#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::RealBin/../lib";
use Test::More;

use_ok('Smokeping::matchers::CheckLoss');
use_ok('Smokeping::matchers::CheckLatency');
use_ok('Smokeping::matchers::ExpLoss');
use_ok('Smokeping::matchers::Median');

# =============================================================================
# CheckLoss matcher
# =============================================================================

{
    my $m = Smokeping::matchers::CheckLoss->new(l => 10, x => 3);
    isa_ok($m, 'Smokeping::matchers::CheckLoss', 'CheckLoss constructor');
    isa_ok($m, 'Smokeping::matchers::base', 'CheckLoss inherits from base');

    # Length returns the x parameter
    is($m->Length(), 3, 'CheckLoss Length returns x parameter');

    # Alert not raised (prevmatch=0), all loss values >= threshold -> triggers
    my $data_high_loss = {
        rtt  => [0.001, 0.002, 0.003],
        loss => [15, 20, 25],
        prevmatch => 0,
    };
    ok($m->Test($data_high_loss), 'CheckLoss triggers when loss >= threshold for x samples');

    # Alert not raised (prevmatch=0), all loss values below threshold -> no trigger
    my $data_low_loss = {
        rtt  => [0.001, 0.002, 0.003],
        loss => [0, 1, 2],
        prevmatch => 0,
    };
    ok(!$m->Test($data_low_loss), 'CheckLoss does not trigger when loss < threshold');

    # Alert already raised (prevmatch=1), all loss below threshold -> clears
    my $data_clearing = {
        rtt  => [0.001, 0.002, 0.003],
        loss => [0, 1, 2],
        prevmatch => 1,
    };
    ok(!$m->Test($data_clearing), 'CheckLoss clears when loss < threshold for x samples');

    # Alert already raised (prevmatch=1), loss still high -> holds alert
    my $data_holding = {
        rtt  => [0.001, 0.002, 0.003],
        loss => [15, 20, 25],
        prevmatch => 1,
    };
    ok($m->Test($data_holding), 'CheckLoss holds alert when loss still >= threshold');

    # Edge case: 'S' marker in data returns prevmatch
    my $data_with_s = {
        rtt  => [0.001, 0.002, 0.003],
        loss => [15, 'S', 25],
        prevmatch => 0,
    };
    is($m->Test($data_with_s), 0, 'CheckLoss returns prevmatch when S marker present');

    my $data_with_s_prev1 = {
        rtt  => [0.001, 0.002, 0.003],
        loss => [15, 'S', 25],
        prevmatch => 1,
    };
    is($m->Test($data_with_s_prev1), 1, 'CheckLoss returns prevmatch=1 when S marker present');

    # Edge case: fewer samples than x
    my $data_short = {
        rtt  => [0.001],
        loss => [15],
        prevmatch => 0,
    };
    # With only 1 sample but x=3, cannot reach count threshold
    ok(!$m->Test($data_short), 'CheckLoss handles fewer samples than x');

    # Construction fails with unknown parameter
    eval { Smokeping::matchers::CheckLoss->new(l => 10, bogus => 1) };
    like($@, qr/not known/, 'CheckLoss rejects unknown parameter');

    # Construction fails with invalid parameter value
    eval { Smokeping::matchers::CheckLoss->new(l => 'abc', x => 3) };
    like($@, qr/invalid data/, 'CheckLoss rejects non-numeric l value');

    eval { Smokeping::matchers::CheckLoss->new(l => 10, x => 'abc') };
    like($@, qr/invalid data/, 'CheckLoss rejects non-numeric x value');
}

# =============================================================================
# CheckLatency matcher
# =============================================================================

