package Smokeping::probes::EchoPingChargen;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::EchoPingChargen>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::EchoPingChargen>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::EchoPing);
use Carp;

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::EchoPingChargen - an echoping(1) probe for SmokePing
DOC
		overview => <<DOC,
Measures TCP chargen (port 19) roundtrip times for SmokePing.
DOC
		notes => <<DOC,
The I<udp> variable is not supported.
DOC
		authors => <<'DOC',
Niko Tyni <ntyni@iki.fi>
DOC
		see_also => <<DOC,
L<Smokeping::probes::EchoPing>
DOC
	}
}

sub proto_args {
	return ("-c");
}

sub ProbeDesc($) {
        return "TCP Chargen pings using echoping(1)";
}

sub targetvars {
	my $class = shift;
	my $h = $class->SUPER::targetvars;
	delete $h->{udp};
	return $h;
}

1;
