#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

our ($simulating, $clock, $pids, $scenario, $wakeup, @signals);
BEGIN {
    *CORE::GLOBAL::time = sub () { return $clock || CORE::time() };
    *CORE::GLOBAL::sleep = sub (;$) {
        return CORE::sleep($_[0] || 0) unless $simulating;
        $clock++;
        $SIG{HUP}->() unless $wakeup++;
        die "simulation exceeded deadline\n" if $clock > 1000000020;
        return 1;
    };
    *CORE::GLOBAL::kill = sub {
        die "unexpected signal outside reload simulation\n" unless $simulating;
        my ($signal, @targets) = @_;
        push @signals, [$signal, @targets];
        if ($signal == 15) {
            return 0 if $scenario eq 'failed';
            if ($scenario eq 'vanished') {
                # the child exited before the signal reached it
                delete $pids->{$_} for @targets;
                return 0;
            }
            delete $pids->{$_} for $scenario eq 'stopped' ? @targets : ();
        }
        return scalar @targets;
    };
    *CORE::GLOBAL::exit = sub (;$) {
        die "EXIT $_[0]\n" if $simulating;
        CORE::exit($_[0] || 0);
    };
}
use Smokeping;

{
    package ReloadProbe;
    sub step { 2 }
}

for my $case (['stopped', 'RESTARTED'], ['failed', 'EXIT 1'], ['stuck', 'EXIT 1'],
        ['vanished', 'RESTARTED']) {
    subtest "overdue child: $case->[0]" => sub {
        local $simulating = 1;
        local $scenario = $case->[0];
        local $clock = 1000000000;
        local $wakeup = 0;
        local @signals;
        local %SIG = %SIG;
        local @ARGV = ('--nodaemon');
        my $starts = 0;
        no warnings 'redefine';
        local *Smokeping::load_cfg = sub ($;$) {
            $Smokeping::cfg = { General => { concurrentprobes => 'yes' } };
            $Smokeping::probes = { a => bless({}, 'ReloadProbe'), b => bless({}, 'ReloadProbe') };
        };
        local *Smokeping::reload_cfg = sub ($) { return 1 };
        local *Smokeping::do_log = sub (@) {};
        local *Smokeping::do_debuglog = sub {};
        local *Smokeping::start_probes = sub {
            die "RESTARTED\n" if $starts++;
            $pids = $_[0];
            $pids->{12345} = 'a';
            return 12345;
        };
        eval { Smokeping::main('unused') };
        like($@, qr/\Q$case->[1]\E/, 'reload reaches the expected outcome');
        my @term = grep { $_->[0] == 15 } @signals;
        is_deeply(\@term, [[15, 12345]], 'TERM is sent once to the overdue child only');
        if ($scenario eq 'stuck') {
            cmp_ok($clock, '>=', 1000000007, 'TERM grace period is observed');
            cmp_ok($clock, '<=', 1000000010, 'grace period is not reset on each pass');
        }
    };
}

done_testing;
