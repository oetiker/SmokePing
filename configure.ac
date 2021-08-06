#  Copyright (C) 2021  Tobi Oetiker
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

#


AC_INIT([smokeping],m4_esyscmd([tr -d '\n' < VERSION]),[tobi@oetiker.ch])
AC_PREREQ([2.59])
AC_CONFIG_AUX_DIR(conftools)

# need this to allow long path names
AM_INIT_AUTOMAKE([1.9 tar-ustar foreign])

AC_PREFIX_DEFAULT(/opt/$PACKAGE_NAME-$PACKAGE_VERSION)

AC_ARG_VAR(PERL,   [Path to local perl binary])
AC_PATH_PROG(PERL, perl, no)
AC_PATH_PROG(CURL, curl, no)
AC_PATH_PROG(WGET, wget, no)

URL_CAT="neither curl nor wget found"

if test -x "$CURL"; then
    URL_CAT="$CURL --location --insecure"
else
    if test -x "$WGET"; then
        URL_CAT="$WGET -O -"
    fi
fi

AC_SUBST(URL_CAT)

ac_perl_version="5.10.1"

if test "x$PERL" != "x"; then
  AC_MSG_CHECKING(for perl version greater than or equal to $ac_perl_version)
  $PERL -e "use $ac_perl_version;" >/dev/null 2>&1
  if test $? -ne 0; then
    AC_MSG_RESULT(no);
    AC_MSG_ERROR(at least version 5.10.1 is required to run mojolicious)
  else
    AC_MSG_RESULT(ok);
  fi
else
  AC_MSG_ERROR(could not find perl)
fi


AC_PATH_PROG(SED, sed, no)
AC_PATH_PROG(GREP, grep, no)
AC_PATH_PROG(ECHO, echo, no)
AC_PATH_PROG(LN, ln, no)
AC_PATH_PROG(CP, cp, no)
AC_PATH_PROG(RM, rm, no)
AC_PATH_PROG(RMDIR, rmdir, no)
AC_PATH_PROG(MKDIR, mkdir, no)
AC_PATH_PROG(FIND, find, no)
AC_PATH_PROG(SENDMAIL, sendmail, /path/to/sendmail, $PATH:/usr/sbin:/usr/lib)
AC_PATH_PROGS(NROFF, [gnroff nroff])

AC_ARG_VAR(GMAKE,   [Path to local GNU Make binary])
AC_PATH_PROGS(GMAKE, [gnumake gmake make])

AC_MSG_CHECKING([checking for gnu make availability])
if  ( $GMAKE --version 2> /dev/null | $GREP GNU  > /dev/null 2>&1 );  then
    AC_MSG_RESULT([$GMAKE is GNU make])
else
    AC_MSG_ERROR([GNU make not found. Try setting the GMAKE environment variable.])
fi

AC_ARG_ENABLE(pkgonly,
        [AC_HELP_STRING([--enable-pkgonly],
                        [Skip all checking])])
AC_SUBST(enable_pkgonly)

# $prefix stores the value of the --prefix command line option, or
# NONE if the option wasn't set.  In the case that it wasn't set, make
# it be the default, so that we can use it to expand directories now.

actual_prefix=$prefix
if test x$actual_prefix = xNONE; then
    actual_prefix=$ac_default_prefix
fi
    
HTDOCSDIR=${actual_prefix}/htdocs
AC_ARG_WITH(htdocs-dir,AC_HELP_STRING([--with-htdocs-dir=DIR],[Where to install htdocs [PREFIX/htdocs]]), [HTDOCSDIR=$withval])
AC_SUBST(HTDOCSDIR)

AC_ARG_VAR(PERL5LIB,   [Colon separated list of perl library directories])

AC_SUBST(PERL5LIB)

# Check the necessary Perl modules

mod_ok=1
if test "$enable_pkgonly" != yes; then
    AC_MSG_CHECKING([checking for RRDs perl module])
    if ${PERL} -e 'use RRDs' 2>/dev/null ; then
         AC_MSG_RESULT([Ok])
    else
         AC_MSG_RESULT([Failed])
         mod_ok=0
    fi
fi

if test x$mod_ok = x0; then
   cat <<NOTES

** Aborting Configure ******************************

   Smokeping requires a copy of rrdtool and its perl module RRDs
   installed for Smokeping to work. Installing rrdtool
   is outside the scope of the package. The easiest is
   to simply install rrdtool from your distro:

   on ubuntu

      sudo apt install rrdtool librrds-perl

   on redhat

      sudo yum install rrdtool perl-rrdtool

   if you install rrdtool from source into a non-standard location
   set PERL5LIB accordingly.
NOTES
   exit 1
fi

AC_CONFIG_FILES([Makefile bin/Makefile doc/Makefile htdocs/Makefile etc/Makefile lib/Makefile thirdparty/Makefile etc/config.dist])

AC_SUBST(VERSION)

AC_OUTPUT

        cat <<NOTES

** Ready to install Smokeping ******************************
   
   Settings:

     PERL5LIB = ${PERL5LIB:-"not set"}
     PERL = $PERL

   The Smokeping Makefiles use GNU make functionality.
   Continue installation with

     $GMAKE install

NOTES
