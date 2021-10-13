package Amazon::S3::Headers;
use strict;
use warnings;

use Amazon::S3::Constants
  qw{ :booleans :chars :reftypes :aws_prefixes :http_methods };
use Amazon::S3::Log::Placeholders qw{ :debug :errors :carp };
use Amazon::S3::Utils;
use Carp;
use Data::Dumper;
use DateTime;
use Digest::SHA qw{ sha256_hex hmac_sha256 hmac_sha256_hex };
use English qw{ -no_match_vars };
use HTTP::Headers;
use Scalar::Util qw{ reftype blessed };
use URI::Escape qw{ uri_escape_utf8 uri_unescape };
use URI;

use base qw(Class::Accessor::Fast);
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(
  qw(
    headers hh metadata token
    secure

    host secure token method path in_headers in_metadata
    aws_access_key_id
    payload datetime scope signing_key
    allow_legacy_path_based_bucket
    headers protocol url
    )
);

our $VERSION = '1.00';

##############################################################################
sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);
  TRACE 'Entering new';

  my $original_headers = $self->get_headers();
  my $headers_reftype = ( reftype $original_headers) // $EMPTY;
  $headers_reftype eq $HASH or $original_headers = {};
  if ( blessed($original_headers)
    && $original_headers->isa('HTTP::Headers') ) {

    $self->set_hh($original_headers);
  }
  else {
    $self->set_hh( HTTP::Headers->new() );
    # generates an HTTP::Headers objects given one hash that represents http
    # headers to set and another hash that represents an object's metadata.
    foreach my $key ( keys %{$original_headers} ) {
      my $val = $original_headers->{$key};
      $self->get_hh()->header( $key => $val );
      TRACE "Header: $key => $val";
    }
  } ## end else [ if ( blessed($original_headers...))]

  ref $self->get_metadata() eq $HASH or $self->set_metadata( {} );
  foreach my $key ( keys %{ $self->get_metadata() } ) {
    my $val = $self->get_metadata->{$key};
    $self->get_hh()->header( "${METADATA_PREFIX}${key}" => $val );
    TRACE "Metadata: ${METADATA_PREFIX}{$key} => $val";
  }

  if ( $self->get_token() ) {
    my $token_header_name = $AMAZON_HEADER_PREFIX . 'security-token';
    DEBUG 'adding token: ', $self->get_token();
    $self->get_hh()->header( $token_header_name => $self->get_token() );
  }

  return $self;
} ## end sub new

##############################################################################
sub make_host_url_and_path {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  my $host = $context->{'host'} || LOGCROAK 'must specify host';
  my $path = $context->{'path'} // LOGCROAK 'must specify path';
  my $secure = $context->{'secure'} // 0;
  DEBUG "initial host: $host, initial path: $path";

  my $url;
  my $protocol = $secure ? 'https' : 'http';
  my $allow_legacy = $context->{'allow_legacy_path_based_bucket'};
  DEBUG "proto: $protocol, allow_legacy_path_based...:", $allow_legacy // 0;

  if (!$allow_legacy
    && $path =~ m{\A ([^/?]+) (.*) \z}xms
    && Amazon::S3::Utils::is_dns_bucket($1) ) {

    my $bucket_name = $1;
    my $rest_path   = $2;
    $host = "$bucket_name.$host";
    $url  = "$protocol://$host" . $rest_path;
    $path =~ s{\A [^/?]+ }{}xms;    # cut bucket name
  } ## end if ( !$allow_legacy &&...)
  else {
    $path =~ s{\A /}{}xms;          # remove leading '/' before bucket name
    $url  = "$protocol://$host/$path";
    $path = "/$path";
  }
  DEBUG "new host: $host, new path: $path, url: $url";

  $self->get_hh()->header( host => $host );
  return $host, $url, $path;
} ## end sub make_host_url_and_path

