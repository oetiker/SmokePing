#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use Storable qw(retrieve);
use Fcntl qw(:flock);
use FindBin;
use lib "$FindBin::Bin/../lib";

our ($before_lock, $fail_lock);
BEGIN {
    *CORE::GLOBAL::flock = sub (*$) {
        my ($fh, $operation) = @_;
        return 0 if $fail_lock;
        if ($before_lock && $operation == LOCK_EX) {
            my $hook = $before_lock;
            undef $before_lock;
            $hook->();
        }
        return CORE::flock($fh, $operation);
    };
}
use Smokeping::Master;

my $dir = tempdir(CLEANUP => 1);
my $cfg = { General => { datadir => $dir } };

subtest 'slave membership uses complete names' => sub {
    for my $case (['east', 'east', 1], ['east', 'east-2', 0],
            ['east-2', 'east-2 west', 1], ['east.2', 'eastx2', 0],
            ['east.2', 'west east.2', 1]) {
        my ($slave, $members, $expected) = @$case;
        my $target = Smokeping::Master::get_targets(
            { probe => 'FPing', slaves => $members, host => 'example.invalid' }, $slave);
        is(!!$target, !!$expected, "$slave membership in '$members'");
    }
    is(Smokeping::Master::get_targets({ probe => 'FPing', host => 'example.invalid' }, 'east'),
        undef, 'target without a slaves list is not polled by slaves');
};

subtest 'reader skips a cache it cannot lock' => sub {
    Smokeping::Master::save_updates($cfg, 'east', "locked\t100\tsample");
    my @warn;
    local $SIG{__WARN__} = sub { push @warn, @_ };
    my $read = do {
        local $fail_lock = 1;
        Smokeping::Master::get_slaveupdates($cfg, "$dir/locked", 'east');
    };
    is_deeply($read, [], 'an unlockable cache yields no updates');
    like("@warn", qr/Could not lock/, 'the lock failure is reported');
    is_deeply([map { $_->[2] } @{Smokeping::Master::get_slaveupdates($cfg, "$dir/locked", 'east')}],
        ['sample'], 'the sample is still there for the next round');
};

subtest 'reader retries a replaced cache' => sub {
    Smokeping::Master::save_updates($cfg, 'east', "target\t100\told-sample");
    $before_lock = sub {
        Smokeping::Master::save_updates($cfg, 'east', "target\t101\tnew-sample");
    };
    my $read = Smokeping::Master::get_slaveupdates($cfg, "$dir/target", 'east');
    is_deeply([map { $_->[2] } @$read], ['old-sample', 'new-sample'],
        'both samples survive replacement between open and lock');
    is_deeply(Smokeping::Master::get_slaveupdates($cfg, "$dir/target", 'east'), [],
        'consumed cache is empty');
};

subtest 'writer retries another writer replacement' => sub {
    Smokeping::Master::save_updates($cfg, 'east', "target\t100\tfirst");
    $before_lock = sub {
        Smokeping::Master::save_updates($cfg, 'east', "target\t101\tsecond");
    };
    Smokeping::Master::save_updates($cfg, 'east', "target\t102\tthird");
    my $read = Smokeping::Master::get_slaveupdates($cfg, "$dir/target", 'east');
    is_deeply([map { $_->[2] } @$read], ['first', 'second', 'third'],
        'writer appends to current inode after waiting');
};

subtest 'writer retries a reader removal' => sub {
    Smokeping::Master::save_updates($cfg, 'east', "target\t100\tfirst");
    $before_lock = sub {
        my $read = Smokeping::Master::get_slaveupdates($cfg, "$dir/target", 'east');
        is_deeply([map { $_->[2] } @$read], ['first'], 'reader consumes the previous sample');
    };
    Smokeping::Master::save_updates($cfg, 'east', "target\t101\tsecond");
    my $read = Smokeping::Master::get_slaveupdates($cfg, "$dir/target", 'east');
    is_deeply([map { $_->[2] } @$read], ['second'], 'new sample is saved after removal');
};

subtest 'repeated replacements do not exhaust writer retries' => sub {
    Smokeping::Master::save_updates($cfg, 'east', "target\t100\tfirst");
    my $replacements = 4;
    my $replace;
    $replace = sub {
        Smokeping::Master::save_updates($cfg, 'east', "target\t101\tcompetitor-$replacements");
        $before_lock = $replace if --$replacements;
    };
    $before_lock = $replace;
    Smokeping::Master::save_updates($cfg, 'east', "target\t102\tmy-sample");
    my $read = Smokeping::Master::get_slaveupdates($cfg, "$dir/target", 'east');
    is_deeply([map { $_->[2] } @$read],
        ['first', 'competitor-4', 'competitor-3', 'competitor-2', 'competitor-1', 'my-sample'],
        'every accepted sample survives more than three inode replacements');
};

done_testing;
