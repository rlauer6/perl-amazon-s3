# NEWS

This is the `NEWS` file for the `perl-Amazon-S3`
project. This file contains information on changes since the last
release of the package, as well as a running list of changes from
previous versions.  If critical bugs are found in any of the software,
notice of such bugs and the versions in which they were fixed will be
noted here, as well.

# perl-Amazon-S3 0.55 (2022-07-21)

## Enhancements

* new convenience method for multipart upload - `upload_multipart_object()`
* new convenience method for retrieving bucket region - `get_bucket_location()`
* buckets objects carry region attribute to facilitate signing
* multipart upload unit tests
* github workflow build

## Fixes

* error handling in `complete_multipart_upload()`
