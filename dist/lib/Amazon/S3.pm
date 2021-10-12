package Amazon::S3;
use strict;
use warnings;

use Amazon::S3::Bucket;
use Amazon::S3::Constants
  qw{ :booleans :chars :reftypes :http_methods :aws_prefixes };
use Amazon::S3::Account;
use Amazon::S3::Log::Placeholders qw{ :debug :errors :carp };
use Amazon::S3::Utils;
use Carp;
use Data::Dumper;
use DateTime;
use Digest::SHA qw{ sha256_hex hmac_sha256 hmac_sha256_hex };
use English qw{ -no_match_vars };
use LWP::UserAgent::Determined;
use MIME::Base64 qw{ encode_base64 };
use URI::Escape qw{ uri_escape_utf8 uri_unescape };
use URI;
use XML::Simple;

use base qw(Class::Accessor::Fast);
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(
  qw(
    account region aws_access_key_id aws_secret_access_key token
    secure ua err errstr timeout retry host
    multipart_threshold multipart_chunksize
    allow_legacy_global_endpoint allow_legacy_path_based_bucket
    allow_unsigned_payload
    )
);

our $VERSION = '1.00';

##############################################################################
sub new {
  my ( $class, @args ) = @_;
  my $self = $class->SUPER::new(@args);
  TRACE 'Entering new';

  $self->set_account( Amazon::S3::Account->new(@args) );

  INFO 'self created, leave "new"';
  TRACE sub { return 'self: ', Dumper $self };
  return $self;
} ## end sub new

##############################################################################
sub buckets {
  my ($self) = @_;
  TRACE 'Entering buckets';

  my $xml = $self->get_account()->send_request_excpect_xml(    # send
    { method => $GET, }
  );
  TRACE sub { return 'Response: ', Dumper $xml };

  if ( !$xml || $self->get_account->remember_errors($xml) ) {
    return $FALSE;
  }
  INFO 'Response recieved and it is successfull';

  my $owner_id          = $xml->{'Owner'}->{'ID'};
  my $owner_displayname = $xml->{'Owner'}->{'DisplayName'};

  my @buckets;
  if ( ref $xml->{'Buckets'} ) {
    my $buckets = $xml->{'Buckets'}->{'Bucket'};
    ref $buckets eq $ARRAY or $buckets = [$buckets];
    foreach my $node ( @{$buckets} ) {
      push @buckets, Amazon::S3::Bucket->new(    # create new
        { bucket        => $node->{'Name'},
          creation_date => $node->{'CreationDate'},
          account       => $self->get_account(),
        }
      );
      DEBUG 'node->{name}: ', $node->{'Name'};

    } ## end foreach my $node ( @{$buckets...})
  } ## end if ( ref $xml->{'Buckets'...})

  my $buckets_href = {
    owner_id          => $owner_id,
    owner_displayname => $owner_displayname,
    buckets           => \@buckets,
  };
  INFO scalar @{ $buckets_href->{'buckets'} } . ' found, leave "buckets"';
  TRACE sub { return 'buckets_href: ', Dumper $buckets_href };
  return $buckets_href;
} ## end sub buckets

##############################################################################
sub add_bucket {
  my ( $self, $args ) = @_;
  my $bucket = $args->{'bucket'};
  LOGCROAK 'must specify bucket' if !$bucket;
  DEBUG 'Creating bucket: ', $bucket;

  if ( $args->{'headers'}->{'acl_short'} ) {
    Amazon::S3::Utils::validate_acl_short(
      $args->{'headers'}->{'acl_short'} );
  }

  my $headers
    = ( $args->{'headers'}->{'acl_short'} )
    ? { $AMAZON_ACL => $args->{'headers'}->{'acl_short'} }
    : {};

  my $data = $EMPTY;
  if ( defined $args->{'headers'}->{'location_constraint'} ) {
    $data
      = '<CreateBucketConfiguration><LocationConstraint>'
      . $args->{'headers'}->{'location_constraint'}
      . '</LocationConstraint></CreateBucketConfiguration>';
  } ## end if ( defined $args->{'headers'...})

  my $response = $self->account->send_request_expect_nothing(
    method  => $PUT,
    path    => $bucket . $SLASH_CHAR,
    headers => $headers,
    data    => \$data,
  );
  return $FALSE if !$response;

  my $bucket_instance = $self->bucket( { bucket => $bucket } );
  INFO 'Bucket ', $bucket, ' was created, leave "add_bucket"';
  TRACE sub { return 'bucket_instance: ', Dumper $bucket_instance };
  return $bucket_instance;
} ## end sub add_bucket

