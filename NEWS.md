# NEWS

This is the `NEWS` file for the `perl-Amazon-S3`
project. This file contains information on changes since the last
release of the package, as well as a running list of changes from
previous versions.  If critical bugs are found in any of the software,
notice of such bugs and the versions in which they were fixed will be
noted here, as well.

# perl-Amazon-S3 0.56 (2022-11-29)

## Enhancements

None

## Fixes

* issue #8 - typo in Amazon::S3::Bucket::last_response()
* minor refactoring
* Amazon::S3::Bucket::get_acl()
  - return undef on 404 instead of croaking
* Amazon::S3 - minor refactoring, see ChangeLog

# perl-Amazon-S3 0.55 (2022-08-01)

## Enhancements

This version attempts to handle the _region_ problem...AWS Signature
Version 4 requires the region that the bucket is located in when
signing API requests. Amazon::S3::Bucket objects now carry along their
region so that requests against the bucket sign the request with the
correct region.

Unit tests for multipart uploads have been added and XML support has
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
