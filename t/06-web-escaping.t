#!/usr/bin/env perl

# Request values and RRD errors must be HTML-escaped when the CGI writes
# them into a page.

use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

eval { require RRDs; require Config::Grammar; require Smokeping; 1 }
    or plan skip_all => "Smokeping web front end does not load: $@";

use SPWeb qw(load_sample_cfg render);

# An invalid graph colour makes the main RRDs::graph call fail. The
# earlier range checks do not use it, so this reaches the error branch.
sub with_bad_color {
    my ($cfg, $code) = @_;
    local $cfg->{Presentation}{colortext} = 'nothex';
    return $code->();
}

my $markup = '<b>XT</b>';
my $escaped = '&lt;b&gt;XT&lt;/b&gt;';

{
    my ($cfg) = load_sample_cfg();

    my $out = render($cfg, target => 'Test.James', displaymode => 'n',
        title => $markup, start => 'end-3h', end => 'now');
    like($out, qr{<h2>\Q$escaped\E</h2>}, 'navigator title is escaped');
    unlike($out, qr{\Q$markup\E}, 'navigator title markup is not emitted');

    $out = render($cfg, target => 'Test.James', displaymode => 'n', start => 'end-3h', end => 'now');
    like($out, qr{<h2>Navigator Graph</h2>}, 'navigator default title still renders');

    $out = render($cfg, target => 'Test.MultiHost "onx=1', displaymode => 's');
    like($out, qr{href="\?displaymode=n&start=[^"]*&end=now&target=Test\.MultiHost">},
        'multi-host link uses the resolved target');
    unlike($out, qr{onx=1}, 'multi-host link drops extra request text');

    $out = with_bad_color($cfg, sub {
        render($cfg, target => 'Test.MultiHost', displaymode => 'n', start => 'end-3h', end => 'now') });
    like($out, qr{<div>ERROR: [^<]+</div><div>[^<]+__navcache}, 'multi-host RRD error is reported');

    local $ENV{REMOTE_USER} = '<u>who</u>';
    $out = render($cfg, target => 'Test.James');
    like($out, qr{&lt;u&gt;who&lt;/u&gt;}, 'REMOTE_USER is escaped');
    unlike($out, qr{<u>who</u>}, 'REMOTE_USER markup is not emitted');

    delete $ENV{REMOTE_USER};
    $out = render($cfg, target => 'Test.James');
    like($out, qr{Guest}, 'anonymous user is shown as Guest');
}

{
    # With htmltitle off the title goes into the RRD arguments instead,
    # and those are echoed when RRDtool fails.
    $Smokeping::cfg = undef;
    my ($cfg) = load_sample_cfg(filter => sub {
        my $c = shift; $c =~ s/^htmltitle = yes$/htmltitle = no/m; $c });
    my $out = with_bad_color($cfg, sub {
        render($cfg, target => 'Test.James', displaymode => 'n',
            title => $markup, start => 'end-3h', end => 'now') });
    like($out, qr{<div>ERROR: [^<]+</div>}, 'navigator RRD error is reported');
    like($out, qr{<br/>\Q$escaped\E from }, 'RRD arguments in the error are escaped');
    unlike($out, qr{\Q$markup\E}, 'RRD arguments markup is not emitted');
}

done_testing();
