package probes::EchoPingChargen;

=head1 NAME

probes::EchoPingChargen - an echoping(1) probe for SmokePing

=head1 OVERVIEW

Measures TCP chargen (port 19) roundtrip times for SmokePing.

=head1 SYNOPSYS

 *** Probes ***
 + EchoPingChargen

 binary = /usr/bin/echoping

 *** Targets ***

 probe = EchoPingChargen

=head1 DESCRIPTION

Supported probe- and target-specific variables: see probes::EchoPing(3pm)

Note: the I<udp> variable is not supported.

=head1 AUTHOR

Niko Tyni E<lt>ntyni@iki.fiE<gt>

=head1 SEE ALSO

probes::EchoPing(3pm)

=cut


use strict;
use base qw(probes::EchoPing);
use Carp;

sub proto_args {
	return ("-c");
}

sub test_usage {
	my $self = shift;
	my $bin = $self->{properties}{binary};
	croak("Your echoping binary doesn't support CHARGEN")
		if `$bin -c 2>&1 127.0.0.1` =~ /(usage|not compiled|invalid option)/i;
	$self->SUPER::test_usage;
	return;
}

sub ProbeDesc($) {
        return "TCP Chargen pings using echoping(1)";
}

1;
