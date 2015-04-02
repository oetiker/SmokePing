package Smokeping::probes::EchoPingHttps;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::EchoPingHttps>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::EchoPingHttps>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::EchoPingHttp);
use Carp;

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::EchoPingHttps - an echoping(1) probe for SmokePing
DOC
		overview => <<DOC,
Measures HTTPS (HTTP over SSL) roundtrip times (web servers and caches) for
SmokePing.
DOC
		description => <<DOC,
As EchoPingHttp(3pm), but SSL-enabled.
DOC
notes => <<DOC,
You should consider setting a lower value for the C<pings> variable than the
default 20, as repetitive URL fetching may be quite heavy on the server.
DOC
		authors => <<'DOC',
Niko Tyni <ntyni@iki.fi>
DOC
		see_also => <<DOC,
L<Smokeping::probes::EchoPingHttp>
DOC
	}
}

sub proto_args {
	my $self = shift;
	my $target = shift;
	my @args = $self->SUPER::proto_args($target);
	return ("-C", @args);
}

sub ProbeDesc($) {
        return "HTTPS pings using echoping(1)";
}


sub targetvars {
    my $class = shift;
    my $h = $class->SUPER::targetvars;
    $h->{prot}{_example} = 3443;
    $h->{prot}{_default} = 443;
    return $h;
}

1;
