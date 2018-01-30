#!/bin/sh
set -e
[ `git status -s | wc -l` -gt 0 ] && echo "ERROR: commit all changes before release" && exit 1
VERSION=`cat VERSION`
mkdir -p conftools
make clean
./bootstrap
make
make clean
touch PERL_MODULES
make PERL=perl-5.10.1
./configure  --enable-maintainer-mode --prefix=/tmp/smokeping-$$-build
make install
make dist
echo READY TO SYNC ?
read XXX
scp CHANGES smokeping-$VERSION.tar.gz oposs@freddie:public_html/smokeping/pub
rm -fr /tmp/smokeping-$$-build
git tag $VERSION
echo "run 'git push;git push --tags' to sync github"