##############################################################################
sub bucket {
  my ( $self, $args ) = @_;
  my $bucketname = $args->{'bucket'};
  INFO 'Creating bucket instance: ', $bucketname;

  my $bucket = Amazon::S3::Bucket->new(
    { bucket  => $bucketname,
      account => $self->get_account(),
    }
  );
  TRACE sub { return 'bucket: ', Dumper $bucket };
  return $bucket;
} ## end sub bucket

##############################################################################
sub delete_bucket {
  my ( $self, $args ) = @_;
  my $bucket;
  if ( eval { $args->isa('Amazon::S3::Bucket'); } ) {
    $bucket = $args->bucket();
  }
  else {
    $bucket = $args->{'bucket'};
  }
  LOGCROAK 'must specify bucket' if !$bucket;

  INFO 'Deleting bucket: ', $bucket;
  my $response = $self->send_request_expect_nothing(
    { method => $DELETE,
      path   => $bucket . $SLASH_CHAR,
    }
  );
  TRACE sub { return 'response: ', Dumper $response };
  return $response;
} ## end sub delete_bucket

##############################################################################
sub list_bucket {
  my ( $self, $args ) = @_;
  my $bucket = delete $args->{'bucket'};
  LOGCROAK 'must specify bucket' unless $bucket;
  $args ||= {};
  INFO 'List bucket: ', $bucket;

  my $path = $bucket . $SLASH_CHAR;
  if ( %{$args} ) {
    $path .= $QUESTION_MARK
      . join( $AMP_CHAR,
      map { $_ . $EQUAL_SIGN . $self->_urlencode( $args->{$_} ) }
        keys %{$args} );
  } ## end if ( %{$args} )
  DEBUG 'path: ', $path;

  my $xpc = $self->get_account()->send_request_expect_xml(
    { method => $GET,
      path   => $path,
    }
  );
  return undef if !$xpc || $self->account->_remember_errors($xpc);
  INFO 'Response recieved and it is successfull';
  DEBUG 'Bucket name: ', $xpc->{'Name'};
  TRACE sub { return 'Response (r): ', Dumper $xpc };

  my $return = {
    bucket       => $xpc->{'Name'},
    prefix       => $xpc->{'Prefix'},
    marker       => $xpc->{'Marker'},
    next_marker  => $xpc->{'NextMarker'},
    max_keys     => $xpc->{'MaxKeys'},
    is_truncated => (
      scalar $xpc->{'IsTruncated'} eq 'true'
      ? $TRUE
      : $FALSE
    ),
  };

  my @keys;
  foreach my $node ( @{ $xpc->{'Contents'} } ) {
    my $etag = $node->{'ETag'};
    $etag =~ s{(\A" | "\z)}{}gxms if defined $etag;
    push @keys,
      {
      key               => $node->{'Key'},
      last_modified     => $node->{'LastModified'},
      etag              => $etag,
      size              => $node->{'Size'},
      storage_class     => $node->{'StorageClass'},
      owner_id          => $node->{'Owner'}->{'ID'},
      owner_displayname => $node->{'Owner'}->{'DisplayName'},
      };
    DEBUG 'Key: ', $node->{'Key'};
  } ## end foreach my $node ( @{ $xml->...})
  $return->{'keys'} = \@keys;

  if ( $args->{'delimiter'} ) {
    my @common_prefixes;
    my $strip_delim = qr/$args->{'delimiter'} \z/xms;

    foreach my $node ( $xpc->{'CommonPrefixes'} ) {
      if ( ref $node ne $ARRAY ) {
        $node = [$node];
      }

      foreach my $node_elem ( @{$node} ) {
        next unless exists $node_elem->{'Prefix'};
        my $prefix = $node_elem->{'Prefix'};

        # strip delimiter from end of prefix
        if ($prefix) {
          $prefix =~ s/$strip_delim//xms;
        }

        push @common_prefixes, $prefix;
      } ## end foreach my $node_elem ( @{$node...})
    } ## end foreach my $node ( $xpc->{'CommonPrefixes'...})
    $return->{'common_prefixes'} = \@common_prefixes;
  } ## end if ( $args->{'delimiter'...})

  INFO 'Listed bucket: ', $bucket, ', leave "list_backet"';
  TRACE sub { return 'return: ', Dumper $return };
  return $return;
} ## end sub list_bucket

