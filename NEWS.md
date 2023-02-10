# NEWS

This is the `NEWS` file for the `perl-Amazon-S3`
project. This file contains information on changes since the last
release of the package, as well as a running list of changes from
previous versions.  If critical bugs are found in any of the software,
notice of such bugs and the versions in which they were fixed will be
noted here, as well.

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
