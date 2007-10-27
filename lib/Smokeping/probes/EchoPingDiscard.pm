package Smokeping::probes::EchoPingDiscard;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::EchoPingDiscard>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::EchoPingDiscard>

to generate the POD document.

=cut

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::EchoPingDiscard - an echoping(1) probe for SmokePing
DOC
		overview => <<DOC,
Measures TCP or UDP discard (port 9) roundtrip times for SmokePing.
DOC
		authors => <<'DOC',
Niko Tyni <ntyni@iki.fi>
DOC
		see_also => <<DOC,
L<Smokeping::probes::EchoPing>
DOC
	}
}

use strict;
use base qw(Smokeping::probes::EchoPing);
use Carp;

sub proto_args {
	my $self = shift;
	my $target = shift;
	my @args = $self->udp_arg;
	return ("-d", @args);
}

sub ProbeDesc($) {
	return "TCP or UDP Discard pings using echoping(1)";
}


1;
