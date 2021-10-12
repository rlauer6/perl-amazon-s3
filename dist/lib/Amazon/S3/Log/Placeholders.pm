package Amazon::S3::Log::Placeholders;

use strict;
use warnings;

use Carp qw{croak cluck carp confess};
use base 'Exporter';

our @EXPORT      = ();
our @EXPORT_OK   = ();
our %EXPORT_TAGS = (
    debug =>  [ qw{ TRACE DEBUG INFO } ],
    errors => [ qw{ WARN ERROR FATAL } ],
    always => [ qw{ ALWAYS } ],
    carp =>   [ qw{ LOGCROAK LOGCLUCK LOGCARP LOGCONFESS } ],
    core =>   [ qw{ LOGDIE LOGEXIT LOGWARN } ],
);
foreach my $tag (keys %EXPORT_TAGS) {
    foreach my $symbol (@{ $EXPORT_TAGS{$tag} }) {
        push @EXPORT_OK, $symbol;
    }
}
$EXPORT_TAGS{'all'} = [ @EXPORT_OK ];

sub TRACE      { return 1; } # Do not print debug output by default
sub DEBUG      { return 1; } # Do not print debug output by default
sub INFO       { return 1; } # Do not print debug output by default
sub WARN       { my @messages = @_; carp    @messages; return 1; }
sub ERROR      { my @messages = @_; carp    @messages; return 1; }
sub FATAL      { my @messages = @_; carp    @messages; return 1; }
sub ALWAYS     { my @messages = @_; carp    @messages; return 1; }
sub LOGCROAK   { my @messages = @_; croak   @messages; }
sub LOGCLUCK   { my @messages = @_; cluck   @messages; }
sub LOGCARP    { my @messages = @_; carp    @messages; return 1; }
sub LOGCONFESS { my @messages = @_; confess @messages; return 1; }
sub LOGDIE     { my @messages = @_; croak   @messages; }
sub LOGEXIT    { my @messages = @_; carp    @messages; exit 1; }
sub LOGWARN    { my @messages = @_; carp    @messages; return 1; }

# Let's delegate it to Exporter
# but let's keep this code to show how it should works
#sub import {
#    my @args = @_;
#    my $callpkg = caller(0);
#    return _process(import => $callpkg, @args);
#}

sub unimport {
    my @args = @_;
    my $callpkg = caller(0);
    return _process(unimport => $callpkg, @args);
}

sub _process {
    my($action, $callpkg, $pkg, @symbols) = @_;
    cluck 'Wrong action' if $action ne 'import' && $action ne 'unimport';
    if ($pkg ne __PACKAGE__) {
        # Somebody call us as Amazon::S3::Log::Placeholders::import
        unshift @symbols, $pkg;
    }
    my %symbols_to_process = ();
    foreach my $symbol (@symbols) {
        if (q{:} eq substr $symbol, 0, 1) {
            my $tagname = substr $symbol, 1;
            cluck 'Wrong tag' if ! $EXPORT_TAGS{$tagname};
            foreach my $tag_symbol (@{ $EXPORT_TAGS{$tagname} }) {
                $symbols_to_process{$tag_symbol}++;
            }
        }
        else {
            my($direct_symbol) = grep { $symbol eq $_ } @EXPORT_OK;
            cluck 'Wrong symbol' if ! $direct_symbol;
            $symbols_to_process{$direct_symbol}++;
        }
    }
    foreach my $symbol (keys %symbols_to_process) {
        if ($action eq 'import') {
            no strict 'refs';
            *{"$callpkg\::$symbol"} = \&{"$pkg\::$symbol"};
        }
        else {
            undef &{"$callpkg\::$symbol"};
        }
    }
}

1;

