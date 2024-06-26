AC_INIT([perl-Amazon-S3],
        m4_esyscmd_s([
if test -z "$VERSION"; then \
  VERSION=$(test -e VERSION && cat VERSION); \
  VERSION=${VERSION:-0.0.0}; \
fi; \
echo $VERSION
]),
        m4_esyscmd_s([if test -z "$EMAIL"; then EMAIL=rclauer@gmail.com; fi; echo $EMAIL]),[perl-Amazon-S3])

__poor_mans_expand_file_name () {
    _tmp_name=$1
    _tmp_last="`eval echo '${'"${_tmp_name}"'}'`"
    if test -z "${_tmp_last}"; then
        printf "__poor_mans_expand_file_name() (WARNING): var \"%s\" is empty\n" \
          "${_tmp_name}" 1>&2
        return 0;  # nothing to do
    fi
    _tmp_last_expanded="`eval echo ${_tmp_last}`"
    while test "${_tmp_last_expanded}" != "${_tmp_last}"; do

        # Set 'last' hold var to most recently expanded version...
        _tmp_last="${_tmp_last_expanded}"

        # ...and try to expand further.
        _tmp_last_expanded="`eval echo ${_tmp_last_expanded}`"
    done
    printf "%s\n" "${_tmp_last_expanded}"
    unset _tmp_last_expanded
    unset _tmp_last
    unset _tmp_name
    return 0;
}


[
do_subst_command='do_subst = sed \
  -e '"'"'s,[@]PACKAGE[@],$(PACKAGE),g'"'"' \
  -e '"'"'s,[@]PACKAGE_VERSION[@],$(PACKAGE_VERSION),g'"'"' \
  -e '"'"'s,[@]VERSION[@],$(VERSION),g'"'"' \
  -e '"'"'s,[@]PATH_SEPARATOR[@],$(PATH_SEPARATOR),g'"'"' \
  -e '"'"'s~[@]configure_input[@]~Generated from $@.in; do not edit by hand.~g'"'"' \
  -e "s,[@]BUILD_DATE[@],$$(date '"'"'+%Y-%m-%d %H:%M:%S'"'"'),g" \
  \
  -e '"'"'s,[@]bindir[@],$(bindir),g'"'"' \
  -e '"'"'s,[@]datadir[@],$(datadir),g'"'"' \
  -e '"'"'s,[@]exec_prefix[@],$(exec_prefix),g'"'"' \
  -e '"'"'s,[@]includedir[@],$(includedir),g'"'"' \
  -e '"'"'s,[@]infodir[@],$(infodir),g'"'"' \
  -e '"'"'s,[@]libdir[@],$(libdir),g'"'"' \
  -e '"'"'s,[@]libexecdir[@],$(libexecdir),g'"'"' \
  -e '"'"'s,[@]localstatedir[@],$(localstatedir),g'"'"' \
  -e '"'"'s,[@]mandir[@],$(mandir),g'"'"' \
  -e '"'"'s,[@]oldincludedir[@],$(oldincludedir),g'"'"' \
  -e '"'"'s,[@]prefix[@],$(prefix),g'"'"' \
  -e '"'"'s,[@]sbindir[@],$(sbindir),g'"'"' \
  -e '"'"'s,[@]sharedstatedir[@],$(sharedstatedir),g'"'"' \
  -e '"'"'s,[@]sysconfdir[@],$(sysconfdir),g'"'"' \
  \
  -e '"'"'s,[@]abs_builddir[@],$(abs_builddir),g'"'"' \
  -e '"'"'s,[@]abs_srcdir[@],$(abs_srcdir),g'"'"' \
  -e '"'"'s,[@]abs_top_builddir[@],$(abs_top_builddir),g'"'"' \
  -e '"'"'s,[@]abs_top_srcdir[@],$(abs_top_srcdir),g'"'"' \
  -e '"'"'s,[@]srcdir[@],$(srcdir),g'"'"' \
  -e '"'"'s,[@]top_builddir[@],$(top_builddir),g'"'"' \
  -e '"'"'s,[@]top_srcdir[@],$(top_srcdir),g'"'"' \
\
  -e '"'"'s,[@]perl5libdir[@],$(perl5libdir),g'"'"' \
  -e '"'"'s,[@]perlrun[@],$(perlrun),g'"'"' \
  -e '"'"'s,[@]ksh[@],$(ksh),g'"'"' \
  -e '"'"'s,[@]bashrun[@],$(bashrun),g'"'"' \
  -e '"'"'s,[@]logdir[@],$(logdir),g'"'"' \
  -e '"'"'s,[@]spooldir[@],$(spooldir),g'"'"' \
\
'
]

AC_SUBST([do_subst_command])

AC_CONFIG_AUX_DIR([autotools])
AC_CONFIG_MACRO_DIR([autotools])

