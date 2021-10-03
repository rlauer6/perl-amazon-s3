package Amazon::S3::Bucket;
use strict;
use warnings;
use Carp;
use File::stat;
use IO::File;
use Digest::MD5 qw(md5 md5_hex);
use Digest::MD5::File qw(file_md5 file_md5_hex);
use MIME::Base64;
use XML::LibXML;
use Data::Dumper;
use Amazon::S3::Log::Placeholders qw{:debug :errors :carp};

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw(bucket creation_date account));

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    LOGCROAK 'no bucket'  unless $self->bucket;
    LOGCROAK 'no account' unless $self->account;
    INFO 'self crealed, leave "new"';
    TRACE sub{ return 'self:', Dumper $self };
    return $self;
}

sub _uri {
    my ($self, $key) = @_;
    TRACE 'Entering to "_uri", key: ', $key // q{};
    my $uri = ($key)
      ? $self->bucket . "/" . $self->account->_urlencode($key)
      : $self->bucket . "/";
    DEBUG 'uri: ', $uri;
    return $uri;
}

# returns bool
sub add_key {
    my ($self, $key, $value, $conf) = @_;
    LOGCROAK 'must specify key' unless $key && length $key;
    DEBUG 'Entering to "add_key", key: ', $key;

    if ($conf->{acl_short}) {
        TRACE 'ACL presents, validate it: ', $conf->{acl_short};
        $self->account->_validate_acl_short($conf->{acl_short});
        $conf->{'x-amz-acl'} = $conf->{acl_short};
        delete $conf->{acl_short};
    }

    if (ref($value) eq 'SCALAR') {
        DEBUG 'value is SCALAR, treat it like file: ', ${ $value };
        my $md5_hex = file_md5_hex($$value);
        TRACE 'md5_hex: ', $md5_hex;
        my $md5 = pack( 'H*', $md5_hex );
        my $md5_base64 = encode_base64($md5);
        chomp $md5_base64;
        TRACE 'md5_base64: ', $md5_base64;

        $conf->{'Content-MD5'} = $md5_base64;

        $conf->{'Content-Length'} ||= -s $$value;
        TRACE 'Content-Length: ', $conf->{'Content-Length'};

        $value = _content_sub($$value);
    }
    else {
        DEBUG 'value is not reference, just plain data';
        $conf->{'Content-Length'} ||= length $value;
        TRACE 'Content-Length: ', $conf->{'Content-Length'};

        my $md5        = md5($value);
        my $md5_hex    = unpack( 'H*', $md5 );
        TRACE 'md5_hex: ', $md5_hex;
        my $md5_base64 = encode_base64($md5);
        TRACE 'md5_base64: ', $md5_base64;

        $conf->{'Content-MD5'} = $md5_base64;
    }

    # If we're pushing to a bucket that's under DNS flux, we might get a 307
    # Since LWP doesn't support actually waiting for a 100 Continue response,
    # we'll just send a HEAD first to see what's going on

    if (ref($value)) {
        DEBUG "Call _send_request_expect_nothing_probed for $key via PUT";
        my $response = $self->account->_send_request_expect_nothing_probed('PUT',
            $self->_uri($key), $conf, $value);
        TRACE sub{ return 'response: ', Dumper $response };
        return $response;
    }
    else {
        DEBUG "Call _send_request_expect_nothing for $key via PUT";
        my $response = $self->account->_send_request_expect_nothing('PUT',
            $self->_uri($key), $conf, $value);
        TRACE sub{ return 'response: ', Dumper $response };
        return $response;
    }
}

sub add_key_filename {
    my ($self, $key, $value, $conf) = @_;
    INFO '"add_key_filename" for key: ', $key // q{};
    return $self->add_key($key, \$value, $conf);
}

#
# Initiate a multipart upload operation
# This is necessary for uploading files > 5Gb to Amazon S3
# Returns the Upload ID assigned by Amazon, 
# This is needed to identify this particular upload in other operations
#
sub initiate_multipart_upload {
    my ($self, $key, $conf) = @_;

    LOGCROAK 'Object key is required' unless $key;
    INFO '"initiate_multipart_upload" for key: ', $key;

    my $acct = $self->account;

    my $request = $acct->_make_request("POST", $self->_uri($key) . '?uploads', $conf);
    my $response = $acct->_do_http($request);

    $acct->_croak_if_response_error($response);

    my $r = $acct->_xpc_of_content($response->content);

    DEBUG 'r->{UploadId}: ', $r->{UploadId};
    return $r->{UploadId};
}

