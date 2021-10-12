package Amazon::S3::Constants;
use strict;
use warnings;

use base qw{ Exporter };
use Readonly;

our $VERSION = '1.00';

our @EXPORT      = ();
our @EXPORT_OK   = ();    # See below
our %EXPORT_TAGS = (
  booleans           => [qw{ $EMPTY $TRUE $FALSE $LAST }],
  reftypes           => [qw{ $HASH $ARRAY $CODE $SCALAR $NOTREF }],
  http_methods       => [qw{ $GET $PUT $HEAD $POST $DELETE }],
  http_codes         => [qw{ $CODE_404 }],
  ua_defaults        => [qw{ $DEFAULT_TIMEOUT $KEEP_ALIVE_CACHESIZE }],
  multipart_defaults => [qw{ $DEFAULT_THRESHOLD $DEFAULT_CHUNKSIZE }],
  io_defaults        => [qw{ $READ_BLOCK_SIZE $SEEK_SET }],
  aws_defaults       => [qw{ $AWS_DEFAULT_REGION $AWS_DEFAULT_HOST }],
  aws_bucket_limits  => [qw{ $BUCKET_NAME_MAX_LEN $BUCKET_NAME_MIN_LEN }],
  aws_prefixes => [qw{ $AMAZON_HEADER_PREFIX $METADATA_PREFIX $AMAZON_ACL }],
  aws_regexps  => [qw{ $LGE_CHECK_REGEXP }],
  chars        => [
    qw{ $SPACE $DOT_CHAR $SLASH_CHAR $AMP_CHAR $COLON_CHAR $SEMICOLON_CHAR },
    qw{ $QUESTION_MARK $EQUAL_SIGN },
  ],
);

for my $tag ( keys %EXPORT_TAGS ) {
  push @EXPORT_OK, @{ $EXPORT_TAGS{$tag} };
}
$EXPORT_TAGS{'all'} = [@EXPORT_OK];

# booleans
Readonly our $EMPTY => q{};
Readonly our $TRUE  => 1;
Readonly our $FALSE => $EMPTY;
Readonly our $LAST  => -1;

# reftypes
Readonly our $HASH   => 'HASH';
Readonly our $ARRAY  => 'ARRAY';
Readonly our $CODE   => 'CODE';
Readonly our $SCALAR => 'SCALAR';
Readonly our $NOTREF => $EMPTY;

# http_methods
Readonly our $GET    => 'GET';
Readonly our $PUT    => 'PUT';
Readonly our $HEAD   => 'HEAD';
Readonly our $POST   => 'POST';
Readonly our $DELETE => 'DELETE';

# http_codes
Readonly our $CODE_404 => 404;

# ua_defaults
Readonly our $DEFAULT_TIMEOUT      => 30;
Readonly our $KEEP_ALIVE_CACHESIZE => 10;

# multipart_defaults
Readonly our $DEFAULT_THRESHOLD => 64 * 1024 * 1024;
Readonly our $DEFAULT_CHUNKSIZE => 16 * 1024 * 1024;

# io_defaults
Readonly our $READ_BLOCK_SIZE => 4096;
Readonly our $SEEK_SET        => 0;

# aws_defaults
Readonly our $AWS_DEFAULT_REGION => 'us-east-1';
Readonly our $AWS_DEFAULT_HOST   => 's3.amazonaws.com';

# aws_bucket_limits
Readonly our $BUCKET_NAME_MAX_LEN => 63;
Readonly our $BUCKET_NAME_MIN_LEN => 3;

# aws_prefixes
Readonly our $AMAZON_HEADER_PREFIX => 'x-amz-';
Readonly our $AMAZON_ACL           => 'x-amz-acl';
Readonly our $METADATA_PREFIX      => 'x-amz-meta-';

# aws_regexps
Readonly our $LGE_CHECK_REGEXP =>
  qr{ ( s3 [^.]* [.]         # s3., s3-fips., etc
      (?:dualstack[.])? )  # optional dualstack.
    ( amazonaws[.]com \z ) # amazonaws at the end
  }ixms;

# chars
Readonly our $SPACE          => q{ };
Readonly our $DOT_CHAR       => q{.};
Readonly our $SLASH_CHAR     => q{/};
Readonly our $AMP_CHAR       => q{&};
Readonly our $COLON_CHAR     => q{:};
Readonly our $SEMICOLON_CHAR => q{;};
Readonly our $QUESTION_MARK  => q{?};
Readonly our $EQUAL_SIGN     => q{=};

1;

__END__
