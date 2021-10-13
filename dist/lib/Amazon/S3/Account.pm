package Amazon::S3::Account;
use strict;
use warnings;

use Amazon::S3::Constants
  qw{ :booleans :chars :reftypes :http_methods :ua_defaults :aws_defaults :aws_regexps };
use Amazon::S3::Datetime;
use Amazon::S3::Error;
use Amazon::S3::Headers;
use Amazon::S3::Log::Placeholders qw{ :debug :errors :carp };
use Amazon::S3::Multipart;
use Amazon::S3::Payload;
use Amazon::S3::Request;
use Amazon::S3::Signature;
use Data::Dumper;
use Digest::SHA qw{ sha256_hex hmac_sha256 hmac_sha256_hex };
use LWP::UserAgent::Determined;
use XML::Simple;

use base qw(Class::Accessor::Fast);
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(
  qw(
    region aws_access_key_id aws_secret_access_key token
    secure ua err errstr timeout retry host
    datetime payload headers request multipart
    multipart_threshold multipart_chunksize
    allow_legacy_global_endpoint allow_legacy_path_based_bucket
    allow_unsigned_payload bucket
    )
);

our $VERSION = '1.00';

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);
  TRACE 'Entering new';

  LOGCROAK "No aws_access_key_id"     if !$self->get_aws_access_key_id();
  LOGCROAK "No aws_secret_access_key" if !$self->get_aws_secret_access_key();

  my $region = $self->get_region();
  if ( !$region ) {
    # default to US East (N. Virginia) region
    $region = $AWS_DEFAULT_REGION;
    $self->set_region($region);
  }
  DEBUG "region: $region";

  my $host = $self->get_host();
  if ( !defined $host ) {
    $host = $AWS_DEFAULT_HOST;
    INFO "host wasn't defined, use default: $host (can be changed later)";
    $self->set_host($host);
  }

  if (!$self->get_allow_legacy_global_endpoint
    && $host =~ $LGE_CHECK_REGEXP ) {

    my ( $accesspoint_part, $amazonaws_part ) = ( $1, $2 );
    $host = $accesspoint_part . $region . $DOT_CHAR . $amazonaws_part;
    $self->set_host($host);
  } ## end if ( !$self->get_allow_legacy_global_endpoint...)
  DEBUG "host: $host";

  $self->_make_ua();

  TRACE sub { return 'self: ', Dumper $self };
  return $self;
} ## end sub new

##############################################################################
sub _make_ua {
  my ($self) = @_;

  defined $self->get_timeout() or $self->set_timeout($DEFAULT_TIMEOUT);
  my $ua;
  if ( $self->get_retry() ) {
    $ua = LWP::UserAgent::Determined->new(
      keep_alive            => $KEEP_ALIVE_CACHESIZE,
      requests_redirectable => [qw(GET HEAD DELETE PUT)],
    );
    $ua->timing('1,2,4,8,16,32');
  } ## end if ( $self->get_retry(...))
  else {
    $ua = LWP::UserAgent->new(
      keep_alive            => $KEEP_ALIVE_CACHESIZE,
      requests_redirectable => [qw(GET HEAD DELETE PUT)],
    );
  } ## end else [ if ( $self->get_retry(...))]
  DEBUG 'ua_class: ' . ref $ua;

  $ua->timeout( $self->get_timeout() );
  $ua->env_proxy;
  $self->set_ua($ua);

  return $self;
} ## end sub _make_ua

##############################################################################
# make the HTTP::Request object
sub send_request {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  LOGCROAK 'must specify method' if !$context->{'method'};
  LOGCROAK 'must specify path'   if !defined $context->{'path'};
  INFO "make_request method: $context->{'method'}, path: $context->{'path'}";

  my $payload = Amazon::S3::Payload->new(
    { %{$context},
      allow_unsigned_payload => $self->get_allow_unsigned_payload(),
      multipart_threshold    => $self->get_multipart_threshold(),
      multipart_chunksize    => $self->get_multipart_chunksize(),
    }
  );

  my $payload_mode = $payload->get_mode() // $EMPTY;
  DEBUG 'payload_mode: ', $payload_mode;
  $context->{'payload'} = $payload;

  my $response;
  if ( $payload_mode eq 'multipart' ) {
    $response = $self->send_multipart_requests($context);
  }
  elsif ( $payload_mode eq 'single' ) {
    $response = $self->send_single_request($context);
  }
  else {
    LOGCROAK 'Unknown mode: ', $payload_mode;
  }
  if ($response->code !~ /^2\d\d$/) {
    $self->_remember_errors( $response->content, 1 );
  }

  return $response;
} ## end sub send_request

