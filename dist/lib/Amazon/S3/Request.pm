package Amazon::S3::Request;
use strict;
use warnings;

use Amazon::S3::Constants qw{ :all };
use Amazon::S3::Log::Placeholders qw{:debug :errors :carp};
use Data::Dumper;

use base qw(Class::Accessor::Fast);
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(qw( method url headers request ua host ));

our $VERSION = '1.00';

##############################################################################
sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);
  TRACE 'Entering new';

  LOGCROAK 'Need method'  if !defined $self->get_method();
  LOGCROAK 'Need url'     if !defined $self->get_url();
  LOGCROAK 'Need headers' if !defined $self->get_headers();

  my $request = HTTP::Request->new( # create instance
    $self->get_method(),
    $self->get_url(),
    $self->get_headers(),
  );
  TRACE sub { return 'The request without content: ', Dumper $request };

  $self->set_request($request);

  TRACE sub { return 'self: ', Dumper $self };
  return $self;
} ## end sub new

##############################################################################
sub send_content {
  #my ($self, $request, $filename) = @_;
  my ( $self, $args ) = @_;
  my $request  = $self->get_request();
  my $filename = $args->{'filename'};
  my $payload  = $args->{'payload'};

  INFO '_do_http with request and filename: ', $filename || 'EMPTY';

  my $response;

  $request->content(${ $payload->get_content() } );
  $response = $self->get_ua()->request( $request, $filename );
  TRACE sub { return 'First Response: ', Dumper $response };

  return $response;
} ## end sub send_request

1;

__END__

