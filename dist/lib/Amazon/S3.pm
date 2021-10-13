package Amazon::S3;
use strict;
use warnings;

use Amazon::S3::Bucket;
use Amazon::S3::Constants
  qw{ :booleans :chars :reftypes :http_methods :aws_prefixes };
use Amazon::S3::Account;
use Amazon::S3::Log::Placeholders qw{ :debug :errors :carp };
use Amazon::S3::Utils;
use Carp;
use Data::Dumper;
use DateTime;
use Digest::SHA qw{ sha256_hex hmac_sha256 hmac_sha256_hex };
use English qw{ -no_match_vars };
use LWP::UserAgent::Determined;
use MIME::Base64 qw{ encode_base64 };
use URI::Escape qw{ uri_escape_utf8 uri_unescape };
use URI;
use XML::Simple;

use base qw(Class::Accessor::Fast);
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(
  qw(
    account region aws_access_key_id aws_secret_access_key token
    secure ua err errstr timeout retry host
    multipart_threshold multipart_chunksize
    allow_legacy_global_endpoint allow_legacy_path_based_bucket
    allow_unsigned_payload
    )
);

our $VERSION = '1.00';

##############################################################################
sub new {
  my ( $class, @args ) = @_;
  my $self = $class->SUPER::new(@args);
  TRACE 'Entering new';

  $self->set_account( Amazon::S3::Account->new(@args) );

  INFO 'self created, leave "new"';
  TRACE sub { return 'self: ', Dumper $self };
  return $self;
} ## end sub new

##############################################################################
sub buckets {
  my ($self) = @_;
  TRACE 'Entering buckets';

  my $xml = $self->get_account()->send_request_expect_xml(
    { method => $GET,
      path   => $EMPTY,
    }
  );
  TRACE sub { return 'Response: ', Dumper $xml };

  if ( !$xml || $self->get_account->_remember_errors($xml) ) {
    return $FALSE;
  }
  INFO 'Response recieved and it is successfull';

  my $owner_id          = $xml->{'Owner'}->{'ID'};
  my $owner_displayname = $xml->{'Owner'}->{'DisplayName'};

  my @buckets_list;
  if ( ref $xml->{'Buckets'} ) {
    my $buckets_aref = $xml->{'Buckets'}->{'Bucket'};
    ref $buckets_aref eq $ARRAY or $buckets_aref = [$buckets_aref];
    foreach my $node ( @{$buckets_aref} ) {
      push @buckets_list, Amazon::S3::Bucket->new(    # create new
        { bucket        => $node->{'Name'},
          creation_date => $node->{'CreationDate'},
          account       => $self->get_account(),
        }
      );
      DEBUG 'node->{name}: ', $node->{'Name'};

    } ## end foreach my $node ( @{$buckets...})
  } ## end if ( ref $xml->{'Buckets'...})

  my $buckets_href = {
    owner_id          => $owner_id,
    owner_displayname => $owner_displayname,
    buckets           => \@buckets_list,
  };
  INFO scalar @{ $buckets_href->{'buckets'} } . ' found, leave "buckets"';
  TRACE sub { return 'buckets_href: ', Dumper $buckets_href };
  return $buckets_href;
} ## end sub buckets

##############################################################################
sub add_bucket {
  my ( $self, $args ) = @_;
  my $bucket = $args->{'bucket'};
  LOGCROAK 'must specify bucket' if !$bucket;
  DEBUG 'Creating bucket: ', $bucket;

  if ( $args->{'headers'}->{'acl_short'} ) {
    Amazon::S3::Utils::validate_acl_short(
      $args->{'headers'}->{'acl_short'} );
  }

  my $headers
    = ( $args->{'headers'}->{'acl_short'} )
    ? { $AMAZON_ACL => $args->{'headers'}->{'acl_short'} }
    : {};

  my $data = $EMPTY;
  if ( defined $args->{'headers'}->{'location_constraint'} ) {
    $data
      = '<CreateBucketConfiguration><LocationConstraint>'
      . $args->{'headers'}->{'location_constraint'}
      . '</LocationConstraint></CreateBucketConfiguration>';
  } ## end if ( defined $args->{'headers'...})

  my $response = $self->get_account()->send_request_expect_nothing(
    { method  => $PUT,
      path    => $bucket . $SLASH_CHAR,
      headers => $headers,
      data    => \$data,
    }
  );
  return $FALSE if !$response;

  my $bucket_instance = $self->bucket( { bucket => $bucket } );
  INFO 'Bucket ', $bucket, ' was created, leave "add_bucket"';
  TRACE sub { return 'bucket_instance: ', Dumper $bucket_instance };
  return $bucket_instance;
} ## end sub add_bucket

##############################################################################
sub bucket {
  my ( $self, $args ) = @_;
  my $bucketname = $args->{'bucket'};
  INFO 'Creating bucket instance: ', $bucketname;

  my $bucket = Amazon::S3::Bucket->new(
    { bucket  => $bucketname,
      account => $self->get_account(),
    }
  );
  TRACE sub { return 'bucket: ', Dumper $bucket };
  return $bucket;
} ## end sub bucket

