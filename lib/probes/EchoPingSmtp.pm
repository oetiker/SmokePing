package probes::EchoPingSmtp;

=head1 NAME

probes::EchoPingSmtp - an echoping(1) probe for SmokePing

=head1 OVERVIEW

Measures SMTP roundtrip times (mail servers) for SmokePing.

=head1 SYNOPSYS

 *** Probes ***
 + EchoPingSmtp

 binary = /usr/bin/echoping # mandatory

 *** Targets ***
 probe = EchoPingSmtp

=head1 DESCRIPTION

Supported probe-specific variables: those specified in EchoPing(3pm) 
documentation.

Supported target-specific variables: those specified in 
EchoPing(3pm) documentation except I<fill>, I<size> and I<udp>.

=head1 AUTHOR

Niko Tyni E<lt>ntyni@iki.fiE<gt>

=head1 SEE ALSO

EchoPing(3pm)

=cut

use strict;
use base qw(probes::EchoPing);
use Carp;

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

sub test_usage {
	my $self = shift;
	my $bin = $self->{properties}{binary};
	croak("Your echoping binary doesn't support SMTP")
		if `$bin -S 127.0.0.1 2>&1` =~ /(not compiled|invalid option|usage)/i;
	$self->SUPER::test_usage;
	return;
}

sub ProbeDesc($) {
        return "SMTP pings using echoping(1)";
}

1;
