package probes::EchoPingDiscard;

=head1 NAME

probes::EchoPingDiscard - an echoping(1) probe for SmokePing

=head1 OVERVIEW

Measures TCP or UDP discard (port 9) roundtrip times for SmokePing.

=head1 SYNOPSYS

 *** Probes ***
 + EchoPingDiscard

 binary = /usr/bin/echoping

 *** Targets ***

 probe = EchoPingDiscard

=head1 DESCRIPTION

Supported probe- and target-specific variables: see probes::EchoPing(3pm)

=head1 AUTHOR

Niko Tyni E<lt>ntyni@iki.fiE<gt>

=head1 SEE ALSO

probes::EchoPing(3pm)

=cut

use strict;
use base qw(probes::EchoPing);
use Carp;

sub proto_args {
	my $self = shift;
	my $target = shift;
	my @args = $self->udp_arg;
	return ("-d", @args);
}

sub test_usage {
	my $self = shift;
	my $bin = $self->{properties}{binary};
	croak("Your echoping binary doesn't support DISCARD")
		if `$bin -d 127.0.0.1 2>&1` =~ /(not compiled|invalid option|usage)/i;
	$self->SUPER::test_usage;
	return;
}

sub ProbeDesc($) {
	return "TCP or UDP Discard pings using echoping(1)";
}


1;
