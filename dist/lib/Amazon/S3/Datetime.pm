package Amazon::S3::Datetime;
use strict;
use warnings;

use Amazon::S3::Log::Placeholders qw{ :debug };
use Data::Dumper;
use Readonly;

Readonly my $epoch => 1900;

use base qw{ Class::Accessor::Fast };
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(qw{ ymd hms iso8601 });

our $VERSION = '1.00';

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);
  TRACE 'Entering new';

  my ( $sec, $min, $hour, $mday, $mon, $year ) = gmtime;
  if ( !$self->get_ymd() ) {
    $year += $epoch;
    $mon  += 1;
    $self->set_ymd( sprintf '%04d%02d%02d', $year, $mon, $mday );
  }
  if ( !$self->get_hms() ) {
    $self->set_hms( sprintf '%02d%02d%02d', $hour, $min, $sec );
  }

  my $req_time = $self->get_ymd() . 'T' . $self->get_hms() . 'Z';
  $self->set_iso8601($req_time);

  DEBUG 'req_time: ', $req_time, 'leave "new"';

  TRACE sub { return 'self: ', Dumper $self };
  return $self;
} ## end sub new

1;

__END__

