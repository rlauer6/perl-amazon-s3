package Amazon::S3::Bucket;
use strict;
use warnings;

use Amazon::S3::Constants
  qw{ :booleans :chars :reftypes :aws_prefixes :http_methods :http_codes };
use Amazon::S3::Log::Placeholders qw{ :debug :errors :carp };
use Data::Dumper;
use Digest::MD5 qw{ md5 md5_hex };
use Digest::MD5::File qw{ file_md5_hex };
use English qw{ -no_match_vars };
use File::stat;
use IO::File;
use MIME::Base64;

use base qw(Class::Accessor::Fast);
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(qw(bucket creation_date account));

our $VERSION = '1.00';

##############################################################################
sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);

  LOGCROAK 'no bucket'  if !$self->get_bucket();
  LOGCROAK 'no account' if !$self->get_account();
  INFO 'self created, leave "new"';
  TRACE sub { return 'self:', Dumper $self };

  return $self;
} ## end sub new

##############################################################################
sub _uri {
  my ( $self, $key ) = @_;
  TRACE 'Entering to "_uri", key: ', $key // $EMPTY;
  my $uri
    = ($key)
    ? $self->get_bucket() . $SLASH_CHAR . Amazon::S3::Utils::urlencode($key)
    : $self->get_bucket() . $SLASH_CHAR;
  DEBUG 'uri: ', $uri;

  return $uri;
} ## end sub _uri

