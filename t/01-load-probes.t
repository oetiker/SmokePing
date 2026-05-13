#!/usr/bin/env perl

# Load every probe module under lib/Smokeping/probes/.
#
# Many probes pull in optional CPAN modules (Authen::Radius, Net::LDAP,
# Net::OpenSSH, ...); those count as skips when absent, not failures.
# A failure here means an internal SmokePing symbol is broken.

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";
use SPTest;

my $probe_dir = "$FindBin::Bin/../lib/Smokeping/probes";
my @probes;
if (opendir(my $dh, $probe_dir)) {
    @probes = sort grep { /\.pm$/ } readdir $dh;
    closedir $dh;
} else {
    fail("cannot read $probe_dir: $!");
}

ok(@probes, "found probe modules in $probe_dir");

for my $file (@probes) {
    (my $mod = $file) =~ s/\.pm$//;
    try_load("Smokeping::probes::$mod");
}

done_testing();
