package Amazon::S3::Error;
use strict;
use warnings;

use Amazon::S3::Constants qw{ :all };
use Amazon::S3::Log::Placeholders qw{:debug :errors :carp};
use Data::Dumper;

{

  my $err;
  my $errstr;

##############################################################################
  sub err {
    my ( $class, $arg ) = @_;
    my $num_of_args = scalar @_;
    if ( $class && $class eq __PACKAGE__ ) {
      $num_of_args -= 1;    # do not count class
    }
    else {                  # was called as Amazon::S3::Error::err( ...
      $arg = $class;
    }
    if ( $num_of_args > 0 ) {
      $err = $arg;
      return 1;
    }
    else {
      return $err;
    }
  } ## end sub err

##############################################################################
  sub errstr {
    my ( $class, $arg ) = @_;
    my $num_of_args = scalar @_;
    if ( $class && $class eq __PACKAGE__ ) {
      $num_of_args -= 1;    # do not count class
    }
    else {                  # was called as Amazon::S3::Error::err( ...
      $arg = $class;
    }
    if ( $num_of_args > 0 ) {
      $errstr = $arg;
      return 1;
    }
    else {
      return $errstr;
    }
  } ## end sub errstr

}

1;

__END__


