#  Copyright (C) 2011  Tobi Oetiker
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
AM_INIT_AUTOMAKE([1.9 tar-ustar foreign no-dependencies no-installinfo no-texinfo.tex nostdinc ])
AM_MAINTAINER_MODE

m4_ifdef([AM_SILENT_RULES], [AM_SILENT_RULES([yes])])

AC_PREFIX_DEFAULT(/opt/smokeping-$PACKAGE_VERSION)

AC_ARG_VAR(PERL,   [Path to local perl binary])
AC_PATH_PROG(PERL, perl, no)
AC_PATH_PROG(SED, sed, no)
AC_PATH_PROG(GREP, grep, no)
AC_PATH_PROG(ECHO, echo, no)
AC_PATH_PROG(LN, ln, no)
AC_PATH_PROG(CP, cp, no)
AC_PATH_PROG(RM, rm, no)
AC_PATH_PROG(RMDIR, rmdir, no)
AC_PATH_PROG(MKDIR, mkdir, no)
AC_PATH_PROG(FIND, find, no)
AC_PATH_PROG(SENDMAIL, sendmail, /path/to/sendmail, [$PATH$PATH_SEPARATOR/usr/sbin$PATH_SEPARATOR/usr/lib])
AC_PATH_PROGS(NROFF, [gnroff nroff])

AC_ARG_VAR(GMAKE,   [Path to local GNU Make binary])
AC_PATH_PROGS(GMAKE, [gnumake gmake make])

AC_MSG_CHECKING([checking for gnu make availablility])
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
   MODULES=`dirname $0`/PERL_MODULES
   for module in `sed -e 's/\@.*//' $MODULES` RRDs; do 
     AC_MSG_CHECKING([checking for perl module '$module'])
     if ${PERL} -I$actual_prefix/thirdparty/lib/perl5 -e 'use '$module; then
         AC_MSG_RESULT([Ok])
     else
         AC_MSG_RESULT([Failed])
         mod_ok=0
     fi
   done
   if test x$mod_ok = x0; then
        cat <<NOTES

** Aborting Configure ******************************
   
   If you know where perl can find the missing modules, set
   the PERL5LIB environment variable accordingly.

   FIRST though, make sure that 'perl' starts the perl
   binary you want to use for SmokePing.

   Now you can install local copies of the missing modules 
   by running

     ./setup/build-perl-modules.sh ${actual_prefix}/thirdparty

   The RRDs perl module is part of RRDtool. Either use the rrdtool
   package provided by your OS or install rrdtool from source. 
   If you install from source, the RRDs module is located
   PREFIX/lib/perl

NOTES
      exit 1
   fi

fi


AC_CONFIG_FILES([Makefile bin/Makefile doc/Makefile htdocs/Makefile etc/Makefile lib/Makefile etc/config.dist])

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