#
# Upload a part of a file as part of a multipart upload operation
# Each part must be at least 5mb (except for the last piece).
# This returns the Amazon-generated eTag for the uploaded file segment.
# It is necessary to keep track of the eTag for each part number
# The complete operation will want a sequential list of all the part 
# numbers along with their eTags.
#
sub upload_part_of_multipart_upload {
    my ($self, $key, $upload_id, $part_number, $data, $length) = @_;

    LOGCROAK 'Object key is required' unless $key;
    LOGCROAK 'Upload id is required' unless $upload_id;
    LOGCROAK 'Part Number is required' unless $part_number;
    INFO 'Entering upload_part_of_multipart_upload for key: ', $key;
    TRACE "upload_id: $upload_id, part_number: $part_number";

    my $conf = {};
    my $acct = $self->account;

    # Make sure length and md5 are set
    my $md5        = md5($data);
    my $md5_hex    = unpack( 'H*', $md5 );
    TRACE 'md5_hex: ', $md5_hex;
    my $md5_base64 = encode_base64($md5);
    TRACE 'md5_base64: ', $md5_base64;

    $conf->{'Content-MD5'} = $md5_base64;
    $conf->{'Content-Length'} = $length;
    TRACE 'Content-Length: ', $conf->{'Content-Length'};

    my $params = "?partNumber=${part_number}&uploadId=${upload_id}";
    DEBUG 'params: ', $params;
    my $request = $acct->_make_request("PUT", $self->_uri($key) . $params, $conf, $data);
    my $response = $acct->_do_http($request);

    $acct->_croak_if_response_error($response);

    # We'll need to save the etag for later when completing the transaction
    my $etag = $response->header('ETag');
    DEBUG 'Checking and unquote ETag: ', $etag // q{};
    if ($etag) {
        $etag =~ s/^"//;
        $etag =~ s/"$//;
    }

    return $etag;
}

#
# Inform Amazon that the multipart upload has been completed
# You must supply a hash of part Numbers => eTags
# For amazon to use to put the file together on their servers.
#
sub complete_multipart_upload {
    my ($self, $key, $upload_id, $parts_hr) = @_;

    LOGCROAK 'Object key is required' unless $key;
    LOGCROAK 'Upload id is required' unless $upload_id;
    LOGCROAK 'Part number => etag hashref is required' unless (ref $parts_hr eq 'HASH');

    # The complete command requires sending a block of xml containing all 
    # the part numbers and their associated etags (returned from the upload)

    #build XML doc
    my $xml_doc = XML::LibXML::Document->new('1.0','UTF-8');
    my $root_element = $xml_doc->createElement('CompleteMultipartUpload');
    $xml_doc->addChild($root_element);
    TRACE sub{ return 'xml_doc: ', Dumper $xml_doc };

    # Add the content
    foreach my $part_num (sort {$a <=> $b} keys %$parts_hr) {

        # For each part, create a <Part> element with the part number & etag
        my $part = $xml_doc->createElement('Part');
        $part->appendTextChild('PartNumber' => $part_num);
        $part->appendTextChild('ETag' => $parts_hr->{$part_num});
        TRACE "PartNumber: $part_num, ETag: $parts_hr->{$part_num}";
        $root_element->addChild($part);
    }

    my $content    = $xml_doc->toString;
    my $md5        = md5($content);
    my $md5_base64 = encode_base64($md5);
    chomp $md5_base64;
    TRACE 'md5_base64: ', $md5_base64;

    my $conf = {
        'Content-MD5'    => $md5_base64,
        'Content-Length' => length $content,
        'Content-Type'   => 'application/xml'
    };
    TRACE sub{ return 'conf: ', Dumper $conf };

    my $acct = $self->account;
    my $params = "?uploadId=${upload_id}";
    TRACE 'params: ', $params;
    my $request = $acct->_make_request("POST", $self->_uri($key) . $params, $conf, $content);
    my $response = $acct->_do_http($request);

    $acct->_croak_if_response_error($response);

    return 1;
}

