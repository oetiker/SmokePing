#!/usr/bin/env perl

# Parse the shipped sample config (etc/config.dist.in) through SmokePing's
# real grammar. Catches regressions that break the parser or change the
# shape of the top-level config tree.
#
# The config has @prefix@ / @SENDMAIL@ autoconf substitutions that we
# resolve to in-tree paths so the test runs in a fresh checkout. Some
# probes' validators check that referenced binaries exist (FPing checks
# its 'binary' setting); SmokePing exposes $ENV{SERVER_SOFTWARE} as the
# documented CGI-mode bypass for that, so we set it.

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use File::Temp ();
use File::Spec;

eval { require Smokeping; 1 }
    or plan skip_all => "Smokeping core does not load: $@";

my $repo = File::Spec->rel2abs("$FindBin::Bin/..");
my $src  = "$repo/etc/config.dist.in";

open(my $in, '<', $src) or BAIL_OUT("cannot read $src: $!");
my $config = do { local $/; <$in> };
close $in;

# autoconf substitutions. @SENDMAIL@ is resolved from $PATH because
# sendmail's path varies across distros; the parser doesn't validate
# it today, and /bin/true is a safe no-op fallback if sendmail is absent.
chomp(my $sendmail = qx{command -v sendmail 2>/dev/null});
$sendmail ||= '/bin/true';
$config =~ s/\@prefix\@/$repo/g;
$config =~ s/\@SENDMAIL\@/$sendmail/g;

# Directories the parser will resolve but not necessarily require to be
# pre-populated. Create them under a tempdir to keep the source tree
# untouched, and rewrite the relevant config keys to point there.
my $tmpdir = File::Temp->newdir;
for my $sub (qw(cache data var)) {
    mkdir "$tmpdir/$sub" or BAIL_OUT("mkdir $tmpdir/$sub: $!");
}
$config =~ s{^(imgcache\s*=\s*).*$}{$1$tmpdir/cache}m;
$config =~ s{^(datadir\s*=\s*).*$}{$1$tmpdir/data}m;
$config =~ s{^(piddir\s*=\s*).*$}{$1$tmpdir/var}m;

# Slaves' secrets file must be mode 0600 (parser refuses world-readable).
# Copy the in-tree dist file to the tempdir and tighten perms.
my $secrets = "$tmpdir/smokeping_secrets";
open(my $sin,  '<', "$repo/etc/smokeping_secrets.dist") or BAIL_OUT($!);
open(my $sout, '>', $secrets) or BAIL_OUT($!);
print $sout do { local $/; <$sin> };
close $sout;
close $sin;
chmod 0600, $secrets or BAIL_OUT("chmod $secrets: $!");
$config =~ s{^(secrets\s*=\s*).*$}{$1$secrets}m;

my ($fh, $cfgfile) = File::Temp::tempfile('smokeping-test-XXXXXX',
    SUFFIX => '.cfg', UNLINK => 1, TMPDIR => 1);
print $fh $config;
close $fh;

# Bypass the "binary must exist" validators in probes that wrap external
# tools. This is the same escape hatch SmokePing uses in CGI mode.
local $ENV{SERVER_SOFTWARE} = 'smokeping-test';

my $parser = Smokeping::get_parser();
ok($parser, 'Smokeping::get_parser returned a parser')
    or BAIL_OUT("no parser, cannot continue");

my $cfg = $parser->parse($cfgfile);
ok($cfg, 'sample config parses without error')
    or diag("parser error: " . ($parser->{err} // '(unknown)'));

if ($cfg) {
    for my $section (qw(General Database Presentation Probes Targets Alerts Slaves)) {
        ok(exists $cfg->{$section}, "parsed config has '$section' section");
    }
    # Round-trip checks: the parser produced non-empty values for
    # representative scalar keys. We avoid asserting specific strings so
    # an editorial change to etc/config.dist.in does not break the test.
    like($cfg->{General}{owner}, qr/\S/,
        "General/owner has a value");
    like($cfg->{Probes}{FPing}{binary}, qr/\S/,
        "Probes/FPing/binary has a value");
}

done_testing();
