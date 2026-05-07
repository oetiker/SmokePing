#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../thirdparty/lib/perl5";
use lib "$FindBin::Bin/../local-rrdtool/lib/perl/5.38.2";
use lib "$FindBin::Bin/../local-rrdtool/lib/perl/5.38.2/x86_64-linux-gnu-thread-multi";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../test-install/lib";
use POSIX qw(mktime);

# Smokeping.pm requires RRDs and other XS modules at compile time.
# Skip the entire test if they aren't available.
BEGIN {
    eval { require RRDs; 1 }
        or plan skip_all => 'RRDs not installed - skipping Smokeping utility tests';
}

use_ok('Smokeping');
use_ok('Smokeping::Request');

# ──────────────────────────────────────────────────────────
# min / max
# ──────────────────────────────────────────────────────────
subtest 'min' => sub {
    is(Smokeping::min(1, 2),   1, 'min(1,2) = 1');
    is(Smokeping::min(5, 3),   3, 'min(5,3) = 3');
    is(Smokeping::min(-1, 1), -1, 'min(-1,1) = -1');
    is(Smokeping::min(7, 7),   7, 'min(7,7) = 7');
    is(Smokeping::min(0, 0),   0, 'min(0,0) = 0');
    is(Smokeping::min(0.5, 0.3), 0.3, 'min with floats');
};

subtest 'max' => sub {
    is(Smokeping::max(1, 2),   2, 'max(1,2) = 2');
    is(Smokeping::max(5, 3),   5, 'max(5,3) = 5');
    is(Smokeping::max(-1, 1),  1, 'max(-1,1) = 1');
    is(Smokeping::max(7, 7),   7, 'max(7,7) = 7');
    is(Smokeping::max(0, 0),   0, 'max(0,0) = 0');
    is(Smokeping::max(0.1, 0.9), 0.9, 'max with floats');
};

# ──────────────────────────────────────────────────────────
# exp2seconds
# ──────────────────────────────────────────────────────────
subtest 'exp2seconds' => sub {
    is(Smokeping::exp2seconds('30s'),   30,           '30s = 30');
    is(Smokeping::exp2seconds('5m'),    300,          '5m = 300');
    is(Smokeping::exp2seconds('2h'),    7200,         '2h = 7200');
    is(Smokeping::exp2seconds('1d'),    86400,        '1d = 86400');
    is(Smokeping::exp2seconds('1w'),    604800,       '1w = 604800');
    is(Smokeping::exp2seconds('1y'),    31536000,     '1y = 31536000');
    is(Smokeping::exp2seconds('3600'),  3600,         'plain number passthrough');
    is(Smokeping::exp2seconds('10m'),   600,          '10m = 600');
    is(Smokeping::exp2seconds('0s'),    0,            '0s = 0');
};

# ──────────────────────────────────────────────────────────
# display_range
# ──────────────────────────────────────────────────────────
subtest 'display_range' => sub {
    is(Smokeping::display_range(10, 19), '10-19', 'range 10-19');
    is(Smokeping::display_range(5, 5),    5,      'equal values return single');
    is(Smokeping::display_range(10, 3),   3,      'upper < lower returns upper');
    is(Smokeping::display_range(0, 0),    0,      'zero range');
    is(Smokeping::display_range(1, 100), '1-100', 'wide range');
};

# ──────────────────────────────────────────────────────────
# parse_datetime
# ──────────────────────────────────────────────────────────
subtest 'parse_datetime' => sub {
    # Unix timestamp
    is(Smokeping::parse_datetime('1000000'), 1000000, 'unix timestamp passthrough');

    # "now" returns current time (within 2 seconds)
    my $before = time;
    my $now = Smokeping::parse_datetime('now');
    my $after = time;
    ok($now >= $before && $now <= $after, '"now" returns current time');

    # Date string: 2024-01-15 10:30:00
    my $expected = POSIX::mktime(0, 30, 10, 15, 0, 124, 0, 0, -1);
    is(Smokeping::parse_datetime('2024-01-15 10:30:00'), $expected, 'full datetime');

    # Date without time
    my $expected2 = POSIX::mktime(0, 0, 0, 15, 0, 124, 0, 0, -1);
    is(Smokeping::parse_datetime('2024-01-15'), $expected2, 'date only');

    # Date with hours and minutes but no seconds
    my $expected3 = POSIX::mktime(0, 30, 10, 15, 0, 124, 0, 0, -1);
    is(Smokeping::parse_datetime('2024-01-15 10:30'), $expected3, 'date with HH:MM');

    # Very large timestamp gets clamped to time()
    my $big = Smokeping::parse_datetime(2**32 + 1);
    ok(abs($big - time()) < 2, 'huge timestamp clamped to now');
};

