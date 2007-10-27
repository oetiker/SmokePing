package Smokeping::probes::EchoPingSmtp;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::EchoPingSmtp>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::EchoPingSmtp>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::EchoPing);
use Carp;

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::EchoPingSmtp - an echoping(1) probe for SmokePing
DOC
		overview => <<DOC,
Measures SMTP roundtrip times (mail servers) for SmokePing.
DOC
		notes => <<DOC,
The I<fill>, I<size> and I<udp> EchoPing variables are not valid.
DOC
		authors => <<'DOC',
Niko Tyni <ntyni@iki.fi>
DOC
		see_also => <<DOC,
L<Smokeping::probes::EchoPing>
DOC
	}
}

sub _init {
	my $self = shift;
	# SMTP doesn't fit with filling or size
	my $arghashref = $self->features;
	delete $arghashref->{size};
	delete $arghashref->{fill};
}

sub proto_args {
	return ("-S");
}

sub ProbeDesc($) {
        return "SMTP pings using echoping(1)";
}

sub targetvars {
	my $class = shift;
	my $h = $class->SUPER::targetvars;
	delete $h->{udp};
	delete $h->{fill};
	delete $h->{size};
	return $h;
}

1;