#
# Stop a multipart upload
#
sub abort_multipart_upload {
    my ($self, $key, $upload_id) = @_;

    LOGCROAK 'Object key is required' unless $key;
    LOGCROAK 'Upload id is required' unless $upload_id;

    my $acct = $self->account;
    my $params = "?uploadId=${upload_id}";
    TRACE 'params: ', $params;
    my $request = $acct->_make_request("DELETE", $self->_uri($key) . $params);
    my $response = $acct->_do_http($request);

    $acct->_croak_if_response_error($response);

    return 1;
}

#
# List all the uploaded parts for an ongoing multipart upload
# It returns the block of XML returned from Amazon
#
sub list_multipart_upload_parts {
    my ($self, $key, $upload_id, $conf) = @_;

    LOGCROAK 'Object key is required' unless $key;
    LOGCROAK 'Upload id is required' unless $upload_id;

    my $acct = $self->account;
    my $params = "?uploadId=${upload_id}";
    TRACE 'params: ', $params;
    my $request = $acct->_make_request("GET", $self->_uri($key) . $params, $conf);
    my $response = $acct->_do_http($request);

    $acct->_croak_if_response_error($response);

    # Just return the XML, let the caller figure out what to do with it
    return $response->content;
}

#
# List all the currently active multipart upload operations
# Returns the block of XML returned from Amazon
#
sub list_multipart_uploads {
    my ($self, $conf) = @_;

    my $acct = $self->account;
    my $params = '?uploads';
    TRACE 'params: ', $params;
    my $request = $acct->_make_request("GET", $self->_uri() . $params, $conf);
    my $response = $acct->_do_http($request);

    $acct->_croak_if_response_error($response);

    # Just return the XML, let the caller figure out what to do with it
    return $response->content;
}

sub head_key {
    my ($self, $key) = @_;
    INFO 'head_key for key: ', $key // q{};
    return $self->get_key($key, "HEAD");
}

sub get_key {
    my ($self, $key, $method, $filename) = @_;
    INFO '"get_key" for key: ', $key // q{}, ' via: ', $method // q{};
    $method ||= "GET";
    $filename = $$filename if ref $filename;
    TRACE "method: $method, filename: ", $filename // q{};
    my $acct = $self->account;

    my $request = $acct->_make_request($method, $self->_uri($key), {});
    my $response = $acct->_do_http($request, $filename);

    if ($response->code == 404) {
        INFO 'Key: ', $key // q{}, ' not found (404)!';
        return undef;
    }

    $acct->_croak_if_response_error($response);

    my $etag = $response->header('ETag');
    TRACE 'Checking and unquote ETag: ', $etag // q{};
    if ($etag) {
        $etag =~ s/^"//;
        $etag =~ s/"$//;
    }

    my $return = {
        content_length => $response->content_length || 0,
        content_type   => $response->content_type,
        etag           => $etag,
        value          => $response->content,
    };

    # Validate against data corruption by verifying the MD5
    if ($method eq 'GET') {
        my $md5 = ($filename and -f $filename) ? file_md5_hex($filename) : md5_hex($return->{value});
        TRACE 'md5 for verifying data corruption:', $md5 // q{};
        LOGCROAK "Computed and Response MD5's do not match:  $md5 : $etag" unless ($md5 eq $etag);
    }

    foreach my $header ($response->headers->header_field_names) {
        next unless $header =~ /x-amz-meta-/i;
        $return->{lc $header} = $response->header($header);
    }
    TRACE sub{ return 'return: ', Dumper $return };

    return $return;

}

sub get_key_filename {
    my ($self, $key, $method, $filename) = @_;
    INFO '"get_key_filename" for key: ', $key // q{};
    TRACE 'initial filename: ', $filename // q{};
    $filename = $key unless defined $filename;
    DEBUG 'filename: ', $filename;
    return $self->get_key($key, $method, \$filename);
}

