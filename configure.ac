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
AC_CANONICAL_TARGET
m4_version_prereq(2.60, [AC_USE_SYSTEM_EXTENSIONS], [#])
AM_INIT_AUTOMAKE(1.9)
AM_MAINTAINER_MODE
m4_ifdef([AM_SILENT_RULES], [AM_SILENT_RULES([yes])])

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
AC_PATH_PROGS(NROFF, [gnroff nroff])


AC_ARG_ENABLE(pkgonly,
        [AC_HELP_STRING([--enable-pkgonly],
                        [Skip all checking])])
AC_SUBST(enable_pkgonly)

HTDOCSDIR=${prefix}/htdocs
AC_ARG_WITH(htdocs-dir,[  --with-htdocs-dir=[DIR]    Where to install htdocs [PREFIX/htdocs]], [HTDOCSDIR=$withval])
AC_SUBST(HTDOCSDIR)

#AC_ARG_WITH(perl5lib,  [  --with-perl5lib=[A:B:C]  Colon separated list of perl library directories], [PERL5LIB=$withval])

AC_ARG_VAR(PERL5LIB,   [[]             Colon separated list of perl library directories])

AC_SUBST(PERL5LIB)

# Check the necessary Perl modules

if test "$enable_pkgonly" != yes; then
   for module in RRDs FCGI CGI CGI::Fast Config::Grammar Digest::HMAC_MD5; do
     AC_MSG_CHECKING([presence of $module])
     if ${PERL} -e 'use '$module; then
         AC_MSG_RESULT([Ok])
     else
         AC_MSG_ERROR([Perl cannot find $module ($PERL5LIB)]);
     fi
   done
fi


AC_CONFIG_FILES([Makefile bin/Makefile doc/Makefile htdocs/Makefile etc/Makefile lib/Makefile])

AC_SUBST(VERSION)

AC_OUTPUT