{
    # l is in milliseconds, internally divided by 1000 for comparison
    my $m = Smokeping::matchers::CheckLatency->new(l => 100, x => 3);
    isa_ok($m, 'Smokeping::matchers::CheckLatency', 'CheckLatency constructor');
    isa_ok($m, 'Smokeping::matchers::base', 'CheckLatency inherits from base');

    # Length returns the x parameter
    is($m->Length(), 3, 'CheckLatency Length returns x parameter');

    # Alert not raised (prevmatch=0), all rtt >= threshold (0.1s = 100ms) -> triggers
    my $data_high_latency = {
        rtt  => [0.200, 0.300, 0.400],
        loss => [0, 0, 0],
        prevmatch => 0,
    };
    ok($m->Test($data_high_latency), 'CheckLatency triggers when latency >= threshold');

    # Alert not raised (prevmatch=0), all rtt below threshold -> no trigger
    my $data_low_latency = {
        rtt  => [0.010, 0.020, 0.030],
        loss => [0, 0, 0],
        prevmatch => 0,
    };
    ok(!$m->Test($data_low_latency), 'CheckLatency does not trigger when latency < threshold');

    # Alert already raised (prevmatch=1), all rtt below threshold -> clears
    my $data_clearing = {
        rtt  => [0.010, 0.020, 0.030],
        loss => [0, 0, 0],
        prevmatch => 1,
    };
    ok(!$m->Test($data_clearing), 'CheckLatency clears when latency < threshold for x samples');

    # Alert already raised (prevmatch=1), rtt still high -> holds alert
    my $data_holding = {
        rtt  => [0.200, 0.300, 0.400],
        loss => [0, 0, 0],
        prevmatch => 1,
    };
    ok($m->Test($data_holding), 'CheckLatency holds alert when latency still >= threshold');

    # Edge case: 'S' marker in rtt returns prevmatch
    my $data_with_s = {
        rtt  => [0.200, 'S', 0.400],
        loss => [0, 0, 0],
        prevmatch => 0,
    };
    is($m->Test($data_with_s), 0, 'CheckLatency returns prevmatch when S marker present');

    # Edge case: fewer samples than x
    my $data_short = {
        rtt  => [0.200],
        loss => [0],
        prevmatch => 0,
    };
    ok(!$m->Test($data_short), 'CheckLatency handles fewer samples than x');

    # Construction fails with unknown parameter
    eval { Smokeping::matchers::CheckLatency->new(l => 100, bogus => 1) };
    like($@, qr/not known/, 'CheckLatency rejects unknown parameter');

    # Construction fails with invalid parameter value
    eval { Smokeping::matchers::CheckLatency->new(l => 'abc', x => 3) };
    like($@, qr/invalid data/, 'CheckLatency rejects non-numeric l value');
}

# =============================================================================
# ExpLoss matcher
# =============================================================================

{
    my $m = Smokeping::matchers::ExpLoss->new(hist => 10, rising => 50);
    isa_ok($m, 'Smokeping::matchers::ExpLoss', 'ExpLoss constructor');
    isa_ok($m, 'Smokeping::matchers::base', 'ExpLoss inherits from base');

    # Length returns the hist parameter
    is($m->Length(), 10, 'ExpLoss Length returns hist parameter');

    # High loss should trigger (all 100% loss, well above rising=50)
    my $data_high = {
        rtt  => [(0.001) x 10],
        loss => [(100) x 10],
        prevmatch => 0,
    };
    ok($m->Test($data_high), 'ExpLoss triggers on high loss above rising threshold');

    # Low loss should not trigger (all 0% loss, below rising=50)
    my $data_low = {
        rtt  => [(0.001) x 10],
        loss => [(0) x 10],
        prevmatch => 0,
    };
    ok(!$m->Test($data_low), 'ExpLoss does not trigger on low loss');

    # Edge case: returns undef when too few samples (with skip)
    my $m_skip = Smokeping::matchers::ExpLoss->new(hist => 10, rising => 50, skip => 5);
    my $data_few = {
        rtt  => [(0.001) x 3],
        loss => [(100) x 3],
        prevmatch => 0,
    };
    is($m_skip->Test($data_few), undef, 'ExpLoss returns undef with fewer samples than skip+1');

    # Edge case: 'S' markers are skipped
    my $data_with_s = {
        rtt  => [(0.001) x 10],
        loss => [100, 'S', 100, 'S', 100, 100, 100, 100, 100, 100],
        prevmatch => 0,
    };
    ok($m->Test($data_with_s), 'ExpLoss skips S markers and still evaluates');

    # Edge case: 'U' markers are skipped
    my $data_with_u = {
        rtt  => [(0.001) x 10],
        loss => [100, 'U', 100, 100, 100, 100, 100, 100, 100, 100],
        prevmatch => 0,
    };
    ok($m->Test($data_with_u), 'ExpLoss skips U markers and still evaluates');

    # Edge case: all S/U markers returns undef (num==0)
    my $data_all_s = {
        rtt  => [('S') x 5],
        loss => [('S') x 5],
        prevmatch => 0,
    };
    is($m->Test($data_all_s), undef, 'ExpLoss returns undef when all samples are S/U');

    # Hysteresis: with falling threshold, prevmatch matters
    my $m_hyst = Smokeping::matchers::ExpLoss->new(
        hist => 5, rising => 60, falling => 30
    );

    # Loss at 40 (between falling=30 and rising=60): should not trigger fresh
    my $data_mid = {
        rtt  => [(0.001) x 5],
        loss => [(40) x 5],
        prevmatch => 0,
    };
    ok(!$m_hyst->Test($data_mid),
        'ExpLoss does not trigger when loss between falling and rising (prevmatch=0)');

    # Loss at 40 with prevmatch=1: should hold (above falling=30)
    my $data_mid_prev = {
        rtt  => [(0.001) x 5],
        loss => [(40) x 5],
        prevmatch => 1,
    };
    ok($m_hyst->Test($data_mid_prev),
        'ExpLoss holds alert when loss between falling and rising (prevmatch=1)');

    # Fast transition test
    my $m_fast = Smokeping::matchers::ExpLoss->new(
        hist => 10, rising => 50, fast => 3
    );
    my $data_fast_rise = {
        rtt  => [(0.001) x 10],
        loss => [0, 0, 0, 0, 0, 0, 0, 80, 80, 80],
        prevmatch => 0,
    };
    ok($m_fast->Test($data_fast_rise),
        'ExpLoss fast transition triggers on last fast samples above rising');

    # Construction fails with unknown parameter
    eval { Smokeping::matchers::ExpLoss->new(hist => 10, rising => 50, bogus => 1) };
    like($@, qr/not known/, 'ExpLoss rejects unknown parameter');

    # Construction fails with invalid parameter value
    eval { Smokeping::matchers::ExpLoss->new(hist => 'abc', rising => 50) };
    like($@, qr/invalid data/, 'ExpLoss rejects non-numeric hist value');
}