# returns bool
sub delete_key {
    my ($self, $key) = @_;
    LOGCROAK 'must specify key' unless $key && length $key;
    INFO '"delete_key" for key: ', $key;
    return $self->account->_send_request_expect_nothing('DELETE',
        $self->_uri($key), {});
}

sub delete_bucket {
    my $self = shift;
    LOGCROAK 'Unexpected arguments' if @_;
    INFO 'Entering "delete_bucket"';
    return $self->account->delete_bucket($self);
}

sub list {
    my $self = shift;
    my $conf = shift || {};
    $conf->{bucket} = $self->bucket;
    INFO '"list" for bucket: ', $conf->{bucket};
    TRACE sub{ return 'conf:', Dumper $conf };
    return $self->account->list_bucket($conf);
}

sub list_all {
    my $self = shift;
    my $conf = shift || {};
    $conf->{bucket} = $self->bucket;
    INFO '"list_all" for bucket: ', $conf->{bucket};
    TRACE sub{ return 'conf:', Dumper $conf };
    return $self->account->list_bucket_all($conf);
}

sub get_acl {
    my ($self, $key) = @_;
    INFO '"get_acl" for key: ', $key // q{};
    my $acct = $self->account;

    my $request = $acct->_make_request('GET', $self->_uri($key) . '?acl', {});
    my $response = $acct->_do_http($request);

    if ($response->code == 404) {
        INFO 'Key: ', $key // q{}, ' not found (404)!';
        return undef;
    }

    $acct->_croak_if_response_error($response);

    DEBUG 'response->content: ', $response->content;
    return $response->content;
}

sub set_acl {
    my ($self, $conf) = @_;
    $conf ||= {};
    INFO 'Entering set_acl';
    TRACE sub{ return 'conf: ', Dumper $conf };

    unless ($conf->{acl_xml} || $conf->{acl_short}) {
        LOGCROAK 'need either acl_xml or acl_short';
    }

    if ($conf->{acl_xml} && $conf->{acl_short}) {
        LOGCROAK 'cannot provide both acl_xml and acl_short';
    }

    my $path = $self->_uri($conf->{key}) . '?acl';
    DEBUG 'path: ', $path;

    my $hash_ref =
        ($conf->{acl_short})
      ? {'x-amz-acl' => $conf->{acl_short}}
      : {};
    TRACE sub{ return 'hash_ref: ', Dumper $hash_ref };

    my $xml = $conf->{acl_xml} || '';
    TRACE sub{ return 'xml: ', Dumper $xml };

    return $self->account->_send_request_expect_nothing('PUT', $path,
        $hash_ref, $xml);

}

sub get_location_constraint {
    my ($self) = @_;
    INFO 'Entering get_location_constraint';

    my $xpc =
      $self->account->_send_request('GET', $self->bucket . '/?location');
    return undef unless $xpc && !$self->account->_remember_errors($xpc);
    TRACE sub { return 'xpc: ', Dumper $xpc };

    my $lc = $xpc->{content};
    if (defined $lc && $lc eq '') {
        $lc = undef;
    }
    DEBUG 'lc: ', $lc // 'UNDEF', ', leave "get_location_constraint"';
    return $lc;
}

# proxy up the err requests

sub err { $_[0]->account->err }

sub errstr { $_[0]->account->errstr }

sub _content_sub {
    my $filename  = shift;
    my $stat      = stat($filename);
    my $remaining = $stat->size;
    my $blksize   = $stat->blksize || 4096;

    LOGCROAK "$filename not a readable file with fixed size"
      unless -r $filename
          and $remaining;
    INFO '"_content_sub" for file: ', $filename;

    my $fh = IO::File->new($filename, 'r')
      or LOGCROAK "Could not open $filename: $!";
    $fh->binmode;

    TRACE "File '$filename' was opened (with binmode)";
    return sub {
        my $buffer;

        # upon retries the file is closed and we must reopen it
        unless ($fh->opened) {
            INFO "Reopen file $filename inside closure";

            $fh = IO::File->new($filename, 'r')
              or LOGCROAK "Could not open $filename: $!";
            $fh->binmode;
            $remaining = $stat->size;
        }

        unless (my $read = $fh->read($buffer, $blksize)) {
            LOGCROAK
              "Error while reading upload content $filename ($remaining remaining) $!"
              if $! and $remaining;
            DEBUG "Reach end of file $filename";
            $fh->close    # otherwise, we found EOF
              or LOGCROAK "close of upload content $filename failed: $!";
            TRACE 'Clearing buffer, because LWP expects an empty string on finish';
            $buffer ||= '';
        }
        TRACE 'read bytes: ', length $buffer // q{};
        $remaining -= length($buffer);
        DEBUG 'remaining: ', $remaining;
        return $buffer;
    };
}