##############################################################################
sub list_bucket_all {
  my ( $self, $args ) = @_;
  $args ||= {};
  my $bucket = $args->{'bucket'};
  LOGCROAK 'must specify bucket' if !$bucket;
  INFO 'List bucket all: ', $bucket;

  my $response = $self->list_bucket($args);
  TRACE sub { return 'First response: ', Dumper $response };
  return $response if !( ref $response && $response->{'is_truncated'} );
  my $all = $response;

  MARKER:
  while (1) {
    my $next_marker = $response->{'next_marker'}
      || $response->{'keys'}->[$LAST]->{'key'};
    $args->{'marker'} = $next_marker;
    $args->{'bucket'} = $bucket;
    $response         = $self->list_bucket($args);
    TRACE sub { return 'Next response: ', Dumper $response };
    push @{ $all->{'keys'} }, @{ $response->{'keys'} };
    last MARKER if !$response->{'is_truncated'};
  } ## end MARKER: while (1)

  delete $all->{'is_truncated'};
  delete $all->{'next_marker'};
  TRACE sub { return 'all: ', Dumper $all };
  return $all;
} ## end sub list_bucket_all

1;

__END__

=head1 NAME

Amazon::S3 - A portable client library for working with and
managing Amazon S3 buckets and keys.

=head1 SYNOPSIS

  #!/usr/bin/perl
  use warnings;
  use strict;

  use Amazon::S3;
  
  use vars qw/$OWNER_ID $OWNER_DISPLAYNAME/;
  
  my $aws_access_key_id     = "Fill me in!";
  my $aws_secret_access_key = "Fill me in too!";
  
  # defaults to US East (N. Virginia)
  my $region = "us-east-1";

  my $s3 = Amazon::S3->new(
      {   region                => $region,
          aws_access_key_id     => $aws_access_key_id,
          aws_secret_access_key => $aws_secret_access_key,
          retry                 => 1
      }
  );
  
  my $response = $s3->buckets;
  
  # create a bucket
  my $bucket_name = $aws_access_key_id . '-net-amazon-s3-test';
  my $bucket = $s3->add_bucket( { bucket => $bucket_name } )
      or die $s3->err . ": " . $s3->errstr;
  
  # store a key with a content-type and some optional metadata
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

  # delete key from bucket
  $bucket->delete_key($keyname);
  
  # delete bucket
  $bucket->delete_bucket;
  
=head1 DESCRIPTION

Amazon::S3 provides a portable client interface to Amazon Simple
Storage System (S3). 

"Amazon S3 is storage for the Internet. It is designed to
make web-scale computing easier for developers. Amazon S3
provides a simple web services interface that can be used to
store and retrieve any amount of data, at any time, from
anywhere on the web. It gives any developer access to the
same highly scalable, reliable, fast, inexpensive data
storage infrastructure that Amazon uses to run its own
global network of web sites. The service aims to maximize
benefits of scale and to pass those benefits on to
developers".

To sign up for an Amazon Web Services account, required to
use this library and the S3 service, please visit the Amazon
Web Services web site at http://www.amazonaws.com/.

You will be billed accordingly by Amazon when you use this
module and must be responsible for these costs.

To learn more about Amazon's S3 service, please visit:
http://s3.amazonaws.com/.

This need for this module arose from some work that needed
to work with S3 and would be distributed, installed and used
on many various environments where compiled dependencies may
not be an option. L<Net::Amazon::S3> used L<XML::LibXML>
tying it to that specific and often difficult to install
option. In order to remove this potential barrier to entry,
this module is forked and then modified to use L<XML::SAX>
via L<XML::Simple>.

