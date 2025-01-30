#!/bin/sh
set -e
[ `git status -s | wc -l` -gt 0 ] && echo "ERROR: commit all changes before release" && exit 1
VERSION=`cat VERSION`
echo ${V} `date +"%Y-%m-%d %H:%M:%S %z"` `git config user.name` '<'`git config user.email`'>' >> CHANGES.new
echo >> CHANGES.new
echo ' -' >> CHANGES.new
echo >> CHANGES.new
cat CHANGES >> CHANGES.new && mv CHANGES.new CHANGES
$EDITOR CHANGES
./bootstrap
./configure  --enable-maintainer-mode --prefix=/tmp/smokeping-$$-build
make
make clean
make install
make dist
echo READY TO SYNC ?
read XXX
scp CHANGES smokeping-$VERSION.tar.gz oposs@freddie:public_html/smokeping/pub
rm -fr /tmp/smokeping-$$-build
git tag $VERSION
echo "run 'git push;git push --tags' to sync github"

