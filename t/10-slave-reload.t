#!/usr/bin/env perl

# A slave that cannot load the configuration pushed by its master keeps
# running with its current configuration instead of exiting.

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

our ($simulating, $sleeps, @signals);
BEGIN {
    *CORE::GLOBAL::sleep = sub (;$) {
        return CORE::sleep($_[0] || 0) unless $simulating;
        # the first sleep delivers the HUP, the next one ends the run
        die "IDLE\n" if $sleeps++;
        $SIG{HUP}->();
        return 1;
    };
    *CORE::GLOBAL::kill = sub {
        die "unexpected signal outside simulation\n" unless $simulating;
        push @signals, [@_];
        return scalar @_ - 1;
    };
}

eval { require Smokeping; 1 }
    or plan skip_all => "Smokeping core does not load: $@";

{
    package FakeProbe;
    sub new { bless {}, shift }
    sub step { 300 }
    sub offset { 0 }
    sub offset_in_seconds { }
}

my @log;
my $reports = 0;
no warnings qw(redefine once);
*Smokeping::do_log = sub (@) { push @log, join '', @_ };
*Smokeping::do_debuglog = sub ($) { };
*Smokeping::report_probes = sub ($$) { $reports++ };
use warnings qw(redefine once);

sub slave_cfg {
    my %general = @_;
    return { General => { changeprocessnames => 'no', %general }, Database => { step => 300 } };
}

# reload_cfg_slave
{
    my $old_cfg = slave_cfg();
    my $old_probes = { a => FakeProbe->new };
    local $Smokeping::cfg = $old_cfg;
    local $Smokeping::probes = $old_probes;
    no warnings 'redefine';

    local *Smokeping::load_cfg_slave = sub {
        $Smokeping::cfg = slave_cfg(new => 1);
        $Smokeping::probes = {};
        return { slave_name => 'boomer' };
    };
    is_deeply(Smokeping::reload_cfg_slave({}), { slave_name => 'boomer' },
        'successful reload returns the slave settings');
    ok($Smokeping::cfg->{General}{new}, 'successful reload installs the new config');

    $Smokeping::cfg = $old_cfg;
    $Smokeping::probes = $old_probes;
    @log = ();
    local *Smokeping::load_cfg_slave = sub {
        $Smokeping::cfg = undef;
        $Smokeping::probes = undef;
        die "Can't locate Smokeping/probes/Missing.pm\n";
    };
    is(Smokeping::reload_cfg_slave({}), undef, 'failed reload returns nothing');
    is($Smokeping::cfg, $old_cfg, 'failed reload restores the config');
    is($Smokeping::probes, $old_probes, 'failed reload restores the probes');
    ok((grep { /Reloading slave configuration failed: Can't locate/ } @log), 'failure is logged');
}

# main() keeps its parsed options in a file-scoped hash, so the master
# runs go before the slave runs that add --master-url.
{
    my $r = run_master(0);
    is($r->{died}, "ROUND\n", 'master keeps probing after a failed reload');
    is($r->{reloads}, 1, 'a failed reload is not retried every round');
    is($r->{reports}, 1, 'master did not restart');
}

{
    my $r = run_master(1);
    is($r->{reloads}, 1, 'master reloaded once');
    is($r->{reports}, 2, 'master restarted after a good reload');
}

# Run main() as a slave. load_cfg_slave succeeds at startup and fails on
# the reload triggered by the HUP.
sub run_slave {
    my %arg = @_;
    local $simulating = 1;
    local $sleeps = 0;
    local @signals;
    local %SIG = %SIG;
    local @ARGV = ('--nodaemon', '--nosleep', '--master-url=http://master/', '--cache-dir=/nonexistent',
        '--shared-secret=/nonexistent');
    local $Smokeping::cfg;
    local $Smokeping::probes;
    @log = ();
    my $loads = 0;
    my $initial;
    no warnings qw(redefine once);
    local *Smokeping::load_cfg_slave = sub {
        if ($loads++) {
            die "Can't locate Smokeping/probes/Missing.pm\n" unless $arg{reload_ok};
            $Smokeping::cfg = slave_cfg(concurrentprobes => $arg{concurrent});
            $Smokeping::probes = { a => FakeProbe->new, b => FakeProbe->new };
            return { slave_name => 'boomer' };
        }
        $Smokeping::cfg = $initial = slave_cfg(concurrentprobes => $arg{concurrent});
        $Smokeping::probes = { a => FakeProbe->new, b => FakeProbe->new };
        return { slave_name => 'boomer' };
    };
    local *Smokeping::start_probes = sub { $_[0]{4242} = 'a'; return 4242 };
    my $rounds = 0;
    local *Smokeping::run_probes = sub { die "ROUND\n" if $rounds++ };
    local *Smokeping::Slave::submit_results = sub { return { new => 'config' } };
    local *Smokeping::kill_smoke = sub { };
    eval { Smokeping::main('unused') };
    return { died => $@, loads => $loads, rounds => $rounds, signals => [@signals],
             same_cfg => ($Smokeping::cfg == $initial), log => [@log] };
}

{
    my $r = run_slave(concurrent => 'yes');
    is($r->{died}, "IDLE\n", 'parent keeps waiting after a failed slave reload');
    is($r->{loads}, 2, 'parent tried to reload the slave config');
    is_deeply($r->{signals}, [], 'children are not restarted when the reload fails');
    ok($r->{same_cfg}, 'parent keeps the old config');
}

{
    my $r = run_slave(concurrent => 'no');
    is($r->{died}, "ROUND\n", 'single-process slave keeps probing after a failed reload');
    is($r->{loads}, 2, 'single-process slave tried to reload');
    ok($r->{same_cfg}, 'single-process slave keeps the old config');
    ok(!(grep { /Restarting due to HUP/ } @{$r->{log}}), 'HUP flag is cleared after the failed reload');
}

{
    my $r = run_slave(concurrent => 'yes', reload_ok => 1);
    is($r->{loads}, 2, 'parent reloaded the slave config');
    ok((grep { $_->[0] == 1 and $_->[1] == 4242 } @{$r->{signals}}), 'children get a HUP after a good reload');
    ok(!$r->{same_cfg}, 'parent uses the new config');
}

{
    my $r = run_slave(concurrent => 'no', reload_ok => 1);
    is($r->{died}, "ROUND\n", 'single-process slave restarts after a good reload');
    is($r->{loads}, 2, 'single-process slave reloaded');
    ok(!$r->{same_cfg}, 'single-process slave uses the new config');
}

# Single-process master: a HUP arrives during the first round.
sub run_master {
    my $reload_ok = shift;
    local $simulating = 1;
    local %SIG = %SIG;
    local @ARGV = ('--nodaemon', '--nosleep', '--config=/nonexistent');
    local $Smokeping::cfg;
    local $Smokeping::probes;
    @log = ();
    $reports = 0;
    my ($reloads, $rounds) = (0, 0);
    no warnings qw(redefine once);
    local *Smokeping::load_cfg = sub ($;$) {
        $Smokeping::cfg = slave_cfg(concurrentprobes => 'no');
        $Smokeping::probes = { a => FakeProbe->new };
    };
    local *Smokeping::reload_cfg = sub ($) { $reloads++; return $reload_ok };
    local *Smokeping::run_probes = sub {
        $rounds++;
        $SIG{HUP}->() if $rounds == 1;
        die "ROUND\n" if $rounds > 2;
    };
    local *Smokeping::update_rrds = sub { };
    local *Smokeping::save_sortercache = sub { };
    eval { Smokeping::main('unused') };
    return { died => $@, reloads => $reloads, reports => $reports };
}

done_testing();