AM_INIT_AUTOMAKE([foreign tar-ustar])

AC_PATH_PROG([BASHRUN],
	[bash])

if test -z "$BASHRUN" ; then 
  AC_MSG_ERROR([bash not found?])
fi

AC_PATH_PROG([PERL],
	[perl])

if test -z "$PERL" ; then 
  AC_MSG_ERROR([perl not found?])
fi

AC_PATH_PROG([POD2MARKDOWN],
	[pod2markdown])

if test -z "$POD2MARKDOWN" ; then 
  AC_MSG_ERROR([pod2markdown found?])
fi

AC_PATH_PROG([MAKE_CPAN_DIST],
	[make-cpan-dist.pl])

if test -z "$MAKE_CPAN_DIST" ; then 
  AC_MSG_WARN([make-cpan-dist.pl not found? (you won't be able to create a CPAN distribution - https://github.com/rlauer6/make-cpan-dist.git)])
fi

AC_PATH_PROG([RPMBUILD],
	[rpmbuild])

if test -z "$RPMBUILD" ; then 
  AC_MSG_WARN([rpmbuild not found?])
fi

AC_PATH_PROG([SCANDEPS],
	[scandeps-static.pl])

if test -z "$SCANDEPS" ; then 
  AC_MSG_WARN([scandeps-static.pl not found? (https://metacpan.org/pod/Module::ScanDeps::Static)])
fi

perl5libdir=\${datadir}/perl5
AC_ARG_WITH(
	[perl5libdir],[  --with-perl5libdir (defaults to [DATAROOTDIR]/perl5)],
	[
    if test "${withval}" = 'no'; then
        true
    elif test "$withval" = 'yes'; then
        perl5libdir=$($PERL -MConfig -wle 'print $Config{sitelib};')
    else
        perl5libdir=$withval    
    fi
        ]
)

AC_SUBST([perl5libdir])

ads_PERL_MODULE([Carp], [REQUIRED])
ads_PERL_MODULE([Class::Accessor::Fast], [REQUIRED])
ads_PERL_MODULE([Data::Dumper], [REQUIRED])
ads_PERL_MODULE([Digest::HMAC_SHA1], [REQUIRED])
ads_PERL_MODULE([Digest::MD5], [REQUIRED])
ads_PERL_MODULE([Digest::MD5::File], [REQUIRED])
ads_PERL_MODULE([Exporter], [REQUIRED])
ads_PERL_MODULE([File::stat], [REQUIRED])
ads_PERL_MODULE([File::Temp], [REQUIRED])
ads_PERL_MODULE([HTTP::Date], [REQUIRED])
ads_PERL_MODULE([IO::File], [REQUIRED])
ads_PERL_MODULE([IO::Scalar], [REQUIRED])
ads_PERL_MODULE([List::Util], [REQUIRED])
ads_PERL_MODULE([LWP::UserAgent::Determined], [REQUIRED])
ads_PERL_MODULE([MIME::Base64], [REQUIRED])
ads_PERL_MODULE([Readonly], [REQUIRED])
ads_PERL_MODULE([Scalar::Util], [REQUIRED])
ads_PERL_MODULE([Test::More], [REQUIRED])
ads_PERL_MODULE([Test::Output], [REQUIRED])
ads_PERL_MODULE([URI::Escape], [REQUIRED])
ads_PERL_MODULE([warnings], [REQUIRED])
ads_PERL_MODULE([XML::Simple], [REQUIRED])

AX_DISTCHECK_HACK
AX_DEPS_CHECK
AX_PERLDEPS_CHECK
AX_RPMBUILD_CHECK

AC_CONFIG_FILES([
    Makefile
    src/Makefile
    src/main/Makefile
    src/main/perl/Makefile
    src/main/perl/lib/Makefile
    cpan/Makefile
    ${PACKAGE_NAME}.spec
])

AC_OUTPUT

printf "\n"
printf "${PACKAGE} has been configured with the following options:\n"
printf "                        Prefix: %s\n" "`__poor_mans_expand_file_name prefix`"
printf "                 User binaries: %s\n" "`__poor_mans_expand_file_name bindir`"
printf "               System binaries: %s\n" "`__poor_mans_expand_file_name sbindir`"
printf "           Configuration files: %s\n" "`__poor_mans_expand_file_name sysconfdir`"
printf "                  Manual pages: %s\n" "`__poor_mans_expand_file_name mandir`"
printf "\n"
printf "                   perl5libdir: %s\n" "`__poor_mans_expand_file_name perl5libdir`"
printf "\n"
printf "                          perl: %s\n" "`__poor_mans_expand_file_name PERL`"
printf "\n"
printf "               Package Version: %s\n"   "${PACKAGE_VERSION}"
