package probes::EchoPingHttps;

=head1 NAME

probes::EchoPingHttps - an echoping(1) probe for SmokePing

=head1 OVERVIEW

Measures HTTPS (HTTP over SSL) roundtrip times (web servers and caches) for
SmokePing.

=head1 SYNOPSYS

 *** Probes ***
 + EchoPingHttps

 binary = /usr/bin/echoping # mandatory

 *** Targets ***

 probe = EchoPingHttps

 + PROBE_CONF
 url = / 
 ignore-cache = yes
 force-revalidate = no
 port = 443 # default value anyway

=head1 DESCRIPTION

As EchoPingHttp(3pm), but SSL-enabled.

=head1 AUTHOR

Niko Tyni E<lt>ntyni@iki.fiE<gt>

=head1 SEE ALSO

EchoPingHttp(3pm)

=cut

use strict;
use base qw(probes::EchoPingHttp);
use Carp;

sub proto_args {
	my $self = shift;
	my $target = shift;
	my @args = $self->SUPER::proto_args($target);
	return ("-C", @args);
}

sub test_usage {
	my $self = shift;

	my $bin = $self->{properties}{binary};
	my $response  = `$bin -C -h/ 127.0.0.1 2>&1`;
	croak("Your echoping binary doesn't support SSL")
		if ($response =~ /(not compiled|invalid option|usage)/i);
	$self->SUPER::test_usage;
	return;
}

sub ProbeDesc($) {
        return "HTTPS pings using echoping(1)";
}


1;
