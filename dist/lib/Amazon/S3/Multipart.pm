package Amazon::S3::Multipart;
use strict;
use warnings;

use Amazon::S3::Account;
use Amazon::S3::Constants qw{ :booleans :chars :reftypes :http_methods };
use Amazon::S3::Log::Placeholders qw{ :debug :errors :carp };
use Data::Dumper;
use Digest::MD5 qw{ md5 md5_hex };
use Digest::MD5::File qw(file_md5 file_md5_hex);
use MIME::Base64;
use XML::LibXML;

use base qw(Class::Accessor::Fast);
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(
  qw(
    account payload
    multipart_threshold multipart_chunksize
    method path headers data metadata bucket
    etags
    )
);

our $VERSION = '1.00';

##############################################################################
sub new {
  my ( $class, @args ) = @_;
  my $self = $class->SUPER::new(@args);
  TRACE 'Entering new';

  $self->set_account(
    Amazon::S3::Account->new(    # pass context
      @args,
      multipart_threshold => 0,
    )
  );

  return $self;
} ## end sub new

##############################################################################
sub send_requests {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  my $payload = delete $context->{'payload'};
  my $path    = $context->{'path'} || LOGCROAK 'path is required';

  my $mode = $payload->get_mode() // $EMPTY;
  LOGCROAK 'Incorrect mode: ', $mode if $mode ne 'multipart';

  my $upload_id   = $self->initiate_multipart_upload($context);
  my $parts_href  = {};
  my $part_number = 1;

  my ( $part_sref, $part_size ) = $payload->get_next_part();
  while ($part_size) {
    my $etag = $self->upload_part_of_multipart_upload(
      { path        => $path,
        upload_id   => $upload_id,
        part_number => $part_number,
        data        => $part_sref,
        length      => $part_size,
      }
    );
    $parts_href->{$part_number} = $etag;
    $part_number++;
    ( $part_sref, $part_size ) = $payload->get_next_part();
  } ## end while ($part_size)

  my $resp = $self->complete_multipart_upload(
    { path       => $path,
      upload_id  => $upload_id,
      parts_href => $parts_href,
    }
  );

  return $resp;
} ## end sub send_requests

##############################################################################
#
# Initiate a multipart upload operation
# This is necessary for uploading files > 5Gb to Amazon S3
# Returns the Upload ID assigned by Amazon,
# This is needed to identify this particular upload in other operations
#
sub initiate_multipart_upload {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  my $path    = $context->{'path'} || LOGCROAK 'path is required';
  my $headers = $context->{'headers'};

  INFO '"initiate_multipart_upload" for key: ', $path;

  my $account = $self->get_account();

  my $response = $account->send_request(
    { method  => $POST,
      path    => $path . '?uploads',
      headers => $headers,
    }
  );

  $account->_croak_if_response_error($response);

  my $xml = $account->_xpc_of_content( $response->content );

  DEBUG 'xml->{UploadId}: ', $xml->{UploadId};
  return $xml->{UploadId};
} ## end sub initiate_multipart_upload

##############################################################################
#
# Upload a part of a file as part of a multipart upload operation
# Each part must be at least 5mb (except for the last piece).
# This returns the Amazon-generated eTag for the uploaded file segment.
# It is necessary to keep track of the eTag for each part number
# The complete operation will want a sequential list of all the part
# numbers along with their eTags.
#
sub upload_part_of_multipart_upload {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  my $path      = $context->{'path'}      || LOGCROAK 'path is required';
  my $upload_id = $context->{'upload_id'} || LOGCROAK 'upload_id is required';
  my $part_number = $context->{'part_number'}
    || LOGCROAK 'part_number is required';
  my $data = $context->{'data'};

  INFO 'Entering upload_part_of_multipart_upload for key: ', $path;
  TRACE "upload_id: $upload_id, part_number: $part_number";

  my $headers = {};
  my $account = $self->get_account();

  # Make sure length and md5 are set
  my $md5 = md5( ${$data} );
  my $md5_hex = unpack( 'H*', $md5 );
  TRACE 'md5_hex: ', $md5_hex;
  my $md5_base64 = encode_base64($md5);
  TRACE 'md5_base64: ', $md5_base64;

  $headers->{'Content-MD5'}    = $md5_base64;
  $headers->{'Content-Length'} = $context->{'length'};
  TRACE 'Content-Length: ', $headers->{'Content-Length'};

  my $params = "?partNumber=${part_number}&uploadId=${upload_id}";
  DEBUG 'params: ', $params;
  my $response = $account->send_request(
    { method  => $PUT,
      path    => $path . $params,
      headers => $headers,
      data    => $data,
    }
  );

  $account->_croak_if_response_error($response);

  # We'll need to save the etag for later when completing the transaction
  my $etag = $response->header('ETag');
  DEBUG 'Checking and unquote ETag: ', $etag // $EMPTY;
  if ($etag) {
    $etag =~ s/\A "//xms;
    $etag =~ s/" \z//xms;
  }

  return $etag;
} ## end sub upload_part_of_multipart_upload