##############################################################################
sub send_single_request {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  my $payload = delete $context->{'payload'};

  my $datetime  = Amazon::S3::Datetime->new();
  my $signature = Amazon::S3::Signature->new(
    { iso8601               => $datetime->get_iso8601(),
      ymd                   => $datetime->get_ymd(),
      region                => $self->get_region(),
      aws_access_key_id     => $self->get_aws_access_key_id(),
      aws_secret_access_key => $self->get_aws_secret_access_key(),
    }
  );

  my $headers = Amazon::S3::Headers->new(
    { headers  => $context->{'headers'},
      metadata => $context->{'metadata'},
      token    => $self->get_token(),
    }
  );

  my ( $host, $url, $path ) = $headers->make_host_url_and_path(
    { path   => $context->{'path'},
      host   => $self->get_host(),
      secure => $self->get_secure(),
      allow_legacy_path_based_bucket =>
        $self->get_allow_legacy_path_based_bucket(),
    }
  );
  my $http_headers = $headers->make_headers(
    { path        => $path,
      url         => $url,
      credential  => $signature->get_credential(),
      scope       => $signature->get_scope(),
      signing_key => $signature->get_signing_key(),
      iso8601     => $datetime->get_iso8601(),
      digest      => $payload->get_digest(),
      method      => $context->{'method'},
    }
  );

  my $request = Amazon::S3::Request->new(
    { %{$context},
      method  => $context->{'method'},
      host    => $host,
      url     => $url,
      headers => $http_headers,
      ua      => $self->get_ua(),
    }
  );

  my $response = $request->send_content( { payload => $payload } );
  INFO 'response was recieved, status: ', $response->code;

  return $response;
} ## end sub send_single_request

##############################################################################
sub send_multipart_requests {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  my $multipart = Amazon::S3::Multipart->new($self);
  my $response  = $multipart->send_requests($context);

  return $response;
} ## end sub send_multipart_requests

##############################################################################
sub send_request_expect_xml {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  my $response = $self->send_request($context);

  my $content = $response->content;
  DEBUG 'Content len: ', length $content, ',type:', $response->content_type;

  return $content if $response->content_type ne 'application/xml';
  return if !$content;
  return $self->_xpc_of_content($content);
} ## end sub send_request_expect_xml

##############################################################################
sub send_request_expect_nothing {
  my ( $self, @args ) = @_;
  INFO 'send_request_expect_nothing';
  my $response = $self->send_request(@args);

  my $content = $response->content;
  INFO 'response was recieved, status: ', $response->code;

  return $TRUE if $response->code =~ /^2\d\d$/;

  # anything else is a failure, and we save the parsed result
  $self->_remember_errors( $response->content, 1 );
  return $FALSE;
} ## end sub send_request_expect_nothing

##############################################################################
sub _croak_if_response_error {
  my ( $self, $response ) = @_;
  INFO '_croak_if_response_error';
  if ( $response->code !~ /^2\d\d$/ ) {
    Amazon::S3::Error->err("network_error");
    Amazon::S3::Error->errstr( $response->status_line );
    LOGCROAK 'Amazon::S3: Amazon responded with '
      . $response->status_line . "\n";
  } ## end unless ( $response->code =~...)
  return $TRUE;
} ## end sub _croak_if_response_error

##############################################################################
sub _xpc_of_content {
  my ( $self, $src, $keep_root ) = @_;
  $keep_root //= $EMPTY;
  INFO 'read XML with length: ', length $src, " KeepRoot: $keep_root";
  return XMLin(
    $src,
    'SuppressEmpty' => '',
    'ForceArray'    => ['Contents'],
    'KeepRoot'      => $keep_root
  );
} ## end sub _xpc_of_content

##############################################################################
# returns 1 if errors were found
sub _remember_errors {
  my ( $self, $src, $keep_root ) = @_;
  $keep_root //= $EMPTY;
  INFO '_remember_errors for scr:', ref $src, " KeepRoot: $keep_root";

  if ( !ref $src && $src !~ m/^[[:space:]]*</ ) {    # if not xml
    ( my $code = $src ) =~ s/^[[:space:]]*\([0-9]*\).*$/$1/;
    Amazon::S3::Error->err($code);
    Amazon::S3::Error->errstr($src);
    if ($code) {
      ERROR "#: $code, str: $src";
      return $TRUE;
    }
    else {
      return $FALSE;
    }
  } ## end if ( !ref $src && $src...)

  my $resp
    = ref $src
    ? $src
    : $self->_xpc_of_content( $src, $keep_root );

  # apparently buckets() does not keep_root
  if ( $resp->{'Error'} ) {
    $resp = $resp->{'Error'};
  }

  if ( $resp->{'Code'} ) {
    Amazon::S3::Error->err( $resp->{'Code'} );
    Amazon::S3::Error->errstr( $resp->{'Message'} );
    ERROR $resp->{Code}, ', str:', $resp->{'Message'};
    return $TRUE;
  } ## end if ( $resp->{Code} )

  TRACE 'No remeber errors';
  return $FALSE;
} ## end sub _remember_errors

1;

__END__

