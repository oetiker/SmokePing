#!/usr/bin/env perl

# Limits on request input to the web front end: menu filter patterns,
# target paths, and the secrets handed out for DYNAMIC hosts.

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

eval { require RRDs; require Config::Grammar; require Smokeping; 1 }
    or plan skip_all => "Smokeping web front end does not load: $@";

use SPWeb qw(load_sample_cfg render);

# filter_regex
{
    my $re_cfg  = { Presentation => {} };
    my $lit_cfg = { Presentation => { literalsearch => 'yes' } };
    my $f = \&Smokeping::filter_regex;

    like('James', $f->($re_cfg, 'jam.s'), 'regex filter matches as a regex');
    unlike('James', $f->($lit_cfg, 'jam.s'), 'literalsearch matches literally');
    like('jam.s', $f->($lit_cfg, 'jam.s'), 'literalsearch finds the literal text');
    like('James', $f->($re_cfg, 'J(.*)(.*)(.*)s'), 'three quantifiers stay a regex');
    unlike('James', $f->($re_cfg, 'J(.*)(.*)(.*)(.*)s'), 'four quantifiers fall back to literal');
    like('J(.*)(.*)(.*)(.*)s', $f->($re_cfg, 'J(.*)(.*)(.*)(.*)s'), 'literal fallback still finds the text');
    unlike('James', $f->($re_cfg, 'J' . ('.' x 64)), 'long filter falls back to literal');
    like('James', $f->($re_cfg, 'J' . ('.?' x 0) . 'ames'), 'short filter is unaffected');
    my $bad = eval { $f->($re_cfg, 'Jam(') };
    ok($bad, 'invalid regex does not die');
    like('Jam(', $bad, 'invalid regex is matched literally');
}

my ($cfg, $tmp) = load_sample_cfg();

# menu filter through the page
{
    my $out = render($cfg, filter => 'jam.s');
    like($out, qr{target=Test\.James"}, 'regex filter finds the target');
    $out = render($cfg, filter => 'Jam(');
    unlike($out, qr{target=Test\.James"}, 'invalid regex filter renders without matches');
}

# target paths
{
    my $out = render($cfg, target => 'Test.James');
    like($out, qr{<h2>Last 3 Hours from }, 'existing target renders');

    for my $t ('Test.James.host', 'Test.James.host.a.b', 'Test.Nobody', 'Test.James.probe') {
        my $ok = eval { render($cfg, target => $t); 1 };
        ok(!$ok, "target $t is rejected");
        like($@, qr/does not exist/, "target $t reports a missing section");
    }
    ok(!-e "$tmp/cache/Test/James/host", 'rejected target creates no cache directory');
}

# random_secret
{
    my $a = Smokeping::random_secret();
    my $b = Smokeping::random_secret();
    like($a, qr/^[0-9a-f]{32}$/, 'secret is 128 bits of hex');
    isnt($a, $b, 'secrets differ');

    local $Smokeping::random_source = "$tmp/no-such-device";
    like(Smokeping::random_secret(), qr/^[0-9a-f]{32}$/, 'fallback secret has the same form');

    open my $short, '>', "$tmp/short" or die $!;
    print $short "abc";
    close $short;
    local $Smokeping::random_source = "$tmp/short";
    like(Smokeping::random_secret(), qr/^[0-9a-f]{32}$/, 'short read uses the fallback');

    # a directory opens but cannot be read
    local $Smokeping::random_source = $tmp;
    like(Smokeping::random_secret(), qr/^[0-9a-f]{32}$/, 'read error uses the fallback');
}

# DYNAMIC host: secret mailed by enable_dynamic is accepted by update_dynaddr
{
    $Smokeping::cfg = undef;
    my ($dcfg, $dtmp) = load_sample_cfg(filter => sub {
        my $c = shift;
        $c =~ s/^host = james\.address$/host = DYNAMIC\nemail = James <james\@example.org>/m;
        $c });

    my @mail;
    no warnings qw(redefine once);
    local *Smokeping::sendmail = sub ($$$) { push @mail, [@_] };
    local *Smokeping::snmpget_ident = sub ($) { return undef };
    use warnings qw(redefine once);

    {
        local *STDERR;
        open STDERR, '>', \my $err;
        Smokeping::enable_dynamic($dcfg, $dcfg->{Targets}, '', '');
    }
    is(scalar @mail, 1, 'enable_dynamic sends one mail');
    is($mail[0][1], 'James <james@example.org>', 'mail goes to the host owner');
    my ($secret) = $mail[0][2] =~ /my \$secret = '([^']*)'/;
    like($secret, qr/^[0-9a-f]{32}$/, 'mailed secret is 128 bits of hex');

    # reload the rewritten config, as the CGI would
    my $cfgfile = $dcfg->{__cfgfile};
    $Smokeping::cfg = undef;
    Smokeping::load_cfg($cfgfile, 1);
    my $ncfg = $Smokeping::cfg;
    like($ncfg->{Targets}{Test}{James}{host}, qr{^DYNAMIC/}, 'config now holds the secret hash');

    local $ENV{REMOTE_ADDR} = '192.0.2.7';
    my $ret = Smokeping::update_dynaddr($ncfg, CGI->new({ target => 'Test.James', secret => 'wrong' }));
    like($ret, qr/Invalid target or secret/, 'wrong secret is rejected');
    $ret = Smokeping::update_dynaddr($ncfg, CGI->new({ target => 'Test.James', secret => $secret }));
    ok(!$ret, 'mailed secret is accepted');
    my $adr = Smokeping::dyndir($ncfg) . '/Test/James.adr';
    open my $fh, '<', $adr or die "$adr: $!";
    is(scalar <$fh>, "192.0.2.7\n", 'address is recorded');
}

done_testing();
