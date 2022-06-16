# README

This project was been largely cloned from:

https://github.com/tima/perl-amazon-s3.

The project provides a Perl interface to S3.

# Requirements for Building

To build an rpm or the CPAN distribution tarball you'll need these in
your toolchain:

* `make`
* `automake`
* `autoconf`

To build an rpm you'll need:

* `rpmbuild`

# Creating a CPAN Distribution

```
git clone http://github.com/rlauer6/perl-amazon-s3.git
cd perl-amazon-s3
./bootstrap
./configure
make
cd cpan
make cpan
```

# Building an rpm

```
git clone http://github.com/rlauer6/perl-amazon-s3.git
cd perl-amazon-s3
./bootstrap
./configure
make dist
make rpm
```
