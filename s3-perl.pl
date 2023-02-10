#!/usr/bin/env perl

# script to exercise a subset of Amazon::S3 and Amazon::S3::Bucket

use strict;
use warnings;

use Amazon::Credentials;
use Amazon::S3;
use Carp;
use Data::Dumper;
use English qw(-no_match_vars);
use File::HomeDir;
use Getopt::Long qw(:config no_ignore_case);
use Log::Log4perl qw(:easy);

use Readonly;

Readonly our $TRUE  => 1;
Readonly our $FALSE => 0;

########################################################################
sub _bucket {
########################################################################
  my ( $s3, $bucket_name ) = @_;

  return $s3->bucket(
    { bucket        => $bucket_name,
      verify_region => $TRUE
    }
  );
}

########################################################################
sub add_key {
########################################################################
  my ( $s3, %options ) = @_;

  my $bucket = _bucket( $s3, $options{bucket} );

  croak "no file or file does not exist\n"
    if !$options{file} || !-e $options{file};

  DEBUG( Dumper( [ $bucket->head_key( $options{key} ) ] ) );

  DEBUG( Dumper( [ $bucket, $s3->last_response ] ) );

  return $bucket->add_key_filename( $options{key}, $options{file} );
}

########################################################################
sub create_bucket {
########################################################################
  my ( $s3, %options ) = @_;

  return $s3->add_bucket(
    { bucket => $options{bucket},
      region => $options{region} // 'us-east-1'
    }
  );
}

########################################################################
sub copy_key {
########################################################################
  my ( $s3, %options ) = @_;

  croak "no name for copy\n"
    if !$options{name};

  my $bucket = _bucket( $s3, $options{bucket} );

  return $bucket->copy_object(
    source => $options{key},
    key    => $options{name},
  );
}

########################################################################
sub get_key {
########################################################################
  my ( $s3, %options ) = @_;

  my $bucket = _bucket( $s3, $options{bucket} );

  if ( $options{file} ) {
    return $bucket->get_key_filename( $options{key}, 'GET', $options{file} );
  }
  else {
    return $bucket->get_key( $options{key} );
  }
}

########################################################################
sub delete_key {
########################################################################
  my ( $s3, %options ) = @_;

  my $bucket = _bucket( $s3, $options{bucket} );

  return $bucket->delete_key( $options{key} );
}

########################################################################
sub remove_bucket {
########################################################################
  my ( $s3, %options ) = @_;

  return $s3->delete_bucket( { bucket => $options{bucket} } );
}

########################################################################
sub list_bucket_keys {
########################################################################
  my ( $s3, %options ) = @_;

  return $s3->list_bucket_all_v2( { bucket => $options{bucket} } );
}

########################################################################
sub show_buckets {
########################################################################
  my ( $s3, %options ) = @_;

  return $s3->buckets();
}

########################################################################
sub help {
########################################################################
  print <<"END_OF_HELP";
usage: $PROGRAM_NAME options command args

Options
-------
-b, --bucket   name of the bucket
-d, --debug    debug output
-h, --help     this
-H, --host     default: s3.amazonaws.com
-p, --profile  AWS credentials profile, default is hunt for them
-r, --region   region, default: us-east-1

         Commands         Args           Description
         --------         ----           -----------
Buckets  create(-bucket)  -              create a new bucket
         list(-bucket)    -              list the contents of a bucket
         remove(-bucket)  -              remove a bucket (must be empty)
         show-(buckets)   -                                
         
Keys     add(-key)        key filename   add an object
         copy(-key)       key name       copy an object
         delete(-key)     key            delete an object
         get(-key)        key [filename] fetch an object and optionally store to file

END_OF_HELP

  return;
}

########################################################################
sub main {
########################################################################

  my %options;

  GetOptions(
    \%options,  'bucket=s', 'debug', 'host|H=s',
    'region=s', 'help|h',   'profile=s'
  );

  if ( $options{help} ) {
    help();
    exit 0;
  }

  local $ENV{DEBUG} = $options{debug};

  Log::Log4perl->easy_init(
    { level  => ( $ENV{DEBUG} ? $DEBUG : $INFO ),
      layout => '[%d] (%r/%R) - %M:%L - %m%n',
    }
  );

  my $command = lc( shift @ARGV // q{} );
  $command =~ s/-(.*)$//xsm;

  my $args = [@ARGV]; # save for debugging

  $options{key} = shift @ARGV;

  $options{file} = shift @ARGV;
  $options{name} = $options{file}; # copy key

  my $host = $options{host} // q{};
  $host =~ s/^https?:\/\///xsm;

  my $s3 = Amazon::S3->new(
    { credentials =>
        Amazon::Credentials->new( { profile => $options{profile} } ),
      debug  => $ENV{DEBUG},
      host   => $host,
      logger => Log::Log4perl->get_logger(),
    }
  );

  DEBUG(
    sub {
      return sprintf "%s, %s, %s\n", $s3->err // q{}, $s3->errstr // q{},
        Dumper( [ $s3->error ] );
    }
  );

  my %actions = (
    add    => [ 'key',    \&add_key ],
    create => [ 'bucket', \&create_bucket ],
    copy   => [ 'key',    \&copy_key ],
    delete => [ 'key',    \&delete_key ],
    get    => [ 'key',    \&get_key ],
    list   => [ 'bucket', \&list_bucket_keys ],
    remove => [ 'bucket', \&remove_bucket ],
    show   => [ 'bucket', \&show_buckets ],
  );

  if ( $command && $actions{$command} ) {
    my ( $type, $sub ) = @{ $actions{$command} };

    if ( $type eq 'bucket' ) {
      $options{bucket} = $ARGV[0] || $options{bucket};
    }
    else {
      croak "no key\n"
        if !$options{key};
    }

    croak "bucket name is required\n"
      if !$options{bucket} && $command ne 'show';

    my $result = eval { $sub->( $s3, %options ); };

    if ( !$result || $EVAL_ERROR ) {
      INFO(
        sub {
          return
            sprintf "COMMAND: %s\nHOST: %s\nARGS: %s\nerror: %s: %s: %s\n",
            $command, $options{host},
            ( sprintf '[%s]', join q{,}, @{$args} ), $s3->err, $s3->errstr,
            Dumper( [ $s3->error, 'EVAL_ERROR', $EVAL_ERROR ] );
        }
      );
    }

    print Dumper( [ 'result', $result ] );
  }

  return;
}

main();

1;

__END__
