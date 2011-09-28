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


AC_INIT([smokeping],[2.5.2],[tobi@oetiker.ch])
AC_PREREQ([2.59])
AC_CONFIG_AUX_DIR(conftools)
AC_CANONICAL_HOST
AM_INIT_AUTOMAKE(1.9)
AM_MAINTAINER_MODE

AC_PREFIX_DEFAULT( /opt/smokeping-$PACKAGE_VERSION )

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


AC_ARG_ENABLE(pkgonly,
        [AC_HELP_STRING([--enable-pkgonly],
                        [Skip all checking])])
AC_SUBST(enable_pkgonly)

HTDOCSDIR=${prefix}/htdocs
AC_ARG_WITH(htdocs-dir,[  --with-htdocs-dir=[DIR]    Where to install htdocs [PREFIX/htdocs]], [HTDOCSDIR=$withval])
AC_SUBST(HTDOCSDIR)
        
PERLLIBDIRS=

PERLOPTS=
AC_ARG_WITH(perl-inc,[  --with-perl-inc=[DIRS]    Additional space-separated Perl library paths], [PERLINC=$withval])
AC_ARG_VAR(PERLINC,  [[]             Additional space-separated Perl library paths])
if test ! -z "$PERLINC"; then
   for d in $PERLINC; do
       PERLOPTS="${PERLOPTS} -I${d}"
       perllibdirs=${perllibdirs}"\,\'"${d}"\'"
   done
fi
AC_SUBST(PERLOPTS)

AC_SUBST(PERLLIBDIRS, [${perllibdirs}])


# Check the necessary Perl modules

if test "$enable_pkgonly" != yes; then
   for module in RRDs FCGI CGI CGI::Fast Config::Grammar Digest::HMAC_MD5; do
     AC_MSG_CHECKING([presence of $module])
     if ${PERL} ${PERLOPTS} -e 'use '$module; then
         AC_MSG_RESULT([Ok])
     else
         AC_MSG_ERROR([Perl cannot find $module ($PERLOPTS)]);
     fi
   done
fi


AC_CONFIG_FILES([Makefile bin/Makefile doc/Makefile htdocs/Makefile etc/Makefile lib/Makefile])

AC_SUBST(VERSION)

AC_OUTPUT
