SUBDIRS = . lib

# See README-TESTING.md for complete details on testing using LocalStack

# LocalStack testing
#    AMAZON_S3_EXPENSIVE_TESTS=1 \
#    AMAZON_S3_HOST=s3.localhost.localstack.cloud:4566 \
#    AMAZON_S3_LOCALSTACK=1 \
#    AWS_ACCESS_KEY_ID=test \
#    AWS_ACCESS_SECRET_KEY=test  \
#    AMAZON_S3_DOMAIN_BUCKET_NAMES=1  make test

# AWS live testing
#    AMAZON_S3_EXPENSIVE_TESTS=1 \
#    AMAZON_S3_DOMAIN_BUCKET_NAMES=1 \
#    AMAZON_S3_CREDENTIALS=1 \
#    AWS_PROFILE=my-profile make test

test:
	prove -I lib -v t/