1;

__END__

=head1 NAME

Amazon::S3::Bucket - A container class for a S3 bucket and its contents.

=head1 SYNOPSIS

  use Amazon::S3;
  
  # creates bucket object (no "bucket exists" check)
  my $bucket = $s3->bucket("foo"); 
  
  # create resource with meta data (attributes)
  my $keyname = 'testing.txt';
  my $value   = 'T';
  $bucket->add_key(
      $keyname, $value,
      {   content_type        => 'text/plain',
          'x-amz-meta-colour' => 'orange',
      }
  );
  
  # list keys in the bucket
  $response = $bucket->list
      or die $s3->err . ": " . $s3->errstr;
  print $response->{bucket}."\n";
  for my $key (@{ $response->{keys} }) {
        print "\t".$key->{key}."\n";  
  }

  # check if resource exists.
  print "$keyname exists\n" if $bucket->head_key($keyname);

  # delete key from bucket
  $bucket->delete_key($keyname);
 
=head1 METHODS

=head2 new

Instaniates a new bucket object. 

Requires a hash containing two arguments:

=over

=item bucket

The name (identifier) of the bucket.

=item account

The L<S3::Amazon> object (representing the S3 account) this
bucket is associated with.

=back

NOTE: This method does not check if a bucket actually
exists. It simply instaniates the bucket.

Typically a developer will not call this method directly,
but work through the interface in L<S3::Amazon> that will
handle their creation.

=head2 add_key

Takes three positional parameters:

=over

=item key

A string identifier for the resource in this bucket

=item value

A SCALAR string representing the contents of the resource.

=item configuration

A HASHREF of configuration data for this key. The configuration
is generally the HTTP headers you want to pass the S3
service. The client library will add all necessary headers.
Adding them to the configuration hash will override what the
library would send and add headers that are not typically
required for S3 interactions.

In addition to additional and overriden HTTP headers, this
HASHREF can have a C<acl_short> key to set the permissions
(access) of the resource without a seperate call via
C<add_acl> or in the form of an XML document.  See the
documentation in C<add_acl> for the values and usage. 

=back

Returns a boolean indicating its success. Check C<err> and
C<errstr> for error message if this operation fails.

=head2 add_key_filename

The method works like C<add_key> except the value is assumed
to be a filename on the local file system. The file will 
be streamed rather then loaded into memory in one big chunk.

=head2 head_key $key_name

Returns a configuration HASH of the given key. If a key does
not exist in the bucket C<undef> will be returned.

=head2 get_key $key_name, [$method]

Takes a key and an optional HTTP method and fetches it from
S3. The default HTTP method is GET.

The method returns C<undef> if the key does not exist in the
bucket and throws an exception (dies) on server errors.

On success, the method returns a HASHREF containing:

=over

=item content_type

=item etag

=item value

=item @meta

=back

=head2 get_key_filename $key_name, $method, $filename

This method works like C<get_key>, but takes an added
filename that the S3 resource will be written to.

=head2 delete_key $key_name

Permanently removes C<$key_name> from the bucket. Returns a
boolean value indicating the operations success.

=head2 delete_bucket

Permanently removes the bucket from the server. A bucket
cannot be removed if it contains any keys (contents).

This is an alias for C<$s3->delete_bucket($bucket)>.

=head2 list

List all keys in this bucket.

See L<Amazon::S3/list_bucket> for documentation of this
method.

=head2 list_all

List all keys in this bucket without having to worry about
'marker'. This may make multiple requests to S3 under the
hood.

See L<Amazon::S3/list_bucket_all> for documentation of this
method.

=head2 get_acl

Retrieves the Access Control List (ACL) for the bucket or
resource as an XML document.

=over

=item key