# =============================================================================
# Median matcher
# =============================================================================

{
    my $m = Smokeping::matchers::Median->new(old => 5, new => 5, diff => 0.010);
    isa_ok($m, 'Smokeping::matchers::Median', 'Median constructor');
    isa_ok($m, 'Smokeping::matchers::base', 'Median inherits from base');

    # Length returns old + new
    is($m->Length(), 10, 'Median Length returns old + new');

    # Old median ~0.010, new median ~0.050, diff=0.040 > 0.010 -> match
    my $data_changed = {
        rtt  => [0.008, 0.009, 0.010, 0.011, 0.012,
                 0.048, 0.049, 0.050, 0.051, 0.052],
        loss => [(0) x 10],
        prevmatch => 0,
    };
    ok($m->Test($data_changed), 'Median triggers when new median differs from old');

    # Old and new medians are similar -> no match
    my $data_stable = {
        rtt  => [0.010, 0.011, 0.010, 0.011, 0.010,
                 0.010, 0.011, 0.010, 0.011, 0.010],
        loss => [(0) x 10],
        prevmatch => 0,
    };
    ok(!$m->Test($data_stable), 'Median does not trigger when latency is stable');

    # Decrease in latency also triggers (absolute difference)
    my $data_decreased = {
        rtt  => [0.048, 0.049, 0.050, 0.051, 0.052,
                 0.008, 0.009, 0.010, 0.011, 0.012],
        loss => [(0) x 10],
        prevmatch => 0,
    };
    ok($m->Test($data_decreased), 'Median triggers on latency decrease too');

    # Edge case: fewer data points than old+new
    my $data_short = {
        rtt  => [0.010, 0.020, 0.030],
        loss => [(0) x 3],
        prevmatch => 0,
    };
    # Should not crash; adjusts cc and bc to available count
    my $result = eval { $m->Test($data_short) };
    ok(!$@, 'Median handles fewer data points than old+new without crashing');

    # Edge case: exact threshold boundary (diff exactly equal, not greater)
    my $m2 = Smokeping::matchers::Median->new(old => 3, new => 3, diff => 0.010);
    my $data_boundary = {
        rtt  => [0.020, 0.020, 0.020, 0.030, 0.030, 0.030],
        loss => [(0) x 6],
        prevmatch => 0,
    };
    # diff is exactly 0.010, matcher requires > not >=
    ok(!$m2->Test($data_boundary), 'Median does not trigger when diff equals threshold exactly');

    # Construction fails with unknown parameter
    eval { Smokeping::matchers::Median->new(old => 5, new => 5, bogus => 1) };
    like($@, qr/not known/, 'Median rejects unknown parameter');

    # Construction fails with invalid parameter value
    eval { Smokeping::matchers::Median->new(old => 'abc', new => 5, diff => 0.01) };
    like($@, qr/invalid data/, 'Median rejects non-numeric old value');

    eval { Smokeping::matchers::Median->new(old => 5, new => 5, diff => 'xyz') };
    like($@, qr/invalid data/, 'Median rejects non-numeric diff value');
}

done_testing;