Amazon::S3 is intended to be a drop-in replacement for
L<Net:Amazon::S3> that trades some performance in return for
portability.

=head1 METHODS

=head2 new 

Create a new S3 client object. Takes some arguments:

=over

=item region

This is the region your buckets are in.
Defaults to us-east-1

See a list of regions at:
https://docs.aws.amazon.com/general/latest/gr/rande.html#s3_region

=item aws_access_key_id 

Use your Access Key ID as the value of the AWSAccessKeyId parameter
in requests you send to Amazon Web Services (when required). Your
Access Key ID identifies you as the party responsible for the
request.

=item aws_secret_access_key 

Since your Access Key ID is not encrypted in requests to AWS, it
could be discovered and used by anyone. Services that are not free
require you to provide additional information, a request signature,
to verify that a request containing your unique Access Key ID could
only have come from you.

B<DO NOT INCLUDE THIS IN SCRIPTS OR APPLICATIONS YOU
DISTRIBUTE. YOU'LL BE SORRY.>

=item token

An optional temporary token that will be inserted in the request along
with your access and secret key.  A token is used in conjunction with
temporary credentials when your EC2 instance has
assumed a role and you've scraped the temporary credentials from
I<http://169.254.169.254/latest/meta-data/iam/security-credentials>

=item secure

Set this to C<1> if you want to use SSL-encrypted
connections when talking to S3. Defaults to C<0>.

=item timeout

Defines the time, in seconds, your script should wait or a
response before bailing. Defaults is 30 seconds.

=item retry

Enables or disables the library to retry upon errors. This
uses exponential backoff with retries after 1, 2, 4, 8, 16,
32 seconds, as recommended by Amazon. Defaults to off, no
retries.

=item host

Defines the S3 host endpoint to use. Defaults to
's3.us-east-1.amazonaws.com'
(or 's3.amazonaws.com' if C<allow_legacy_global_endpoint> is true. See below).

Note that requests are made to domain buckets when possible.  You can
prevent that behavior if either the bucket name does conform to DNS
bucket naming conventions or you preface the bucket name with '/'
or set C<allow_legacy_path_based_bucket> to C<true> (see below).

=item allow_legacy_global_endpoint

Accordind to this document:
L<Virtual hosting of buckets|https://docs.aws.amazon.com/AmazonS3/latest/userguide/VirtualHosting.html#VirtualHostingBackwardsCompatibility>

  Some Regions support legacy endpoints.
  Although you might see legacy endpoints in your logs,
  we recommend that you always use the standard endpoint syntax
  to access your buckets.

Set C<allow_legacy_global_endpoint> to C<true> if you don't want
the constructor to check if region in the C<host> is missed and
automatically insert C<region> into C<host>.

When it set to C<false> (default) constructor try to recognize if
region in C<host> is missed between B<'s3'>
(in fact 's3', 's3-anythig-not-dot' and optional 'dualstack')
and B<'amazonaws.com'> then it inserts content of B<region> there.

B<WARNING! This feature changes default behaviour>

=item allow_legacy_path_based_bucket

According to this document:
L<Virtual hosting of buckets|https://docs.aws.amazon.com/AmazonS3/latest/userguide/VirtualHosting.html#path-style-access>

  Currently Amazon S3 supports virtual hosted-style
  and path-style access in all Regions,
  but this will be changing.
  For more information, see
  Amazon S3 Path Deprecation Plan
  http://aws.amazon.com/blogs/aws/amazon-s3-path-deprecation-plan-the-rest-of-the-story/

To prevent automatic transformation
of any requests to virtual hosted-style
(move backet name from path to the host)
set C<allow_legacy_path_based_bucket> to C<true>.

If you want use legacy path-style requests,
set C<allow_legacy_path_based_bucket> to C<false> which is default.

=item allow_unsigned_payload

Set this to C<true> to send requests with 'UNSIGNED-PAYLOAD'. Default is C<false>,
which means that all payloads (even empty) will be sent in a signed way.

=back

=head2 buckets

Returns C<undef> on error, else HASHREF of results:

=over

=item owner_id

The owner's ID of the buckets owner.

=item owner_display_name

The name of the owner account. 

=item buckets

Any ARRAYREF of L<Amazon::SimpleDB::Bucket> objects for the 
account.

