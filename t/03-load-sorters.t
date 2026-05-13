#!/usr/bin/env perl

# Load every sorter module under lib/Smokeping/sorters/.
# Sorters have no external CPAN deps, so any failure here is real.

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";
use SPTest;

my $dir = "$FindBin::Bin/../lib/Smokeping/sorters";
my @files;
if (opendir(my $dh, $dir)) {
    @files = sort grep { /\.pm$/ } readdir $dh;
    closedir $dh;
} else {
    fail("cannot read $dir: $!");
}

ok(@files, "found sorter modules in $dir");

for my $file (@files) {
    (my $mod = $file) =~ s/\.pm$//;
    try_load("Smokeping::sorters::$mod");
}

done_testing();
