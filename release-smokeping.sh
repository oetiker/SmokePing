#!/bin/sh
set -e
[ `git status -s | wc -l` -gt 0 ] && echo "ERROR: commit all changes before release" && exit 1
VERSION=`perl -n -e 'm/\QAC_INIT([smokeping],[\E(.+?)\Q]\E/ && print $1' configure.ac`
mkdir -p conftools
aclocal
autoconf
automake -a -c
./setup/build-perl-modules.sh /tmp/smokeping-$$-build/thirdparty
./configure  --enable-maintainer-mode --prefix=/tmp/smokeping-$$-build PERL5LIB=/scratch/rrd-trunk/lib/perl
make install
make dist
echo READY TO SYNC ?
read XXX
scp CHANGES smokeping-$VERSION.tar.gz oposs@james:public_html/smokeping/pub
rm -fr /tmp/smokeping-$$-build
git tag $VERSION
echo "run 'git push;git push --tags' to sync github"