=back

=head2 add_bucket 

Takes a HASHREF:

=over

=item bucket

The name of the bucket you want to add

=item acl_short (optional)

See the set_acl subroutine for documenation on the acl_short options

=back

Returns 0 on failure or a L<Amazon::S3::Bucket> object on success

=head2 bucket BUCKET

Takes a scalar argument, the name of the bucket you're creating

Returns an (unverified) bucket object from an account. This method does not access the network.

=head2 delete_bucket

Takes either a L<Amazon::S3::Bucket> object or a HASHREF containing 

=over

=item bucket

The name of the bucket to remove

=back

Returns false (and fails) if the bucket isn't empty.

Returns true if the bucket is successfully deleted.

=head2 list_bucket

List all keys in this bucket.

Takes a HASHREF of arguments:

=over

=item bucket

REQUIRED. The name of the bucket you want to list keys on.

=item prefix

Restricts the response to only contain results that begin with the
specified prefix. If you omit this optional argument, the value of
prefix for your query will be the empty string. In other words, the
results will be not be restricted by prefix.

=item delimiter

If this optional, Unicode string parameter is included with your
request, then keys that contain the same string between the prefix
and the first occurrence of the delimiter will be rolled up into a
single result element in the CommonPrefixes collection. These
rolled-up keys are not returned elsewhere in the response.  For
example, with prefix="USA/" and delimiter="/", the matching keys
"USA/Oregon/Salem" and "USA/Oregon/Portland" would be summarized
in the response as a single "USA/Oregon" element in the CommonPrefixes
collection. If an otherwise matching key does not contain the
delimiter after the prefix, it appears in the Contents collection.

Each element in the CommonPrefixes collection counts as one against
the MaxKeys limit. The rolled-up keys represented by each CommonPrefixes
element do not.  If the Delimiter parameter is not present in your
request, keys in the result set will not be rolled-up and neither
the CommonPrefixes collection nor the NextMarker element will be
present in the response.

NOTE: CommonPrefixes isn't currently supported by Amazon::S3. 

=item max-keys 

This optional argument limits the number of results returned in
response to your query. Amazon S3 will return no more than this
number of results, but possibly less. Even if max-keys is not
specified, Amazon S3 will limit the number of results in the response.
Check the IsTruncated flag to see if your results are incomplete.
If so, use the Marker parameter to request the next page of results.
For the purpose of counting max-keys, a 'result' is either a key
in the 'Contents' collection, or a delimited prefix in the
'CommonPrefixes' collection. So for delimiter requests, max-keys
limits the total number of list results, not just the number of
keys.

=item marker

This optional parameter enables pagination of large result sets.
C<marker> specifies where in the result set to resume listing. It
restricts the response to only contain results that occur alphabetically
after the value of marker. To retrieve the next page of results,
use the last key from the current page of results as the marker in
your next request.

See also C<next_marker>, below. 

If C<marker> is omitted,the first page of results is returned. 

=back

Returns C<undef> on error and a HASHREF of data on success:

The HASHREF looks like this:

  {
        bucket       => $bucket_name,
        prefix       => $bucket_prefix, 
        marker       => $bucket_marker, 
        next_marker  => $bucket_next_available_marker,
        max_keys     => $bucket_max_keys,
        is_truncated => $bucket_is_truncated_boolean
        keys          => [$key1,$key2,...]
   }

Explanation of bits of that:

=over

=item is_truncated

B flag that indicates whether or not all results of your query were
returned in this response. If your results were truncated, you can
make a follow-up paginated request using the Marker parameter to
retrieve the rest of the results.

=item next_marker 

A convenience element, useful when paginating with delimiters. The
value of C<next_marker>, if present, is the largest (alphabetically)
of all key names and all CommonPrefixes prefixes in the response.
If the C<is_truncated> flag is set, request the next page of results
by setting C<marker> to the value of C<next_marker>. This element
is only present in the response if the C<delimiter> parameter was
sent with the request.

=back

Each key is a HASHREF that looks like this:

     {
        key           => $key,
        last_modified => $last_mod_date,
        etag          => $etag, # An MD5 sum of the stored content.
        size          => $size, # Bytes
        storage_class => $storage_class # Doc?
        owner_id      => $owner_id,
        owner_displayname => $owner_name
    }