##############################################################################
sub make_headers {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  LOGCROAK 'must specify host'    if !$self->get_hh()->{'host'};
  LOGCROAK 'must specify iso8601' if !$context->{'iso8601'};
  LOGCROAK 'must specify digest'  if !$context->{'digest'};

  $self->get_hh()->header( 'x-amz-date'           => $context->{'iso8601'} );
  $self->get_hh()->header( 'x-amz-content-sha256' => $context->{'digest'} );

  if ( !exists $self->get_hh()->{'Authorization'} ) {
    DEBUG 'Call _add_auth_header, because headers->{Authorization} missed';
    $self->_add_auth_header($context);
  }

  TRACE sub { return 'self: ', Dumper $self };
  my $http_headers = $self->get_hh();
  DEBUG sub { return 'http_headers: ', Dumper $http_headers };

  return $http_headers;
} ## end sub make_headers

##############################################################################
sub _add_auth_header {
  my ( $self, $context ) = @_;
  INFO "_add_auth_header";
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  my ( $signature, $signed_headers )
    = $self->_get_headers_signature($context);
  TRACE "signature recieved, signature: $signature";
  TRACE sub { return 'signed_headers: ', Dumper $signed_headers };

  $self->_include_authorization_header(
    { signed_headers => $signed_headers,
      signature      => $signature,
      credential     => $context->{'credential'},
    }
  );

  return $self;
} ## end sub _add_auth_header

##############################################################################
sub _get_headers_signature {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  LOGCROAK 'must specify iso8601'     if !$context->{'iso8601'};
  LOGCROAK 'must specify scope'       if !$context->{'scope'};
  LOGCROAK 'must specify signing_key' if !$context->{'signing_key'};

  my ( $canonical_request, $signed_headers )
    = $self->_get_canonical_request($context);

  my $string_to_sign = "AWS4-HMAC-SHA256\n";
  $string_to_sign .= $context->{'iso8601'} . "\n";

  # Scope binds the resulting signature
  # to a specific date, an AWS region, and a service.
  $string_to_sign .= $context->{'scope'} . "\n";
  $string_to_sign .= sha256_hex($canonical_request);
  DEBUG 'string_to_sign: ', $string_to_sign;

  my $signature
    = hmac_sha256_hex( $string_to_sign, $context->{'signing_key'} );
  DEBUG 'SIGNATURE: ', $signature;

  return $signature, $signed_headers;
} ## end sub _get_headers_signature

##############################################################################
sub _get_canonical_request {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  LOGCROAK 'must specify method' if !$context->{'method'};
  LOGCROAK 'must specify digest' if !$context->{'digest'};

  my ( $canonical_uri, $uri ) = $self->_get_canonical_uri($context);
  my $canonical_query_string
    = $self->_get_canonical_query_string( { uri => $uri } );

  my ( $canonical_headers, $signed_headers ) = $self->_get_canonical_headers;
  my $hashed_payload = $context->{'digest'};

  # From: https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
  # HTTPMethod is one of the HTTP methods, for example GET, PUT, HEAD, and DELETE
  my $canonical_request = $context->{'method'} . "\n";

  # CanonicalURI is the URI-encoded version of the absolute path component of the URI
  $canonical_request .= "$canonical_uri\n";

  # CanonicalQueryString specifies the URI-encoded query string parameters.
  $canonical_request .= "$canonical_query_string\n";

  # CanonicalHeaders is a list of request headers with their values.
  $canonical_request .= "$canonical_headers\n";

  # SignedHeaders is an alphabetically sorted,
  # semicolon-separated list of lowercase request header names.
  $canonical_request .= "$signed_headers\n";
  $canonical_request .= $hashed_payload;
  DEBUG 'canonical_request: ', $canonical_request;

  return $canonical_request, $signed_headers;
} ## end sub _get_canonical_request

##############################################################################
sub _get_canonical_uri {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;
  my $path = $context->{'path'} || LOGCROAK 'path is required';
  DEBUG "RAW PATH: $path";

  my $uri = URI->new( uri_unescape($path) );
  DEBUG 'URI PATH: ', $uri->path();

  my $canonical_uri = uri_unescape( $uri->path );
  utf8::decode($canonical_uri);
  DEBUG "DECODED URI: $canonical_uri";

  $canonical_uri
    = Amazon::S3::Utils::urlencode( $canonical_uri, $SLASH_CHAR );
  DEBUG "CANONICAL URI: $canonical_uri";

  return $canonical_uri, $uri;
} ## end sub _get_canonical_uri