# ──────────────────────────────────────────────────────────
# fill_template (with inline data)
# ──────────────────────────────────────────────────────────
subtest 'fill_template' => sub {
    my $tpl = 'Hello <##NAME##>, you have <##COUNT##> items.';
    my $result = Smokeping::fill_template(undef, { NAME => 'Alice', COUNT => '42' }, $tpl);
    is($result, 'Hello Alice, you have 42 items.', 'basic substitution');

    # Missing tag value defaults to empty string
    my $tpl2 = 'Value: <##MISSING##>';
    my $result2 = Smokeping::fill_template(undef, { MISSING => undef }, $tpl2);
    is($result2, 'Value: ', 'undef value replaced with empty string');

    # Multiple occurrences of same tag
    my $tpl3 = '<##X##> and <##X##>';
    my $result3 = Smokeping::fill_template(undef, { X => 'foo' }, $tpl3);
    is($result3, 'foo and foo', 'multiple occurrences replaced');

    # No matching tags leaves template unchanged
    my $tpl4 = 'No tags here';
    my $result4 = Smokeping::fill_template(undef, { NOPE => 'val' }, $tpl4);
    is($result4, 'No tags here', 'no matching tags');
};

# ──────────────────────────────────────────────────────────
# smokecol
# ──────────────────────────────────────────────────────────
subtest 'smokecol' => sub {
    # count <= 2 returns empty arrayref
    is_deeply(Smokeping::smokecol(0), [], 'smokecol(0) empty');
    is_deeply(Smokeping::smokecol(1), [], 'smokecol(1) empty');
    is_deeply(Smokeping::smokecol(2), [], 'smokecol(2) empty');

    # count = 4 should produce entries
    my $result = Smokeping::smokecol(4);
    ok(ref $result eq 'ARRAY', 'smokecol returns arrayref');
    ok(scalar @$result > 0, 'smokecol(4) has entries');

    # Each entry should be a string starting with CDEF, AREA, or STACK
    for my $item (@$result) {
        like($item, qr/^(CDEF|AREA|STACK):/, "entry format: $item");
    }

    # count = 20 should produce more entries
    my $result20 = Smokeping::smokecol(20);
    ok(scalar @$result20 > scalar @$result, 'more pings = more smoke entries');
};

# ──────────────────────────────────────────────────────────
# brighten_webcolor
# ──────────────────────────────────────────────────────────
subtest 'brighten_webcolor' => sub {
    # Result should be a valid hex color (with # prefix)
    my $bright = Smokeping::brighten_webcolor('000000');
    like($bright, qr/^#?[0-9a-f]{6}$/i, 'returns valid hex color');

    # Brightening black should produce something lighter
    unlike($bright, qr/^#?000000$/, 'black gets brightened');

    # Brightening white should stay white
    my $white = Smokeping::brighten_webcolor('ffffff');
    like($white, qr/^#?ffffff$/i, 'white stays white');

    # Brightening a color should produce valid hex
    my $red = Smokeping::brighten_webcolor('ff0000');
    like($red, qr/^#?[0-9a-f]{6}$/i, 'red returns valid hex');
};

# ──────────────────────────────────────────────────────────
# cgiurl
# ──────────────────────────────────────────────────────────
subtest 'cgiurl' => sub {
    my $q = Smokeping::Request->new('');
    local $ENV{SCRIPT_NAME} = '/cgi-bin/smokeping.cgi';

    my $cfg_abs = { General => { cgiurl => 'http://example.com/smokeping.cgi', linkstyle => 'absolute' } };
    is(Smokeping::cgiurl($q, $cfg_abs), 'http://example.com/smokeping.cgi', 'absolute linkstyle');

    my $cfg_rel = { General => { cgiurl => 'http://example.com/smokeping.cgi', linkstyle => 'relative' } };
    is(Smokeping::cgiurl($q, $cfg_rel), '', 'relative linkstyle');

    my $cfg_orig = { General => { cgiurl => 'http://example.com/smokeping.cgi', linkstyle => 'original' } };
    is(Smokeping::cgiurl($q, $cfg_orig), '/cgi-bin/smokeping.cgi', 'original linkstyle');

    my $cfg_bad = { General => { cgiurl => 'http://example.com/smokeping.cgi', linkstyle => 'bogus' } };
    eval { Smokeping::cgiurl($q, $cfg_bad) };
    like($@, qr/unknown value/, 'invalid linkstyle dies');
};

done_testing;
