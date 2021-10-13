package Amazon::S3::Payload;
use strict;
use warnings;

use Amazon::S3::Constants
  qw{ :booleans :chars :reftypes :io_defaults :multipart_defaults };
use Amazon::S3::Log::Placeholders qw{ :debug :errors :carp };
use Data::Dumper;
use Digest::SHA qw{ sha256_hex hmac_sha256 hmac_sha256_hex };
use English qw{ -no_match_vars };
use File::stat;

use base qw(Class::Accessor::Fast);
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(
  qw(
    method data allow_unsigned_payload scope datetime signing_key filename
    multipart_threshold multipart_chunksize fh
    _mode _size _digest _filehandler _fh_type
    last_chunk final_chunk remain_payload
    seed_signature prev_signature
    )
);

our $VERSION = '1.00';

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);
  TRACE 'Entering new';

  defined $self->get_multipart_threshold()
    or $self->set_multipart_threshold($DEFAULT_THRESHOLD);
  defined $self->get_multipart_chunksize
    or $self->set_multipart_chunksize($DEFAULT_CHUNKSIZE);

  my $data_sref = $self->get_data();
  if ( ref $data_sref ne $SCALAR || !defined ${ $self->get_data() } ) {
    $data_sref = \do { my $d = $EMPTY };
    $self->set_data($data_sref);
  }
  TRACE 'Data ref: ', ref ${$data_sref}, ' len: ', length ${$data_sref};

  TRACE sub { return 'self: ', Dumper $self };
  return $self;
} ## end sub new

##############################################################################
sub get_size {
  my ($self) = @_;
  my $size = $self->get__size();
  TRACE '_size: ', $size // $EMPTY;
  return $size if defined $size;

  my $filename = $self->get_filename();
  if ($filename) {
    my $stat = stat $filename or die "No $filename: $OS_ERROR";   # File::stat
    $size = $stat->size;
  }
  else {
    my $data_sref = $self->get_data();
    $size = length ${$data_sref};
  }
  $self->set__size($size);
  $self->set_remain_payload($size);
  DEBUG 'size: ', $size;
  return $size;
} ## end sub get_size

##############################################################################
sub get_mode {
  my ($self) = @_;
  my $mode = $self->get__mode();
  TRACE '_mode: ', $mode // $EMPTY;
  return $mode if defined $mode;

  my $size = $self->get_size();
  $mode
    = $self->get_method() eq 'PUT'
    && $self->get_multipart_threshold() > 0
    && $size >= $self->get_multipart_threshold()
    ? 'multipart'
    : 'single';
  $self->set__mode($mode);
  DEBUG 'mode: ', $mode;
  return $mode;
} ## end sub get_mode

##############################################################################
sub get_filehandler {
  my ($self) = @_;
  my $fh = $self->get_fh();
  TRACE '_filehandler: ', $fh // $EMPTY;
  return $fh if defined $fh;

  my $filename  = $self->get_filename();
  my $data_sref = $self->get_data();
  my ($fh_type);
  if ($filename) {
    if ( !open $fh, q{<}, $filename ) {
      LOGCROAK "Cannot open file $filename, because $OS_ERROR";
    }
    $fh->binmode or LOGCROAK "Cannot binmode to $filename: $OS_ERROR";
    $fh_type = 'file';
  } ## end if ($filename)
  else {
    if ( !open $fh, q{<}, $data_sref ) {
      LOGCROAK "Cannot open an in-memory scalar, because $OS_ERROR";
    }
    $fh_type = 'in-memory';
  } ## end else [ if ($filename) ]
  $self->set_fh($fh);
  $self->set__fh_type($fh_type);

  DEBUG 'filehandler was created, type: ', $fh_type;
  return $fh;
} ## end sub get_filehandler

##############################################################################
sub get_digest {
  my ($self) = @_;
  my $digest = $self->get__digest();
  TRACE '_digest: ', $digest // $EMPTY;
  return $digest if defined $digest;

  if ( $self->get_allow_unsigned_payload() ) {
    $digest = 'UNSIGNED-PAYLOAD';
  }
  else {
    my $fh = $self->get_filehandler();
    $digest = Digest::SHA->new(256)->addfile($fh)->hexdigest;
    # Need return file pos to the beginning
    my $seek_ret = seek $fh, 0, $SEEK_SET;
    TRACE 'Seek returned: ', $seek_ret;
  } ## end else [ if ( $self->get_allow_unsigned_payload...)]

  $self->set__digest($digest);
  DEBUG 'digest: ', $digest;
  return $digest;
} ## end sub get_digest

##############################################################################
sub get_content {
  my ($self) = @_;
  #TRACE 'original "multipart_chunksize": ', $self->{'multipart_chunksize'};
  #local $self->{'multipart_chunksize'} = 0;
  #TRACE 'localized "multipart_chunksize": ', $self->{'multipart_chunksize'};

  my ( $data_sref, $data_size ) = $self->get_next_part();
  TRACE 'Content was read, bytes: ', $data_size;
  return $data_sref;
} ## end sub get_content

##############################################################################
sub get_next_part {
  my ($self) = @_;

  my $remain_payload = $self->get_remain_payload();
  TRACE 'remain_payload: ', $remain_payload;

  my $buffer = $EMPTY;
  my $chunk  = $EMPTY;

  my $fh        = $self->get_filehandler();
  my $chunksize = $self->get_multipart_chunksize();

  my $remaining = $remain_payload;
  if ( $chunksize && $remain_payload > $chunksize ) {
    $remaining = $chunksize;
  }
  TRACE 'Initial remainig:', $remaining;
  my $read_size = 0;
  my $bytes_to_read
    = $remaining < $READ_BLOCK_SIZE
    ? $remaining
    : $READ_BLOCK_SIZE;
  TRACE 'Initial bytes_to_read:', $bytes_to_read;
  my $read = 0;

  while ( $bytes_to_read and $read = read $fh, $buffer, $bytes_to_read ) {
    LOGCROAK 'Buffer undef while reading', $OS_ERROR if !defined $buffer;
    LOGCROAK 'Buffer corrupted', $OS_ERROR if $read != length $buffer;
    TRACE 'read: ', $read;
    $chunk .= $buffer;
    $buffer = $EMPTY;
    $remaining -= $read;
    TRACE 'Next remainig:', $remaining;
    $read_size += $read;
    $bytes_to_read
      = $remaining < $READ_BLOCK_SIZE
      ? $remaining
      : $READ_BLOCK_SIZE;
    TRACE 'Next bytes_to_read:', $bytes_to_read;
  } ## end while ( $bytes_to_read and...)

  LOGCROAK 'Error reading file: ', $OS_ERROR if !defined $read;
  LOGCROAK 'Error:', $OS_ERROR if $remaining && !$read;

  my $chunk_size = length $chunk;
  LOGCROAK 'Length does not match: ', if $chunk_size != $read_size;
  TRACE 'chunk length: ', $chunk_size;

  $remain_payload -= $read_size;
  TRACE 'remain payload: ', $remain_payload;
  $self->set_remain_payload($remain_payload);

  return \$chunk, $read_size;
} ## end sub get_next_part

1;

__END__