##############################################################################
sub _get_canonical_query_string {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  my $canonical_query_string = $EMPTY;

  my $uri         = $context->{'uri'} || LOGCROAK 'uri is required';
  my $query       = $uri->query() // $EMPTY;
  my @query_pairs = split /$AMP_CHAR/xms, $query;
  my %params      = ();
  foreach my $q_pair (@query_pairs) {
    my ( $key, $val ) = split /$EQUAL_SIGN/xms, $q_pair, 2;
    $params{$key} = $val // $EMPTY;
  }

  foreach my $key ( sort keys %params ) {
    $canonical_query_string .= $canonical_query_string ? $AMP_CHAR : $EMPTY;
    $canonical_query_string .= Amazon::S3::Utils::urlencode($key);
    $canonical_query_string .= $EQUAL_SIGN;
    $canonical_query_string .= Amazon::S3::Utils::urlencode( $params{$key} );
  } ## end foreach my $key ( sort keys...)
  DEBUG 'canonical_query_string: ', $canonical_query_string;

  return $canonical_query_string;
} ## end sub _get_canonical_query_string

##############################################################################
sub _get_canonical_headers {
  my ($self) = @_;

  my $headers           = $self->get_hh();
  my $canonical_headers = $EMPTY;
  my $signed_headers    = $EMPTY;
  foreach my $field_name (    # See decsription above
    sort { lc($a) cmp lc($b) } $headers->header_field_names()
    ) {

    $canonical_headers .= lc($field_name);
    $canonical_headers .= $COLON_CHAR;
    $canonical_headers
      .= Amazon::S3::Utils::trim( $headers->header($field_name) );
    $canonical_headers .= "\n";

    $signed_headers .= $signed_headers ? $SEMICOLON_CHAR : $EMPTY;
    $signed_headers .= lc($field_name);
  } ## end foreach my $field_name (  sort...)

  DEBUG 'canonical_headers: ', $canonical_headers;
  DEBUG 'signed_headers: ',    $signed_headers;

  return $canonical_headers, $signed_headers;
} ## end sub _get_canonical_headers

##############################################################################
sub _include_authorization_header {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;
  LOGCROAK 'must specify signed_headers' if !$context->{'signed_headers'};
  LOGCROAK 'must specify signature'      if !$context->{'signature'};
  LOGCROAK 'must specify credential'     if !$context->{'credential'};

  my $autorization_header =

    # The algorithm that was used to calculate the signature.
    # You must provide this value when you use AWS Signature Version 4 for authentication.
    # The string specifies AWS Signature Version 4 (AWS4) and the signing algorithm (HMAC-SHA256).
    "AWS4-HMAC-SHA256"

    # * There is space between the first two components, AWS4-HMAC-SHA256 and Credential
    # * The subsequent components, Credential, SignedHeaders, and Signature are separated by a comma.
    . $SPACE

    # Credential:
    # Your access key ID and the scope information, which includes the date, region, and service that were used to calculate the signature.
    # This string has the following form: <your-access-key-id>/<date>/<aws-region>/<aws-service>/aws4_request
    # Where:
    # * <date> value is specified using YYYYMMDD format.
    # * <aws-service> value is s3 when sending request to Amazon S3.
    . "Credential=$context->{'credential'},"

    # SignedHeaders:
    # A semicolon-separated list of request headers that you used to compute Signature.
    # The list includes header names only, and the header names must be in lowercase.
    . "SignedHeaders=$context->{'signed_headers'},"

    # Signature:
    # The 256-bit signature expressed as 64 lowercase hexadecimal characters.
    . "Signature=$context->{'signature'}";

  $self->get_hh()->header( Authorization => $autorization_header );

  DEBUG 'Authorization header: ', $autorization_header;
  return $self;
} ## end sub _include_authorization_header

1;

__END__

