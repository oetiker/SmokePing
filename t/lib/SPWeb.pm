package SPWeb;

# Load the shipped sample config (etc/config.dist.in) into a temporary
# tree and render CGI pages from it. Used by tests that exercise the web
# front end end to end: load_cfg creates the RRD files, so get_detail and
# display_webpage run against real (empty) data.

use strict;
use warnings;
use Exporter 'import';
use File::Temp ();
use File::Spec;
use File::Basename qw(dirname);

our @EXPORT_OK = qw(load_sample_cfg render);

my $tmpdir;    # kept alive for the life of the test process

sub load_sample_cfg {
    my %edit = @_;
    require Smokeping;
    my $repo = File::Spec->rel2abs(dirname(__FILE__) . "/../..");
    open my $in, '<', "$repo/etc/config.dist.in" or die "config.dist.in: $!";
    my $config = do { local $/; <$in> };
    close $in;

    $tmpdir = File::Temp->newdir;
    mkdir "$tmpdir/$_" or die "mkdir $tmpdir/$_: $!" for qw(cache data var);
    $config =~ s/\@prefix\@/$repo/g;
    $config =~ s/\@SENDMAIL\@/\/bin\/true/g;
    $config =~ s{^(imgcache\s*=\s*).*$}{$1$tmpdir/cache}m;
    $config =~ s{^(datadir\s*=\s*).*$}{$1$tmpdir/data}m;
    $config =~ s{^(piddir\s*=\s*).*$}{$1$tmpdir/var}m;

    # the parser refuses a secrets file that others can read
    my $secrets = "$tmpdir/secrets";
    open my $s, '>', $secrets or die $!;
    print $s "boomer:mysecret\nslave2:yoursecret\n";
    close $s;
    chmod 0600, $secrets or die $!;
    $config =~ s{^(secrets\s*=\s*).*$}{$1$secrets}m;

    $config = $edit{filter}->($config) if $edit{filter};

    my $cfgfile = "$tmpdir/smokeping.cfg";
    open my $out, '>', $cfgfile or die $!;
    print $out $config;
    close $out;

    # SERVER_SOFTWARE skips the probe binary checks. Load in daemon mode
    # so the RRD files get created, then switch to CGI mode for rendering.
    $ENV{SERVER_SOFTWARE} = "smokeping-test";
    $Smokeping::cgimode = 0;
    Smokeping::load_cfg($cfgfile);
    $Smokeping::cgimode = 1;
    return ($Smokeping::cfg, "$tmpdir");
}

# Run display_webpage and return what it printed.
sub render {
    my ($cfg, %param) = @_;
    require CGI;
    my $q = CGI->new({%param});
    my $buf = '';
    open my $fh, '>', \$buf or die $!;
    my $old = select $fh;
    my $ok = eval { Smokeping::display_webpage($cfg, $q); 1 };
    my $err = $@;
    select $old;
    close $fh;
    die $err unless $ok;
    return $buf;
}

1;
