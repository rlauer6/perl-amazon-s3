package Amazon::S3::Bucket;
use strict;
use warnings;

use Amazon::S3::Constants
  qw{ :booleans :chars :reftypes :aws_prefixes :http_methods :http_codes };
use Amazon::S3::Log::Placeholders qw{ :debug :errors :carp };
use Data::Dumper;
use Digest::MD5 qw{ md5 md5_hex };
use Digest::MD5::File qw{ file_md5_hex };
use English qw{ -no_match_vars };
use File::stat;
use IO::File;
use MIME::Base64;

use base qw(Class::Accessor::Fast);
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(qw(bucket creation_date account));

our $VERSION = '1.00';

##############################################################################
sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);

  LOGCROAK 'no bucket'  if !$self->get_bucket();
  LOGCROAK 'no account' if !$self->get_account();
  INFO 'self created, leave "new"';
  TRACE sub { return 'self:', Dumper $self };

  return $self;
} ## end sub new

##############################################################################
sub _uri {
  my ( $self, $key ) = @_;
  TRACE 'Entering to "_uri", key: ', $key // $EMPTY;
  my $uri
    = ($key)
    ? $self->get_bucket() . $SLASH_CHAR . Amazon::S3::Utils::urlencode($key)
    : $self->get_bucket() . $SLASH_CHAR;
  DEBUG 'uri: ', $uri;

  return $uri;
} ## end sub _uri

