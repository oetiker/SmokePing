#!/usr/bin/env perl

# How probe results become an RRD update string, and how DismanPing
# trims the history table it reads back from the device.

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp ();

our $simulating;
BEGIN {
    # DismanPing sleeps while the device runs the test
    *CORE::GLOBAL::sleep = sub (;$) { return $simulating ? 0 : CORE::sleep($_[0] || 0) };
}

eval { require Smokeping; require Smokeping::probes::base; 1 }
    or plan skip_all => "Smokeping core does not load: $@";

my @log;
{
    no warnings qw(redefine once);
    *Smokeping::do_log = sub (@) { push @log, join ' ', @_ };
    *Smokeping::do_debuglog = sub ($) { };
}

my $tmp = File::Temp->newdir;

sub update_string {
    my ($pings, @rtts) = @_;
    my $probe = Smokeping::probes::base->new({}, { Database => { pings => $pings }, General => { datadir => "$tmp" } }, 'Test');
    my $tree = { addr => '192.0.2.1', probe => 'Test' };
    $probe->{targets}{$tree} = '192.0.2.1';
    $probe->{rtts}{$tree} = [@rtts] if @rtts or defined $rtts[0];
    @log = ();
    return $probe->rrdupdate_string($tree);
}

# fields: age:loss:median:ping1:...:pingN
is(update_string(3, 0.01, 0.02, 0.03), 'U:0:0.02:0.01:0.02:0.03', 'all pings answered');
is(update_string(4, 0.01, 0.03), 'U:2:0.03:U:0.01:0.03:U', 'losses pad both ends');
is(update_string(3, 0, 0, 0.1), 'U:0:0:0:0:0.1', 'a zero median is kept');
is(update_string(3), 'U:3:U:U:U:U', 'no samples');
{
    no warnings 'uninitialized';
    like(update_string(3, 0.01, undef), qr/^U:1:U:/, 'an undefined median sample is recorded as unknown');
}

is(update_string(3, 0.01, 0.02, 0.03, 0.04), 'U:0:0.02:0.01:0.02:0.03', 'one extra sample is dropped from the top');
like("@log", qr/got 4 answers for 3 pings from 192\.0\.2\.1, keeping 3/, 'extra samples are logged');
is(update_string(3, 0.01, 0.02, 0.03, 0.04, 0.05), 'U:0:0.03:0.02:0.03:0.04', 'extra samples are dropped from both ends');

# DismanPing reads the device's history table back over SNMP
SKIP: {
    eval { require Smokeping::probes::DismanPing; 1 }
        or skip "DismanPing does not load: $@", 6;

    sub disman_round {
        my ($pings, @history) = @_;
        local $simulating = 1;
        my $probe = Smokeping::probes::DismanPing->new({}, { Database => { pings => $pings, step => 300 } }, 'DismanPing');
        my $tree = { host => '192.0.2.1', pinghost => 'public@router.example', pings => $pings };
        $probe->add($tree, '192.0.2.1');
        no warnings qw(redefine once);
        local *Smokeping::probes::DismanPing::snmpset = sub { return 1 };
        local *Smokeping::probes::DismanPing::snmpget = sub { return 2 };    # test finished
        local *Smokeping::probes::DismanPing::snmpmaptable = sub {
            my ($host, $cb) = @_;
            $cb->($_, @{$history[$_]}) for 0 .. $#history;
            return scalar @history;
        };
        @log = ();
        my $stderr = '';
        {
            local *STDERR;
            open STDERR, '>', \$stderr or die $!;
            $probe->ping;
        }
        return ($probe->{rtts}{$tree}, $stderr);
    }

    # history rows are [rtt in ms, status]; status 1 is responseReceived
    my ($rtts, $stderr) = disman_round(3, [10, 1], [20, 1], [30, 1]);
    is_deeply($rtts, ['1.0000000000e-02', '2.0000000000e-02', '3.0000000000e-02'], 'exact history is used');
    is($stderr, '', 'nothing is written to stderr');

    ($rtts) = disman_round(3, [40, 1], [10, 1], [20, 1], [30, 1]);
    is_deeply($rtts, ['1.0000000000e-02', '2.0000000000e-02', '3.0000000000e-02'],
        'longer history keeps exactly the last pings rows');
    like("@log", qr/returned 4 results, taking last 3/, 'longer history is logged');

    ($rtts) = disman_round(3, [10, 1], [20, 2], [30, 1]);
    is_deeply($rtts, ['1.0000000000e-02', '3.0000000000e-02'], 'unanswered pings are dropped');

    ($rtts) = disman_round(3, [10, 1]);
    is($rtts, undef, 'short history records nothing');
}

done_testing();
