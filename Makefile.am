SUBDIRS = . src cpan

ACLOCAL_AMFLAGS = -I autotools

rpmbuild = @RPMBUILD@

@do_subst_command@

S3_PM = ${abs_builddir}/src/main/perl/lib/Amazon/S3.pm

$(S3_PM): $(S3_PM).in
	cd ${abs_builddir}/src/main/perl/lib; \
	$(MAKE)

README.md: $(S3_PM)
	pod2markdown < $< >$@

dist_noinst_DATA = \
    README.md \
    README-TESTING.md \
    README-BUILD.md \
    ${PACKAGE_NAME}.spec \
    ${PACKAGE_NAME}.spec.in

.PHONY: cpan rpm

rpm:
	if ! test -x "$(rpmbuild)"; then \
	  echo "no rpmbuild"; \
	  exit 1; \
	fi

	cd $(abs_builddir) && $(MAKE) dist
	TARBALL=$$(ls -1rt *.tar.gz | tail -1); \
	$(rpmbuild) -tb $$TARBALL
	find $$HOME/rpmbuild -name '*.rpm' | grep $(PACKAGE)

cpan:
	cd $(abs_builddir) && $(MAKE)
	cd cpan && $(MAKE) cpan

CLEANFILES = 

DISTCHECK_CONFIGURE_FLAGS = --enable-distcheck-hack --enable-rpmbuild
