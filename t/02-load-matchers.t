#!/usr/bin/env perl

# Load every matcher module under lib/Smokeping/matchers/.
# Matchers have no external CPAN deps, so any failure here is real.

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";
use SPTest;

my $dir = "$FindBin::Bin/../lib/Smokeping/matchers";
my @files;
if (opendir(my $dh, $dir)) {
    @files = sort grep { /\.pm$/ } readdir $dh;
    closedir $dh;
} else {
    fail("cannot read $dir: $!");
}

ok(@files, "found matcher modules in $dir");

for my $file (@files) {
    (my $mod = $file) =~ s/\.pm$//;
    try_load("Smokeping::matchers::$mod");
}

done_testing();