##############################################################################
# returns bool
sub add_key {
  my ( $self, $args ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $args ne $HASH;

  my $key      = $args->{'key'} || LOGCROAK 'key is required';
  my $headers  = $args->{'headers'};
  my $data     = $args->{'data'};
  my $filename = $args->{'filename'};
  LOGCROAK 'must specify either data or filename' if !( $data || $filename );
  LOGCROAK 'cannot provide both data and filename' if $data && $filename;
  LOGCROAK 'data must be ref to scalar' if $data && ref $data ne $SCALAR;

  DEBUG 'Entering to "add_key", key: ', $key;

  if ( $headers->{'acl_short'} ) {
    TRACE 'ACL presents, validate it: ', $headers->{'acl_short'};
    Amazon::S3::Utils::validate_acl_short( $headers->{'acl_short'} );
    $headers->{$AMAZON_ACL} = $headers->{'acl_short'};
    delete $headers->{'acl_short'};
  } ## end if ( $headers->{'acl_short'...})

  my $response;
  if ($filename) {
    LOGCROAK "file $filename not found or not readable" if !-r $filename;
    DEBUG 'filename: ', $filename;
    my $md5_hex = file_md5_hex($filename);
    TRACE 'md5_hex: ', $md5_hex;
    my $md5 = pack( 'H*', $md5_hex );
    my $md5_base64 = encode_base64($md5);
    chomp $md5_base64;
    TRACE 'md5_base64: ', $md5_base64;

    $headers->{'Content-MD5'} = $md5_base64;

    $headers->{'Content-Length'} ||= -s $filename;
    TRACE 'Content-Length: ', $headers->{'Content-Length'};

    # If we're pushing to a bucket that's under DNS flux, we might get a 307
    # Since LWP doesn't support actually waiting for a 100 Continue response,
    # we'll just send a HEAD first to see what's going on

    DEBUG "Call send_request_expect_nothing for $key via PUT";
    $response = $self->get_account()->send_request_expect_nothing(
      { method   => $PUT,
        path     => $self->_uri($key),
        headers  => $headers,
        filename => $filename,
      }
    );
  } ## end if ($filename)
  else {
    DEBUG 'just plain data';
    #$headers->{'Content-Length'} ||= length ${$data};
    #TRACE 'Content-Length: ', $headers->{'Content-Length'};

    my $md5 = md5( ${$data} );
    my $md5_hex = unpack( 'H*', $md5 );
    TRACE 'md5_hex: ', $md5_hex;
    my $md5_base64 = encode_base64($md5);
    TRACE 'md5_base64: ', $md5_base64;

    $headers->{'Content-MD5'} = $md5_base64;

    DEBUG "Call send_request_expect_nothing for $key via PUT";
    $response = $self->get_account()->send_request_expect_nothing(
      { method  => $PUT,
        path    => $self->_uri($key),
        headers => $headers,
        data    => $data,
      }
    );
  } ## end else [ if ($filename) ]
  TRACE sub { return 'response: ', Dumper $response };

  return $response;
} ## end sub add_key

##############################################################################
sub head_key {
  my ( $self, $args ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $args ne $HASH;
  INFO 'head_key for key: ', $args->{'key'} // $EMPTY;
  $args->{'method'} = $HEAD;
  my $response = $self->get_key($args);
  return $response;
} ## end sub head_key

##############################################################################
sub get_key {
  #my ( $self, $key, $method, $filename ) = @_;
  my ( $self, $args ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $args ne $HASH;
  my $key = $args->{'key'};
  my $method = $args->{'method'} || $GET;
  INFO '"get_key" for key: ', $key // $EMPTY, ' via: ', $method // $EMPTY;

  my $filename
    = ref $args->{'filename'}
    ? ${ $args->{'filename'} }
    : $args->{'filename'};
  TRACE "method: $method, filename: ", $filename // $EMPTY;
  my $account = $self->get_account();

  my $response = $account->send_request(
    { method   => $method,
      path     => $self->_uri($key),
      filename => $filename,
    }
  );

  if ( $response->code == $CODE_404 ) {
    Amazon::S3::Error->err( $response->{'Code'} );
    Amazon::S3::Error->errstr( $response->{'Message'} );
    INFO 'Key: ', $key // $EMPTY, ' not found (404)!';
    return undef;
  }

  $account->_croak_if_response_error($response);

  my $etag = $response->header('ETag');
  TRACE 'Checking and unquote ETag: ', $etag // $EMPTY;
  if ($etag) {
    $etag =~ s/\A"//xms;
    $etag =~ s/"\z//xms;
  }

  my $return = {
    content_length => $response->content_length() || 0,
    content_type   => $response->content_type(),
    etag           => $etag,
    value          => $response->content(),
  };

  # TODO to discuss why 'etag' => '"6b02d8da7826201644285fbf05f827f4-11"'
  ## Validate against data corruption by verifying the MD5
  #if ( $method eq $GET ) {
  #  my $md5 = ( $filename and -f $filename )    # is file and exists
  #    ? file_md5_hex($filename)
  #    : md5_hex( $return->{'value'} );
  #  TRACE 'md5 for verifying data corruption:', $md5 // $EMPTY;
  #  LOGCROAK "Computed and Response MD5's do not match:  $md5 : $etag"
  #    if ( $md5 ne $etag );
  #} ## end if ( $method eq $GET )

  foreach my $header ( $response->headers->header_field_names ) {
    next if $header !~ /$METADATA_PREFIX/i;
    $return->{ lc $header } = $response->header($header);
  }
  TRACE sub { return 'return: ', Dumper $return };

  return $return;
} ## end sub get_key

##############################################################################
sub get_key_filename {
  #my ( $self, $key, $method, $filename ) = @_;
  my ( $self, $args ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $args ne $HASH;
  INFO '"get_key_filename" for key: ', $args->{'key'}      // $EMPTY;
  TRACE 'initial filename: ',          $args->{'filename'} // $EMPTY;

  defined $args->{'filename'} or $args->{'filename'} = $args->{'key'};
  DEBUG 'filename: ', $args->{'filename'};

  my $response = $self->get_key($args);

  return $response;
} ## end sub get_key_filename

##############################################################################
# returns bool
sub delete_key {
  my ( $self, $args ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $args ne $HASH;
  my $key = $args->{'key'} || LOGCROAK 'path is required';
  INFO '"delete_key" for key: ', $key;

  my $response = $self->get_account()->send_request_expect_nothing(
    { method => $DELETE,
      path   => $self->_uri($key),
    }
  );

  return $response;
} ## end sub delete_key

##############################################################################
sub delete_bucket {
  my ($self) = @_;
  LOGCROAK 'Unexpected arguments' if @_;
  INFO 'Entering "delete_bucket"';

  my $response = $self->get_account()->delete_bucket($self);

  return $response;
} ## end sub delete_bucket

##############################################################################
sub list {
  my ( $self, $args ) = @_;
  $args ||= {};
  $args->{'bucket'} = $self->get_bucket();
  INFO '"list" for bucket: ', $args->{'bucket'};
  TRACE sub { return 'conf:', Dumper $args };
  my $response = $self->get_account()->list_bucket($args);

  return $response;
} ## end sub list

##############################################################################
sub list_all {
  my ( $self, $args ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $args ne $HASH;
  $args ||= {};
  $args->{'bucket'} = $self->get_bucket();
  INFO '"list_all" for bucket: ', $args->{'bucket'};
  TRACE sub { return 'conf:', Dumper $args };
  my $response = $self->get_account()->list_bucket_all($args);

  return $response;
} ## end sub list_all

##############################################################################
sub get_acl {
  my ( $self, $args ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $args ne $HASH;
  my $key = $args->{'key'};
  INFO '"get_acl" for key: ', $key // $EMPTY;
  my $account = $self->get_account();

  my $response = $account->send_request(
    { method => $GET,
      key    => $self->_uri($key) . '?acl'
    }
  );

  if ( $response->code == $CODE_404 ) {
    INFO 'Key: ', $key // $EMPTY, ' not found (404)!';
    return undef;
  }

  $account->_croak_if_response_error($response);

  my $content = $response->content();
  DEBUG 'response->content: ', $content;

  return $content;
} ## end sub get_acl

##############################################################################
sub set_acl {
  my ( $self, $args ) = @_;
  $args ||= {};
  INFO 'Entering set_acl';
  TRACE sub { return 'conf: ', Dumper $args };

  if ( !$args->{'acl_xml'} && !$args->{'acl_short'} ) {
    LOGCROAK 'need either "acl_xml" or "acl_short"';
  }

  if ( $args->{'acl_xml'} && $args->{'acl_short'} ) {
    LOGCROAK 'cannot provide both "acl_xml" and "acl_short"';
  }

  my $path = $self->_uri( $args->{'key'} ) . '?acl';
  DEBUG 'path: ', $path;

  my $headers
    = ( $args->{'acl_short'} )
    ? { $AMAZON_ACL => $args->{'acl_short'} }
    : {};
  TRACE sub { return 'hash_ref: ', Dumper $headers };

  my $xml = $args->{'acl_xml'} || $EMPTY;
  TRACE sub { return 'xml: ', Dumper $xml };

  my $response = $self->get_account()->send_request_expect_nothing(
    method  => $PUT,
    key     => $path,
    headers => $headers,
    data    => \$xml,
  );

  return $response;
} ## end sub set_acl

##############################################################################
sub get_location_constraint {
  my ($self) = @_;
  INFO 'Entering get_location_constraint';

  my $xpc = $self->get_account()->send_request(
    { method => $GET,
      path   => $self->get_bucket() . '/?location',
    }
  );
  return undef if !$xpc || $self->get_account()->_remember_errors($xpc);
  TRACE sub { return 'xpc: ', Dumper $xpc };

  my $lc = $xpc->{'content'};
  if ( defined $lc && $lc eq $EMPTY ) {
    $lc = undef;
  }
  DEBUG 'lc: ', $lc // 'UNDEF', ', leave "get_location_constraint"';

  return $lc;
} ## end sub get_location_constraint

# proxy up the err requests

##############################################################################

1;

__END__

