package Amazon::S3::Utils;
use strict;
use warnings;

use Amazon::S3::Constants qw{ :booleans :aws_bucket_limits };
use Amazon::S3::Log::Placeholders qw{:debug :errors :carp};
use Data::Dumper;
use URI::Escape qw(uri_escape_utf8 uri_unescape);

our $VERSION = '1.00';

sub validate_acl_short {
  my ($policy_name) = @_;

  if (
    !grep( { $policy_name eq $_ }
      qw(private public-read public-read-write authenticated-read) ) ) {
    LOGCROAK "$policy_name is not a supported canned access policy";
  }

  INFO 'Policy validated: ', $policy_name;
  return $TRUE;
} ## end sub validate_acl_short

# EU buckets must be accessed via their DNS name. This routine figures out if
# a given bucket name can be safely used as a DNS name.
sub is_dns_bucket {
  my ($bucketname) = @_;
  INFO 'Check _is_dns_bucket for bucket: ', $bucketname;

  if ( length $bucketname > $BUCKET_NAME_MAX_LEN ) {
    return $FALSE;
  }
  if ( length $bucketname < $BUCKET_NAME_MIN_LEN ) {
    return $FALSE;
  }
  return $FALSE unless $bucketname =~ m{\A [a-z0-9][a-z0-9.-]+ \z}xms;
  my @components = split /[.]/xms, $bucketname;
  for my $c (@components) {
    return $FALSE if $c =~ m{\A-}xms;
    return $FALSE if $c =~ m{-\z}xms;
    return $FALSE if $c eq $EMPTY;
  }
  INFO $bucketname, ' _is_ dns bucket';
  return $TRUE;
} ## end sub is_dns_bucket

sub trim {
  my ($value) = @_;
  $value =~ s/\A \s+//xms;
  $value =~ s/\s+ \z//xms;
  TRACE "trimmed value: $value, leave '_trim'";
  return $value;
} ## end sub trim

sub urlencode {
  my ( $unencoded, $noencode ) = @_;
  $noencode //= $EMPTY;    # Empty string
  TRACE "_urlencode for '$unencoded', noencode: '$noencode'";
  my $uri = uri_escape_utf8( $unencoded, '^A-Za-z0-9-._~' . $noencode );
  DEBUG "URI was encoded: $uri, leave '_urlencode'";
  return $uri;
} ## end sub urlencode

1;

__END__

