#!/bin/sh
set -e
VERSION=`cat VERSION`
mkdir -p conftools
./bootstrap
./configure  --enable-maintainer-mode --prefix=/tmp/smokeping-$$-build
make
make clean
make install
touch PERL_MODULES
make PERL=perl-5.10.1 || true
make dist
#scp CHANGES smokeping-$VERSION.tar.gz oposs@freddie:public_html/smokeping/pub
rm -fr /tmp/smokeping-$$-build