=head2 list_bucket_all

List all keys in this bucket without having to worry about
'marker'. This is a convenience method, but may make multiple requests
to S3 under the hood.

Takes the same arguments as list_bucket.

=head1 ABOUT

This module contains code modified from Amazon that contains the
following notice:

  #  This software code is made available "AS IS" without warranties of any
  #  kind.  You may copy, display, modify and redistribute the software
  #  code either by itself or as incorporated into your code; provided that
  #  you do not remove any proprietary notices.  Your use of this software
  #  code is at your own risk and you waive any claim against Amazon
  #  Digital Services, Inc. or its affiliates with respect to your use of
  #  this software code. (c) 2006 Amazon Digital Services, Inc. or its
  #  affiliates.

=head1 TESTING

Testing S3 is a tricky thing. Amazon wants to charge you a bit of 
money each time you use their service. And yes, testing counts as using.
Because of this, the application's test suite skips anything approaching 
a real test unless you set these three environment variables:

=over 

=item AMAZON_S3_EXPENSIVE_TESTS

Doesn't matter what you set it to. Just has to be set

=item AWS_ACCESS_KEY_ID 

Your AWS access key

=item AWS_ACCESS_KEY_SECRET

Your AWS sekkr1t passkey. Be forewarned that setting this environment variable
on a shared system might leak that information to another user. Be careful.

=back

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
L<Amazon::S3> module this code:

    use English qw{ -no_match_vars };
    use Amazon::S3;

    eval {
        require Log::Log4perl;

        package Amazon::S3;    ## no critic (Modules::ProhibitMultiplePackages)
        Amazon::S3->unimport(':all');
        Log::Log4perl->import(qw(:easy));

        1;
    } || croak $EVAL_ERROR;

    Log::Log4perl->easy_init();
    # or if you prefer use full power of Log::Log4perl:
    # Log::Log4perl->init('path-to-your-log4perl-conf');

=head3 Notes:

=item 'use Amazon::S3;'

You should be ensure that you already 'used' or 'required' L<Amazon::S3>,
so placeholders in place.

=item 'Amazon::S3::Log::Placeholders->unimport(":all");'

You can use also C<no Amazon::S3::Log::Placeholders ':all'> for run this in the C<BEGIN> block

=item 'package Amazon::S3;    ## no critic (Modules::ProhibitMultiplePackages)'

If you do not have package declaration above, you may be want to remove C<## no critic> directive.

=item 'require Log::Log4perl;'

You do not need require L<Log::Log4perl> if you 'use' it above in your own module

=head3 About Amazon::S3::Bucket

You can combine with L<Amazon::S3::Buckets>:

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

=head1 TO DO

=over

=item Continued to improve and refine of documentation.

=item Reduce dependencies wherever possible.

=item Implement debugging mode

=item Refactor and consolidate request code in Amazon::S3

=item Refactor URI creation code to make use of L<URI>.

=back

=head1 SUPPORT

Bugs should be reported via the CPAN bug tracker at

<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Amazon-S3>

For other issues, contact the author.

=head1 AUTHOR

Timothy Appnel <tima@cpan.org>

=head1 SEE ALSO

L<Amazon::S3::Bucket>, L<Net::Amazon::S3>

=head1 COPYRIGHT AND LICENCE

This module was initially based on L<Net::Amazon::S3> 0.41, by
Leon Brocard. Net::Amazon::S3 was based on example code from
Amazon with this notice:

#  This software code is made available "AS IS" without warranties of any
#  kind.  You may copy, display, modify and redistribute the software
#  code either by itself or as incorporated into your code; provided that
#  you do not remove any proprietary notices.  Your use of this software
#  code is at your own risk and you waive any claim against Amazon
#  Digital Services, Inc. or its affiliates with respect to your use of
#  this software code. (c) 2006 Amazon Digital Services, Inc. or its
#  affiliates.

The software is released under the Artistic License. The
terms of the Artistic License are described at
http://www.perl.com/language/misc/Artistic.html. Except
where otherwise noted, Amazon::S3 is Copyright 2008, Timothy
Appnel, tima@cpan.org. All rights reserved.
