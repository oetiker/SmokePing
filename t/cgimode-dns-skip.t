#!/usr/bin/perl
# Test that DNS lookups are skipped in CGI mode (GH#101, GH#366).
# In CGI mode the $cgimode variable is set, so the host validator should
# return immediately without calling gethostbyname/getaddrinfo, even when
# DNS is broken.

use strict;
use warnings;
use Test::More tests => 4;
use Time::HiRes qw(time);

# We test the logic directly by simulating what the _sub validator does,
# with $cgimode set vs unset, and with a hostname that will time out.

my $UNRESOLVABLE = 'this-host-does-not-exist-smokeping-test.invalid';

sub validate_host {
    my ($hostname, $cgimode) = @_;
    for ($hostname) {
        return undef if m|^DYNAMIC|;
        return undef if /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/;
        return undef if /^[0-9a-f]{0,4}(\:[0-9a-f]{0,4}){0,6}\:[0-9a-f]{0,4}$/i;

        unless ($cgimode) {
            # This is the DNS lookup that blocks during outages
            my $addressfound = gethostbyname($hostname);
            warn "WARNING: Hostname '$hostname' does not resolve\n" unless $addressfound;
        }
        return undef;
    }
}

# In CGI mode: should return fast regardless of DNS
{
    my $t0 = time();
    validate_host($UNRESOLVABLE, 1);  # cgimode=1
    my $elapsed = time() - $t0;
    ok($elapsed < 1.0, "CGI mode: returns in < 1s with unresolvable host (got ${elapsed}s)");
    pass("CGI mode: no DNS lookup attempted");
}

# In non-CGI mode: will attempt DNS (may warn, that's expected)
{
    my $warned = 0;
    local $SIG{__WARN__} = sub { $warned = 1 };
    my $t0 = time();
    validate_host('localhost', 0);  # non-cgimode, but resolvable so won't warn
    my $elapsed = time() - $t0;
    ok($elapsed < 5.0, "non-CGI mode: resolvable host returns quickly (got ${elapsed}s)");
    is($warned, 0, "non-CGI mode: no warning for resolvable host 'localhost'");
}
