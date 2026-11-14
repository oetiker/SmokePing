#!/usr/bin/env perl

# Slave authentication in Smokeping::Master: secret lookup, MAC
# comparison and the order of checks in answer_slave.

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use File::Temp ();

eval { require CGI; require Digest::HMAC_MD5; require Smokeping::Master; 1 }
    or plan skip_all => "Smokeping::Master does not load: $@";
Digest::HMAC_MD5->import('hmac_md5_hex');

my $tmp = File::Temp->newdir;
my $secrets = "$tmp/secrets";
open my $fh, '>', $secrets or die $!;
print $fh "boomer:boomersecret\n";
print $fh "a.b:dotsecret\n";
close $fh;

sub capture (&) {
    my $code = shift;
    my $buf = '';
    open my $out, '>', \$buf or die $!;
    my $old = select $out;
    $code->();
    select $old;
    close $out;
    return $buf;
}

# secure_eq
ok(Smokeping::Master::secure_eq('abc', 'abc'), 'secure_eq: equal strings');
ok(!Smokeping::Master::secure_eq('abc', 'abd'), 'secure_eq: different strings');
ok(!Smokeping::Master::secure_eq('abc', 'abcd'), 'secure_eq: different lengths');
ok(!Smokeping::Master::secure_eq(undef, 'abc'), 'secure_eq: undef first');
ok(!Smokeping::Master::secure_eq('abc', undef), 'secure_eq: undef second');
ok(Smokeping::Master::secure_eq('', ''), 'secure_eq: two empty strings');

# get_secret
my $cfg = { Slaves => { secrets => $secrets } };
is(Smokeping::Master::get_secret($cfg, 'boomer'), 'boomersecret', 'get_secret: known slave');
is(Smokeping::Master::get_secret($cfg, 'a.b'), 'dotsecret', 'get_secret: name with a dot');
is(Smokeping::Master::get_secret($cfg, 'a.'), undef, 'get_secret: prefix does not match');
is(Smokeping::Master::get_secret($cfg, 'boo.*'), undef, 'get_secret: regex metacharacters are literal');
is(Smokeping::Master::get_secret($cfg, '(?=b)\w+'), undef, 'get_secret: lookahead is literal');
is(Smokeping::Master::get_secret($cfg, 'nobody'), undef, 'get_secret: unknown slave');
is(Smokeping::Master::get_secret($cfg, ''), undef, 'get_secret: empty name');
is(Smokeping::Master::get_secret($cfg, undef), undef, 'get_secret: undef name');

my $missing = { Slaves => { secrets => "$tmp/does-not-exist" } };
my $ret;
my $out = capture { $ret = Smokeping::Master::get_secret($missing, 'boomer') };
is($ret, '__HORRIBLE_INLINE_SIGNALING__', 'get_secret: unreadable file signals the caller');
like($out, qr/WARNING: Opening secrets file/, 'get_secret: unreadable file is reported');

# answer_slave
my $datadir = "$tmp/data";
mkdir $datadir or die $!;
sub master_cfg {
    return {
        General  => { datadir => $datadir },
        Database => { step => 300, pings => 20 },
        Probes   => { FPing => {} },
        Targets  => {
            probe => 'FPing',
            World => { probe => 'FPing', host => 'example.org', slaves => 'boomer' },
        },
        Slaves   => {
            secrets => $secrets,
            boomer  => {},
            nosecret => {},
        },
        __last   => 1000,
        @_,
    };
}

sub answer {
    my ($cfg, %p) = @_;
    my $q = CGI->new({ protocol => 2, %p });
    return capture { Smokeping::Master::answer_slave($cfg, $q) };
}

my $data = "World\t900\tU:0:0.1";
my $key  = hmac_md5_hex($data, 'boomersecret');

$out = answer(master_cfg(Slaves => { secrets => "$tmp/does-not-exist" }),
    slave => 'stranger', data => $data, key => $key);
like($out, qr/I don't know the slave stranger/, 'unknown slave is rejected');
unlike($out, qr/Opening secrets file/, 'unknown slave is rejected before the secrets file is read');

$out = answer(master_cfg(), data => $data, key => $key);
like($out, qr/I don't know the slave  ignoring it/, 'missing slave parameter is rejected');

$out = answer(master_cfg(), slave => 'boo.*', data => $data, key => $key);
like($out, qr/I don't know the slave boo\.\*/, 'regex slave name is rejected as unknown');

$out = answer(master_cfg(), slave => 'nosecret', data => $data, key => $key);
like($out, qr/No secret found for slave nosecret/, 'configured slave without a secret');

$out = answer(master_cfg(Slaves => { secrets => "$tmp/does-not-exist", boomer => {} }),
    slave => 'boomer', data => $data, key => $key);
like($out, qr/Opening secrets file/, 'unreadable secrets file stops the answer');
unlike($out, qr/OK/, 'unreadable secrets file does not accept data');

$out = answer(master_cfg(), slave => 'boomer', protocol => 1, data => $data, key => $key);
like($out, qr/I expected protocol 2 and got 1/, 'protocol mismatch');

$out = answer(master_cfg(), slave => 'boomer', protocol => '', data => $data, key => $key);
like($out, qr/I expected protocol 2 and got \?/, 'missing protocol');

$out = answer(master_cfg(), slave => 'boomer', data => $data, key => 'f' x 32, config_time => 2000);
like($out, qr/does not match our expectation/, 'wrong key is rejected');
ok(!-e "$datadir/World.boomer.slave_cache", 'wrong key does not store data');

$out = answer(master_cfg(), slave => 'boomer', data => $data, key => $key, config_time => 2000);
like($out, qr/^Content-Type: text\/plain\n\nOK\n$/, 'valid key with current config answers OK');
ok(-e "$datadir/World.boomer.slave_cache", 'valid key stores data');

$out = answer(master_cfg(), slave => 'boomer', data => $data, key => $key, config_time => 1);
like($out, qr/^Content-Type: application\/smokeping-config\nProtocol: 2\nKey: [0-9a-f]{32}\n\n/,
    'valid key with stale config gets a signed config');
like($out, qr/example\.org/, 'pushed config contains the slave targets');

my $nt = master_cfg();
$nt->{Targets}{World}{slaves} = 'someoneelse';
$out = answer($nt, slave => 'boomer', data => $data, key => $key, config_time => 1);
like($out, qr/No targets found for slave 'boomer'/, 'slave without targets gets no config');

done_testing();