##############################################################################
sub delete_bucket {
  my ( $self, $args ) = @_;
  my $bucket;
  if ( eval { $args->isa('Amazon::S3::Bucket'); } ) {
    $bucket = $args->bucket();
  }
  else {
    $bucket = $args->{'bucket'};
  }
  LOGCROAK 'must specify bucket' if !$bucket;

  INFO 'Deleting bucket: ', $bucket;
  my $response = $self->get_account()->send_request_expect_nothing(
    { method => $DELETE,
      path   => $bucket . $SLASH_CHAR,
    }
  );
  TRACE sub { return 'response: ', Dumper $response };
  return $response;
} ## end sub delete_bucket

##############################################################################
sub list_bucket {
  my ( $self, $args ) = @_;
  my $bucket = delete $args->{'bucket'};
  LOGCROAK 'must specify bucket' unless $bucket;
  $args ||= {};
  INFO 'List bucket: ', $bucket;

  my $path = $bucket . $SLASH_CHAR;
  if ( %{$args} ) {
    $path .= $QUESTION_MARK
      . join( $AMP_CHAR,
      map { $_ . $EQUAL_SIGN . $self->_urlencode( $args->{$_} ) }
        keys %{$args} );
  } ## end if ( %{$args} )
  DEBUG 'path: ', $path;

  my $xpc = $self->get_account()->send_request_expect_xml(
    { method => $GET,
      path   => $path,
    }
  );
  return undef if !$xpc || $self->get_account()->_remember_errors($xpc);
  INFO 'Response recieved and it is successfull';
  DEBUG 'Bucket name: ', $xpc->{'Name'};
  TRACE sub { return 'Response (r): ', Dumper $xpc };

  my $return = {
    bucket       => $xpc->{'Name'},
    prefix       => $xpc->{'Prefix'},
    marker       => $xpc->{'Marker'},
    next_marker  => $xpc->{'NextMarker'},
    max_keys     => $xpc->{'MaxKeys'},
    is_truncated => (
      scalar $xpc->{'IsTruncated'} eq 'true'
      ? $TRUE
      : $FALSE
    ),
  };

  my @keys;
  foreach my $node ( @{ $xpc->{'Contents'} } ) {
    my $etag = $node->{'ETag'};
    $etag =~ s{(\A" | "\z)}{}gxms if defined $etag;
    push @keys,
      {
      key               => $node->{'Key'},
      last_modified     => $node->{'LastModified'},
      etag              => $etag,
      size              => $node->{'Size'},
      storage_class     => $node->{'StorageClass'},
      owner_id          => $node->{'Owner'}->{'ID'},
      owner_displayname => $node->{'Owner'}->{'DisplayName'},
      };
    DEBUG 'Key: ', $node->{'Key'};
  } ## end foreach my $node ( @{ $xpc->...})
  $return->{'keys'} = \@keys;

  if ( $args->{'delimiter'} ) {
    my @common_prefixes;
    my $strip_delim = qr/$args->{'delimiter'} \z/xms;

    foreach my $node ( $xpc->{'CommonPrefixes'} ) {
      if ( ref $node ne $ARRAY ) {
        $node = [$node];
      }

      foreach my $node_elem ( @{$node} ) {
        next unless exists $node_elem->{'Prefix'};
        my $prefix = $node_elem->{'Prefix'};

        # strip delimiter from end of prefix
        if ($prefix) {
          $prefix =~ s/$strip_delim//xms;
        }

        push @common_prefixes, $prefix;
      } ## end foreach my $node_elem ( @{$node...})
    } ## end foreach my $node ( $xpc->{'CommonPrefixes'...})
    $return->{'common_prefixes'} = \@common_prefixes;
  } ## end if ( $args->{'delimiter'...})

  INFO 'Listed bucket: ', $bucket, ', leave "list_backet"';
  TRACE sub { return 'return: ', Dumper $return };
  return $return;
} ## end sub list_bucket

##############################################################################
sub list_bucket_all {
  my ( $self, $args ) = @_;
  $args ||= {};
  my $bucket = $args->{'bucket'};
  LOGCROAK 'must specify bucket' if !$bucket;
  INFO 'List bucket all: ', $bucket;

  my $response = $self->list_bucket($args);
  TRACE sub { return 'First response: ', Dumper $response };
  return $response if !( ref $response && $response->{'is_truncated'} );
  my $all = $response;

  MARKER:
  while (1) {
    my $next_marker = $response->{'next_marker'}
      || $response->{'keys'}->[$LAST]->{'key'};
    $args->{'marker'} = $next_marker;
    $args->{'bucket'} = $bucket;
    $response         = $self->list_bucket($args);
    TRACE sub { return 'Next response: ', Dumper $response };
    push @{ $all->{'keys'} }, @{ $response->{'keys'} };
    last MARKER if !$response->{'is_truncated'};
  } ## end MARKER: while (1)

  delete $all->{'is_truncated'};
  delete $all->{'next_marker'};
  TRACE sub { return 'all: ', Dumper $all };
  return $all;
} ## end sub list_bucket_all

1;

__END__

