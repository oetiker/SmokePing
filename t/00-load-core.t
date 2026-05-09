#!/usr/bin/env perl

# Load every core SmokePing module.
#
# These are not optional. If one of them fails to load and the failure is
# not "an external CPAN dep is missing", that is a regression.

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";
use SPTest;

my @core = qw(
    Smokeping
    Smokeping::Config
    Smokeping::Master
    Smokeping::Slave
    Smokeping::Colorspace
    Smokeping::RRDhelpers
    Smokeping::RRDtools
    Smokeping::Graphs
    Smokeping::Examples
    SNMP_Session
    SNMP_util
    BER
);

try_load($_) for @core;

done_testing();
