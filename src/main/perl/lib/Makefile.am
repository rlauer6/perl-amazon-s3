SUBDIRS = .

perlrun = @PERL@

if RPMBUILD_ENABLED
perlwc = \#
else
perlwc = @PERL@ -wc
endif

perl5libdir = @perl5libdir@
ax_perl5_extra_includes_opt = @ax_perl5_extra_includes_opt@

PERLMODULES =

AMAZON_PERLMODULES = \
    Amazon/S3.pm.in

AMAZON_S3_PERLMODULES = \
    Amazon/S3/Bucket.pm.in \
    Amazon/S3/Constants.pm.in \
    Amazon/S3/Logger.pm.in

AMAZON_S3_SIGNATURE_PERLMODULES = \
   Amazon/S3/Signature/V4.pm.in

GPERLMODULES = $(PERLMODULES:.pm.in=.pm)

GAMAZON_PERLMODULES = $(AMAZON_PERLMODULES:.pm.in=.pm)
GAMAZON_S3_PERLMODULES = $(AMAZON_S3_PERLMODULES:.pm.in=.pm)
GAMAZON_S3_SIGNATURE_PERLMODULES = $(AMAZON_S3_SIGNATURE_PERLMODULES:.pm.in=.pm)

amazondir = $(perl5libdir)/Amazon
amazon_s3dir = $(amazondir)/S3
amazon_s3_signaturedir = $(amazondir)/S3

amazon_DATA = $(GAMAZON_PERLMODULES:pm.in=.pm)
amazon_s3_DATA = $(GAMAZON_S3_PERLMODULES:pm.in=.pm)
amazon_s3_signature_DATA = $(GAMAZON_S3_SIGNATURE_PERLMODULES:pm.in=.pm)

dist_noinst_DATA = \
    $(PERLMODULES) \
    $(AMAZON_PERLMODULES) \
    $(AMAZON_S3_PERLMODULES) \
    $(AMAZON_S3_SIGNATURE_PERLMODULES)

@do_subst_command@

if USING_PERL5_EXTRA_INCLUDES
PERL5_EXTRA_INCLUDES = $(ax_perl5_extra_includes_opt)
else
endif

# Please see the notes concerning PERLINCLUDE in the ../bin/Makefile.am file
PERLINCLUDE = \
   -I $(builddir) \
   $(PERL5_EXTRA_INCLUDES) \
   -I $(perl5libdir) 

Amazon/S3.pm: Amazon/S3/Constants.pm \
	      Amazon/S3/Bucket.pm \
	      Amazon/S3/Logger.pm \
	      Amazon/S3/Signature/V4.pm

Amazon/S3/Bucket.pm: Amazon/S3/Constants.pm

Amazon/S3/Logger.pm: Amazon/S3/Constants.pm

%.pm: %.pm.in
	test -d "$$(dirname "$@")" || $(INSTALL) -d "$$(dirname "$@")"
	$(do_subst) $< > $@
	set -e; \
	$(perlwc) $(PERLINCLUDE) $@ || { ret=$$?; rm $@ && exit $$?; }

all:

CLEANFILES = \
   $(GPERLMODULES) \
   $(GAMAZON_PERLMODULES) \
   $(GAMAZON_S3_PERLMODULES) \
   $(GAMAZON_S3_SIGNATURE_PERLMODULES)
