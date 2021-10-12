package Amazon::S3::Signature;
use strict;
use warnings;

use Amazon::S3::Constants qw{ :all };
use Amazon::S3::Log::Placeholders qw{ :debug :errors :carp };
use Data::Dumper;
use Digest::SHA qw{ sha256_hex hmac_sha256 hmac_sha256_hex };

use base qw(Class::Accessor::Fast);
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(
  qw(
    iso8601 ymd aws_access_key_id aws_secret_access_key region
    )
);

#    region aws_access_key_id aws_secret_access_key token
#    secure ua err errstr timeout retry host
#    datetime payload headers request multipart
#    multipart_threshold multipart_chunksize
#    allow_legacy_global_endpoint allow_legacy_path_based_bucket
#    allow_unsigned_payload
#    )
#);

our $VERSION = '1.00';

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);
  TRACE 'Entering new';

  LOGCROAK "No aws_access_key_id"     if !$self->get_aws_access_key_id();
  LOGCROAK "No aws_secret_access_key" if !$self->get_aws_secret_access_key();

  return $self;
} ## end sub new

sub get_scope {
  my ($self) = @_;

  # Credential:
  # Your access key ID and the scope information,
  # which includes the date, region, and service
  # that were used to calculate the signature.
  # This string has the following form:
  # <your-access-key-id>/<date>/<aws-region>/<aws-service>/aws4_request
  # Where:
  # * <date> value is specified using YYYYMMDD format.
  # * <aws-service> value is s3 when sending request to Amazon S3.
  my $date   = $self->get_ymd();
  my $region = $self->get_region();
  DEBUG "date: $date, region: $region";

  my $scope = "$date/$region/s3/aws4_request";
  DEBUG "scope: $scope";
  return $scope;
} ## end sub get_scope

sub get_credential {
  my ($self) = @_;

  my $credential = $self->get_aws_access_key_id() . q{/} . $self->get_scope();
  return $credential;
} ## end sub get_credential

sub get_signing_key {
  my ($self) = @_;

  my $date_key = hmac_sha256( $self->get_ymd(),
    'AWS4' . $self->get_aws_secret_access_key() );
  TRACE sub { return 'date_key: ', unpack 'H*', $date_key };
  my $date_region_key = hmac_sha256( $self->get_region(), $date_key );
  TRACE sub { return 'date_region_key: ', unpack 'H*', $date_region_key };
  my $date_region_service_key = hmac_sha256( 's3', $date_region_key );
  TRACE sub {
    return 'date_region_service_key: ', unpack 'H*', $date_region_service_key;
  };
  my $signing_key = hmac_sha256( 'aws4_request', $date_region_service_key );
  TRACE sub { return 'signing_key: ', unpack 'H*', $signing_key };

  return $signing_key;
} ## end sub get_signing_key

1;

__END__


