#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::RealBin/../lib";
use Test::More;

use_ok('Smokeping::sorters::Loss');
use_ok('Smokeping::sorters::Median');
use_ok('Smokeping::sorters::Max');
use_ok('Smokeping::sorters::StdDev');

my $typical_info = {
    uptime => 100,
    loss   => 5,
    median => 10,
    alert  => 0,
    pings  => [1, 2, 3, 4, 5],
};

# --- Loss sorter ---

{
    my $s = Smokeping::sorters::Loss->new(entries => 5);
    isa_ok($s, 'Smokeping::sorters::Loss', 'Loss constructor');
    isa_ok($s, 'Smokeping::sorters::base', 'Loss inherits from base');

    # CalcValue with typical input
    is($s->CalcValue($typical_info), 5, 'Loss CalcValue returns loss value');

    # Edge case: undef loss (falsy) returns -1
    is($s->CalcValue({ %$typical_info, loss => undef }), -1,
        'Loss CalcValue returns -1 for undef loss');

    # Edge case: zero loss (falsy) returns -1
    is($s->CalcValue({ %$typical_info, loss => 0 }), -1,
        'Loss CalcValue returns -1 for zero loss');

    # Construction fails with unknown parameter
    eval { Smokeping::sorters::Loss->new(bogus => 1) };
    like($@, qr/not known/, 'Loss rejects unknown parameter');

    # Construction fails with invalid parameter value
    eval { Smokeping::sorters::Loss->new(entries => 'abc') };
    like($@, qr/invalid data/, 'Loss rejects non-numeric entries');
}

# --- Median sorter ---

{
    my $s = Smokeping::sorters::Median->new(entries => 5);
    isa_ok($s, 'Smokeping::sorters::Median', 'Median constructor');
    isa_ok($s, 'Smokeping::sorters::base', 'Median inherits from base');

    # CalcValue with typical input
    is($s->CalcValue($typical_info), 10, 'Median CalcValue returns median value');

    # Edge case: undef median returns -1
    is($s->CalcValue({ %$typical_info, median => undef }), -1,
        'Median CalcValue returns -1 for undef median');

    # Edge case: zero median returns -1
    is($s->CalcValue({ %$typical_info, median => 0 }), -1,
        'Median CalcValue returns -1 for zero median');

    # Construction fails with unknown parameter
    eval { Smokeping::sorters::Median->new(bogus => 1) };
    like($@, qr/not known/, 'Median rejects unknown parameter');

    # Construction fails with invalid parameter value
    eval { Smokeping::sorters::Median->new(entries => 'abc') };
    like($@, qr/invalid data/, 'Median rejects non-numeric entries');
}

# --- Max sorter ---

{
    my $s = Smokeping::sorters::Max->new(entries => 5);
    isa_ok($s, 'Smokeping::sorters::Max', 'Max constructor');
    isa_ok($s, 'Smokeping::sorters::base', 'Max inherits from base');

    # CalcValue with typical input
    is($s->CalcValue($typical_info), 5, 'Max CalcValue returns max ping');

    # Edge case: empty pings returns -1
    is($s->CalcValue({ %$typical_info, pings => [] }), -1,
        'Max CalcValue returns -1 for empty pings');

    # Edge case: all undef pings returns -1
    is($s->CalcValue({ %$typical_info, pings => [undef, undef, undef] }), -1,
        'Max CalcValue returns -1 for all undef pings');

    # Construction fails with unknown parameter
    eval { Smokeping::sorters::Max->new(bogus => 1) };
    like($@, qr/not known/, 'Max rejects unknown parameter');

    # Construction fails with invalid parameter value
    eval { Smokeping::sorters::Max->new(entries => 'abc') };
    like($@, qr/invalid data/, 'Max rejects non-numeric entries');
}

# --- StdDev sorter ---

{
    my $s = Smokeping::sorters::StdDev->new(entries => 5);
    isa_ok($s, 'Smokeping::sorters::StdDev', 'StdDev constructor');
    isa_ok($s, 'Smokeping::sorters::base', 'StdDev inherits from base');

    # CalcValue with typical input: stddev of [1,2,3,4,5]
    # mean=3, variance = (4+1+0+1+4)/5 = 2, stddev = sqrt(2)
    my $val = $s->CalcValue($typical_info);
    ok(abs($val - sqrt(2)) < 0.0001, 'StdDev CalcValue returns correct standard deviation');

    # Edge case: empty pings returns -1
    is($s->CalcValue({ %$typical_info, pings => [] }), -1,
        'StdDev CalcValue returns -1 for empty pings');

    # Edge case: all undef pings returns -1
    is($s->CalcValue({ %$typical_info, pings => [undef, undef, undef] }), -1,
        'StdDev CalcValue returns -1 for all undef pings');

    # Edge case: single ping has zero stddev
    is($s->CalcValue({ %$typical_info, pings => [42] }), 0,
        'StdDev CalcValue returns 0 for single ping');

    # Construction fails with unknown parameter
    eval { Smokeping::sorters::StdDev->new(bogus => 1) };
    like($@, qr/not known/, 'StdDev rejects unknown parameter');

    # Construction fails with invalid parameter value
    eval { Smokeping::sorters::StdDev->new(entries => 'abc') };
    like($@, qr/invalid data/, 'StdDev rejects non-numeric entries');
}

done_testing;