The key of the stored resource to fetch. This parameter is
optional. By default the method returns the ACL for the
bucket itself.

=back

=head2 set_acl $conf

Retrieves the Access Control List (ACL) for the bucket or
resource. Requires a HASHREF argument with one of the following keys:

=over

=item acl_xml

An XML string which contains access control information
which matches Amazon's published schema.

=item acl_short

Alternative shorthand notation for common types of ACLs that
can be used in place of a ACL XML document.

According to the Amazon S3 API documentation the following recognized acl_short
types are defined as follows:

=over

=item private

Owner gets FULL_CONTROL. No one else has any access rights.
This is the default.

=item public-read

Owner gets FULL_CONTROL and the anonymous principal is
granted READ access. If this policy is used on an object, it
can be read from a browser with no authentication.

=item public-read-write

Owner gets FULL_CONTROL, the anonymous principal is granted
READ and WRITE access. This is a useful policy to apply to a
bucket, if you intend for any anonymous user to PUT objects
into the bucket.

=item authenticated-read

Owner gets FULL_CONTROL, and any principal authenticated as
a registered Amazon S3 user is granted READ access.

=back

=item key

The key name to apply the permissions. If the key is not
provided the bucket ACL will be set.

=back

Returns a boolean indicating the operations success.

=head2 get_location_constraint

Returns the location constraint data on a bucket.

For more information on location constraints, refer to the
Amazon S3 Developer Guide.

=head2 err

The S3 error code for the last error the account encountered.

=head2 errstr

A human readable error string for the last error the account encountered.

=head1 DIAGNOSTICS

Out of the box module does log nothing, only croaks when it needed.
But it contains placeholders in B<Log::Log4perl(:easy)> compatible style.
If you want to get extended logging you can connect
this module to L<Log::Log4perl>.

(Note that this module does not depend on Log::Log4perl,
it is only provide compatible interface.)

If you want retrieve more logs you can redefine already placed placeholders:
B<TRACE DEBUG INFO WARN ERROR>, then let L<Log::Log4perl> reassign them
to its own closures. To achieve this insert into package where you use
L<Amazon::S3::Bucket> module this code:

    use English qw{ -no_match_vars };
    use Amazon::S3::Bucket;

    eval {
        require Log::Log4perl;

        package Amazon::S3::Bucket;    ## no critic (Modules::ProhibitMultiplePackages)
        Amazon::S3::Log::Placeholders->unimport(':all');
        Log::Log4perl->import(qw(:easy));

        1;
    } || croak $EVAL_ERROR;

    Log::Log4perl->easy_init();
    # or if you prefer use full power of Log::Log4perl:
    # Log::Log4perl->init('path-to-your-log4perl-conf');

=head3 Notes:

=item 'use Amazon::S3::Bucket;'

You should be ensure that you already 'used' or 'required' L<Amazon::S3::Bucket> (or using L<Amazon::S3>),
so placeholders in place.

=item 'Amazon::S3::Log::Placeholders->unimport(":all");'

You can use also C<no Amazon::S3::Log::Placeholders ':all'> for run this in the C<BEGIN> block

=item 'package Amazon::S3::Bucket;    ## no critic (Modules::ProhibitMultiplePackages)'

If you do not have package declaration above, you may be want to remove C<## no critic> directive.

=item 'require Log::Log4perl;'

You do not need require L<Log::Log4perl> if you 'use' it above in your own module

=head3 About Amazon::S3

You can combine with L<Amazon::S3>:

    ...
    eval {
        require Log::Log4perl;

        package Amazon::S3;    ## no critic (Modules::ProhibitMultiplePackages)
        Amazon::S3::Log::Placeholders->unimport(':all');
        Log::Log4perl->import(qw(:easy));
        package Amazon::S3::Bucket;    ## no critic (Modules::ProhibitMultiplePackages)
        Amazon::S3::Log::Placeholders->unimport(':all');
        Log::Log4perl->import(qw(:easy));

        1;
    } || croak $EVAL_ERROR;
    ...

=head1 SEE ALSO

L<Amazon::S3>

=head1 AUTHOR & COPYRIGHT

Please see the L<Amazon::S3> manpage for author, copyright, and
license information.
