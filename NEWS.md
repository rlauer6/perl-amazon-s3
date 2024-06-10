# NEWS

This is the `NEWS` file for the `perl-Amazon-S3`
project. This file contains information on changes since the last
release of the package, as well as a running list of changes from
previous versions.  If critical bugs are found in any of the software,
notice of such bugs and the versions in which they were fixed will be
noted here, as well.

# perl-Amazon-S3 2.00 (2023-12-13)

> This version introduces several new methods. Much of the legacy code has
> been refactored for clarity and to reduce duplication.  A new set of
> S3 methods have been implemented in `Amazon::S3::V2`. Some of
> the new methods duplicate existing functionality but are now
> implemented with interfaces that are more aligned with the actual
> AWS API documentation. The new methods in `Amazon::S3::V2` are named
> after the documented API. Not all API actions have been implemented yet.
>
> Additionally, many of the existing methods have been modified slightly to allow
> for specifying object versions or to allow for setting additional
> headers which were previously ignored.
>
> See the documentation for `Amazon::S3`, `Amazon::S3::Bucket` and
> `Amazon::S3::V2` for more details.

# perl-Amazon-S3 0.66 (2024-06-10)

> This version introduces new methods for handling object version and
> introduces some new methods that more accurately track the S3
> API. Those new methods are experimental and will be released as
> version 2.

## Enhancements

* `Amazon::S3::Bucket`
  * `delete_key()` now accepts an optional version identifier
  * `get_bucket_versioning()` - returns status of bucket versioning
  * `put_bucket_versioning()` - sets the status of bucket versioning
* `Amazon:S3`
  * `list_object_versions()` - method that returns version metadata
* start of version 2 changes
* refactoring
* allow additional headers for several existing methods
* pod fixes & updates

## Fixes

* unit tests fixes
  * LocalStack fixes
  * refactored several tests

# perl-Amazon-S3 0.65 (2023-11-28)

> This version fixes a bug when getting credentials from the the
> Amazon::Credentials object and that object has a token. This bug
> manifested itself as a Forbidden error. The error message misleading
> says the Access Key Id is invalid when the issue is that the session
> token was never passed to the signer.

## Enhancements

* None

# perl-Amazon-S3 0.64 (2023-07-20)

> This version fixes a bug in get_location_constraint()

## Enhancements

* None

# perl-Amazon-S3 0.63 (2023-04-17)

> This version adds passes -key and -pass to Crypt::CBC to
> support older versions of Crypt::CBC

## Enhancements

* None

## Fixes

* pass -key and -pass options to Crypt::CBC

# perl-Amazon-S3 0.62 (2023-04-13)

> This version adds fixes a bug in `list_bucket` and `buckets` methods
> that did not return `undef` as documented for non-existent buckets.

## Enhancements

* None

## Fixes

* return `undef` for `list_bucket` and `buckets` when bucket(s) do not
  exist
* added unit test for listing non-existent bucket

# perl-Amazon-S3 0.61 (2023-03-30)

> This version adds a new method for bulk deletion of keys. Some
> refactoring of the code has been done and unit tests have been
> cleaned up.

## Enhancements

* `delete_keys()` - method to delete a list of keys with one API call (`DeleteObjects`)

## Fixes

* None

# perl-Amazon-S3 0.60 (2023-02-10)

> This version adds a utility (`s3-perl.pl`) to exercise a subset of
> methods. Try `s3-perl.pl --help` for usage information.

> If a logger is passed to the constructor, the `debug` flag is
> ignored. The logging level of the logger passed will determine
> whether debug messages are generated.

## Enhancements

* added the `s3-perl.pl` utility to root of project. This utility is
  not included in the CPAN distribution. It can be used to exercise
  some of the methods in `Amazon::S3` and `Amazon::S3::Bucket`.

## Fixes

* ignore debug flag when a logger is passed to the constructor

# perl-Amazon-S3 0.59 (2023-01-25)

> This version adds the `copy_object()` method to `Amazon::S3::Bucket`.

## Enhancements

* `copy_object()` method added to the `Amazon::S3::Bucket` class
* added unit test for `copy_object()` to `t/01-api` (more tests needed)

## Fixes

* corrected documentation in ['README-TESTING.md`](README-TESTING.md)
* corrected comments in
  ['src/main/perl/Makefile.am'](src/main/perl/Makefile.am)
* changed use of S3_HOST environment variable to AMAZON_S3_HOST in
  (`t/04-list-buckets.t`)[t/04-list-buckets.t]

# perl-Amazon-S3 0.58 (2022-12-19)

> This version pegs the minimum `perl` version to 5.010.

## Enhancements

_None_

## Fixes

* add JSON:PP to requires
* set minimum `perl` version to 5.010

# perl-Amazon-S3 0.57 (2022-12-03)

> This version fixes RPM packaging.

## Enhancements

_None_

## Fixes

* install `Amazon::S3::Signature::V4` to correct directory
* add Net::Amazon::Signature::V4 to Requires

# perl-Amazon-S3 0.56 (2022-11-29)

## Enhancements

* better(?) handling of domain bucket names (Amazon::S3::_make_request())

## Fixes

* issue #8 - typo in Amazon::S3::Bucket::last_response()
* minor refactoring
* Amazon::S3::Bucket::get_acl()
  - return undef on 404 instead of croaking
* Amazon::S3 - minor refactoring, see ChangeLog

# perl-Amazon-S3 0.55 (2022-08-01)

## Enhancements

>This version attempts to handle the _region_ problem...AWS Signature
Version 4 requires the region that the bucket is located in when
signing API requests. Amazon::S3::Bucket objects now carry along their
region so that requests against the bucket sign the request with the
correct region.

>Unit tests for multipart uploads have been added and XML support has
reverted to using XML::Simple rather than XML::LibXML.

* new convenience method for multipart upload - `upload_multipart_object()`
* new convenience method for retrieving bucket region - `get_bucket_location()`
* buckets objects carry region attribute to facilitate signing
* new option `verify_region` for `Amazon::S3` and `Amazon::S3::Bucket`
  to automatically verify region of a bucket
* multipart upload unit tests
* revert to using XML::Simple which introduces slightly less dependencies than
  XML::LibXML and XML::LibXML::Simple
* new method `error()` to retrieve the decode XML error

## Fixes

* error handling in `complete_multipart_upload()`
* pod corrections, additions, updates