##############################################################################
#
# Inform Amazon that the multipart upload has been completed
# You must supply a hash of part Numbers => eTags
# For amazon to use to put the file together on their servers.
#
sub complete_multipart_upload {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  my $path      = $context->{'path'}      || LOGCROAK 'path is required';
  my $upload_id = $context->{'upload_id'} || LOGCROAK 'upload_id is required';
  my $parts_href = $context->{'parts_href'}
    || LOGCROAK 'Part number => etag hashref is required';

  # The complete command requires sending a block of xml containing all
  # the part numbers and their associated etags (returned from the upload)

  #build XML doc
  my $xml_doc = XML::LibXML::Document->new( '1.0', 'UTF-8' );
  my $root_element = $xml_doc->createElement('CompleteMultipartUpload');
  $xml_doc->addChild($root_element);
  TRACE sub { return 'xml_doc: ', Dumper $xml_doc };

  # Add the content
  foreach my $part_num ( sort { $a <=> $b } keys %{$parts_href} ) {

    # For each part, create a <Part> element with the part number & etag
    my $part = $xml_doc->createElement('Part');
    $part->appendTextChild( 'PartNumber' => $part_num );
    $part->appendTextChild( 'ETag'       => $parts_href->{$part_num} );
    TRACE "PartNumber: $part_num, ETag: $parts_href->{$part_num}";
    $root_element->addChild($part);
  } ## end foreach my $part_num ( sort...)

  my $content    = $xml_doc->toString;
  my $md5        = md5($content);
  my $md5_base64 = encode_base64($md5);
  chomp $md5_base64;
  TRACE 'md5_base64: ', $md5_base64;

  my $headers = {
    'Content-MD5'    => $md5_base64,
    'Content-Length' => length $content,
    'Content-Type'   => 'application/xml'
  };
  TRACE sub { return 'headers: ', Dumper $headers };

  my $account = $self->get_account();
  my $params  = '?uploadId=' . $upload_id;
  TRACE 'params: ', $params;
  my $response = $account->send_request(
    { method  => $POST,
      path    => $path . $params,
      headers => $headers,
      data    => \$content,
    }
  );

  $account->_croak_if_response_error($response);

  return $response;
} ## end sub complete_multipart_upload

##############################################################################
#
# Stop a multipart upload
#
sub abort_multipart_upload {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  my $path      = $context->{'path'}      || LOGCROAK 'path is required';
  my $upload_id = $context->{'upload_id'} || LOGCROAK 'upload_id is required';

  my $account = $self->get_account();
  my $params  = '?uploadId=' . $upload_id;
  TRACE 'params: ', $params;
  my $response = $account->send_request( $DELETE, $path . $params );

  $account->_croak_if_response_error($response);

  return 1;
} ## end sub abort_multipart_upload

##############################################################################
#
# List all the uploaded parts for an ongoing multipart upload
# It returns the block of XML returned from Amazon
#
sub list_multipart_upload_parts {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  my $path      = $context->{'path'}      || LOGCROAK 'path is required';
  my $upload_id = $context->{'upload_id'} || LOGCROAK 'upload_id is required';
  my $headers   = $context->{'headers'};

  my $account = $self->get_account();
  my $params  = "?uploadId=${upload_id}";
  TRACE 'params: ', $params;
  my $response = $account->send_request( $GET, $path . $params, $headers );

  $account->_croak_if_response_error($response);

  # Just return the XML, let the caller figure out what to do with it
  return $response->content;
} ## end sub list_multipart_upload_parts

##############################################################################
#
# List all the currently active multipart upload operations
# Returns the block of XML returned from Amazon
#
sub list_multipart_uploads {
  my ( $self, $context ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $context ne $HASH;

  my $path = $context->{'path'} || LOGCROAK 'path is required';
  my $headers = $context->{'headers'};

  my $account = $self->get_account();
  my $params  = '?uploads';
  TRACE 'params: ', $params;
  my $response = $account->send_request( $GET, $path . $params, $headers );

  $account->_croak_if_response_error($response);

  # Just return the XML, let the caller figure out what to do with it
  return $response->content;
} ## end sub list_multipart_uploads

1;

__END__


