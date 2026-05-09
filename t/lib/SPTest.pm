package SPTest;

# Copyright (C) 2026 Avinash Duduskar
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# Shared helpers for the SmokePing test suite.
#
# try_load($module) attempts to require $module and emits one test result:
#   * pass  - module loaded successfully
#   * skip  - module load failed because an external CPAN dep is missing
#             (the test environment does not have the optional dependency)
#   * fail  - module load failed for any other reason: syntax error,
#             missing internal SmokePing module, undefined sub at compile
#             time, etc.
#
# The skip-vs-fail split is what makes this useful: a contributor running
# the suite without every CPAN dep installed sees skips, not noise, while
# a regression that breaks internal symbols still produces a real failure.

use strict;
use warnings;
use Test::More;
use Exporter 'import';

our @EXPORT = qw(try_load);

sub try_load {
    my ($mod) = @_;
    my $rc = eval "require $mod; 1";
    my $err = $@;

    if ($rc) {
        pass("load $mod");
        return 1;
    }

    chomp(my $first_line = (split /\n/, ($err // ''))[0] // '');

    if ($err && $err =~ /Can't locate (\S+?)\.pm in \@INC/) {
        my $missing = $1;
        $missing =~ s{/}{::}g;
        unless ($missing =~ /^(Smokeping|SNMP_Session|SNMP_util|BER)\b/) {
            Test::More->builder->skip(
                "$mod requires $missing (not installed)"
            );
            return 1;
        }
    }

    fail("load $mod");
    diag("error loading $mod: $first_line");
    return 0;
}

1;