##############################################################################
# returns bool
sub add_key {
  my ( $self, $args ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $args ne $HASH;

  my $key      = $args->{'key'} || LOGCROAK 'key is required';
  my $headers  = $args->{'headers'};
  my $data     = $args->{'data'};
  my $filename = $args->{'filename'};
  LOGCROAK 'must specify either data or filename' if !( $data || $filename );
  LOGCROAK 'cannot provide both data and filename' if $data && $filename;
  LOGCROAK 'must specify data as ref to scalar' if ref $data ne $SCALAR;

  DEBUG 'Entering to "add_key", key: ', $key;

  if ( $headers->{'acl_short'} ) {
    TRACE 'ACL presents, validate it: ', $headers->{'acl_short'};
    Amazon::S3::Utils::validate_acl_short( $headers->{'acl_short'} );
    $headers->{$AMAZON_ACL} = $headers->{'acl_short'};
    delete $headers->{'acl_short'};
  } ## end if ( $headers->{'acl_short'...})

  my $response;
  if ($filename) {
    LOGCROAK "file $filename not found or not readable" if !-r $filename;
    DEBUG 'value is SCALAR, treat it like file: ', $filename;
    my $md5_hex = file_md5_hex($filename);
    TRACE 'md5_hex: ', $md5_hex;
    my $md5 = pack( 'H*', $md5_hex );
    my $md5_base64 = encode_base64($md5);
    chomp $md5_base64;
    TRACE 'md5_base64: ', $md5_base64;

    $headers->{'Content-MD5'} = $md5_base64;

    #$headers->{'Content-Length'} ||= -s $filename;
    #TRACE 'Content-Length: ', $headers->{'Content-Length'};

    # If we're pushing to a bucket that's under DNS flux, we might get a 307
    # Since LWP doesn't support actually waiting for a 100 Continue response,
    # we'll just send a HEAD first to see what's going on

    DEBUG "Call send_request_expect_nothing for $key via PUT";
    $response = $self->get_account()->send_request_expect_nothing(
      method   => $PUT,
      path     => $self->_uri($key),
      headers  => $headers,
      filename => $data,
    );
  } ## end if ($filename)
  else {
    DEBUG 'just plain data';
    #$headers->{'Content-Length'} ||= length ${$data};
    #TRACE 'Content-Length: ', $headers->{'Content-Length'};

    my $md5 = md5( ${$data} );
    my $md5_hex = unpack( 'H*', $md5 );
    TRACE 'md5_hex: ', $md5_hex;
    my $md5_base64 = encode_base64($md5);
    TRACE 'md5_base64: ', $md5_base64;

    $headers->{'Content-MD5'} = $md5_base64;

    DEBUG "Call send_request_expect_nothing for $key via PUT";
    $response = $self->get_account()->send_request_expect_nothing(
      { method  => $PUT,
        path    => $self->_uri($key),
        headers => $headers,
        data    => $data,
      }
    );
  } ## end else [ if ($filename) ]
  TRACE sub { return 'response: ', Dumper $response };

  return $response;
} ## end sub add_key

##############################################################################
sub head_key {
  my ( $self, $args ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $args ne $HASH;
  INFO 'head_key for key: ', $args->{'key'} // $EMPTY;
  $args->{'method'} = $HEAD;
  my $response = $self->get_key($args);
  return $response;
} ## end sub head_key

##############################################################################
sub get_key {
  #my ( $self, $key, $method, $filename ) = @_;
  my ( $self, $args ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $args ne $HASH;
  my $key = $args->{'key'};
  my $method = $args->{'method'} || $GET;
  INFO '"get_key" for key: ', $key // $EMPTY, ' via: ', $method // $EMPTY;

  my $filename
    = ref $args->{'filename'}
    ? ${ $args->{'filename'} }
    : $args->{'filename'};
  TRACE "method: $method, filename: ", $filename // $EMPTY;
  my $account = $self->get_account();

  my $data     = $EMPTY;
  my $response = $account->send_request(
    { method   => $method,
      path     => $self->_uri($key),
      filename => $filename,
      data     => \$data,
    }
  );

  if ( $response->code == $CODE_404 ) {
    INFO 'Key: ', $key // $EMPTY, ' not found (404)!';
    return undef;
  }

  $account->_croak_if_response_error($response);

  my $etag = $response->header('ETag');
  TRACE 'Checking and unquote ETag: ', $etag // $EMPTY;
  if ($etag) {
    $etag =~ s/\A"//xms;
    $etag =~ s/"\z//xms;
  }

  my $return = {
    content_length => $response->content_length() || 0,
    content_type   => $response->content_type(),
    etag           => $etag,
    value          => $response->content(),
  };

  # Validate against data corruption by verifying the MD5
  if ( $method eq $GET ) {
    my $md5 = ( $filename and -f $filename )    # is file and exists
      ? file_md5_hex($filename)
      : md5_hex( $return->{value} );
    TRACE 'md5 for verifying data corruption:', $md5 // $EMPTY;
    LOGCROAK "Computed and Response MD5's do not match:  $md5 : $etag"
      if ( $md5 ne $etag );
  } ## end if ( $method eq $GET )

  foreach my $header ( $response->headers->header_field_names ) {
    next if $header !~ /$METADATA_PREFIX/i;
    $return->{ lc $header } = $response->header($header);
  }
  TRACE sub { return 'return: ', Dumper $return };

  return $return;
} ## end sub get_key

##############################################################################
sub get_key_filename {
  #my ( $self, $key, $method, $filename ) = @_;
  my ( $self, $args ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $args ne $HASH;
  INFO '"get_key_filename" for key: ', $args->{'key'}      // $EMPTY;
  TRACE 'initial filename: ',          $args->{'filename'} // $EMPTY;

  defined $args->{'filename'} or $args->{'filename'} = $args->{'key'};
  DEBUG 'filename: ', $args->{'filename'};

  my $response = $self->get_key($args);

  return $response;
} ## end sub get_key_filename

##############################################################################
# returns bool
sub delete_key {
  my ( $self, $args ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $args ne $HASH;
  my $key = $args->{'key'} || LOGCROAK 'path is required';
  INFO '"delete_key" for key: ', $key;

  my $response = $self->get_account()->send_request_expect_nothing(
    { method => $DELETE,
      path   => $self->_uri($key),
    }
  );

  return $response;
} ## end sub delete_key

##############################################################################
sub delete_bucket {
  my ($self) = @_;
  LOGCROAK 'Unexpected arguments' if @_;
  INFO 'Entering "delete_bucket"';

  my $response = $self->get_account()->delete_bucket($self);

  return $response;
} ## end sub delete_bucket

##############################################################################
sub list {
  my ( $self, $args ) = @_;
  $args ||= {};
  $args->{'bucket'} = $self->get_bucket();
  INFO '"list" for bucket: ', $args->{'bucket'};
  TRACE sub { return 'conf:', Dumper $args };
  my $response = $self->get_account()->list_bucket($args);

  return $response;
} ## end sub list

##############################################################################
sub list_all {
  my ( $self, $args ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $args ne $HASH;
  $args ||= {};
  $args->{'bucket'} = $self->get_bucket();
  INFO '"list_all" for bucket: ', $args->{'bucket'};
  TRACE sub { return 'conf:', Dumper $args };
  my $response = $self->get_account()->list_bucket_all($args);

  return $response;
} ## end sub list_all

##############################################################################
sub get_acl {
  my ( $self, $args ) = @_;
  LOGCROAK 'must specify arguments as hash ref' if ref $args ne $HASH;
  my $key = $args->{'key'};
  INFO '"get_acl" for key: ', $key // $EMPTY;
  my $account = $self->get_account();

  my $response = $account->send_request(
    { method => $GET,
      key    => $self->_uri($key) . '?acl'
    }
  );

  if ( $response->code == $CODE_404 ) {
    INFO 'Key: ', $key // $EMPTY, ' not found (404)!';
    return undef;
  }

  $account->_croak_if_response_error($response);

  my $content = $response->content();
  DEBUG 'response->content: ', $content;

  return $content;
} ## end sub get_acl

##############################################################################
sub set_acl {
  my ( $self, $args ) = @_;
  $args ||= {};
  INFO 'Entering set_acl';
  TRACE sub { return 'conf: ', Dumper $args };

  if ( !$args->{'acl_xml'} && !$args->{'acl_short'} ) {
    LOGCROAK 'need either "acl_xml" or "acl_short"';
  }

  if ( $args->{'acl_xml'} && $args->{'acl_short'} ) {
    LOGCROAK 'cannot provide both "acl_xml" and "acl_short"';
  }

  my $path = $self->_uri( $args->{'key'} ) . '?acl';
  DEBUG 'path: ', $path;

  my $headers
    = ( $args->{'acl_short'} )
    ? { $AMAZON_ACL => $args->{'acl_short'} }
    : {};
  TRACE sub { return 'hash_ref: ', Dumper $headers };

  my $xml = $args->{'acl_xml'} || $EMPTY;
  TRACE sub { return 'xml: ', Dumper $xml };

  my $response = $self->get_account()->send_request_expect_nothing(
    method  => $PUT,
    key     => $path,
    headers => $headers,
    data    => \$xml,
  );

  return $response;
} ## end sub set_acl

##############################################################################
sub get_location_constraint {
  my ($self) = @_;
  INFO 'Entering get_location_constraint';

  my $xpc = $self->get_account()->send_request(
    { method => $GET,
      path   => $self->get_bucket() . '/?location',
    }
  );
  return undef if !$xpc || $self->get_account()->_remember_errors($xpc);
  TRACE sub { return 'xpc: ', Dumper $xpc };

  my $lc = $xpc->{'content'};
  if ( defined $lc && $lc eq $EMPTY ) {
    $lc = undef;
  }
  DEBUG 'lc: ', $lc // 'UNDEF', ', leave "get_location_constraint"';

  return $lc;
} ## end sub get_location_constraint

# proxy up the err requests

##############################################################################
sub err    { shift->get_account()->err() }
sub errstr { shift->get_account()->errstr() }

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
