package probes::EchoPingIcp;

=head1 NAME

probes::EchoPingIcp - an echoping(1) probe for SmokePing

=head1 OVERVIEW

Measures ICP (Internet Cache Protocol, spoken by web caches)
roundtrip times for SmokePing.

=head1 SYNOPSYS

 *** Probes ***
 + EchoPingIcp

 binary = /usr/bin/echoping # mandatory
 
 *** Targets ***

 probe = EchoPingHttp

 + PROBE_CONF
 # this can be overridden in the targets' PROBE_CONF sections
 url = / 


=head1 DESCRIPTION

Supported probe-specific variables: those specified in EchoPing(3pm) 
documentation.

Supported target-specific variables:

=over

=item those specified in EchoPing(3pm) documentation 

except I<fill>, I<size> and I<udp>.

=item url

The URL to be requested from the web cache. 

=back

=head1 AUTHOR

Niko Tyni E<lt>ntyni@iki.fiE<gt>

=head1 SEE ALSO

EchoPing(3pm), EchoPingHttp(3pm)

=cut

use strict;
use base qw(probes::EchoPing);
use Carp;

sub _init {
	my $self = shift;
	# Icp doesn't fit with filling or size
	my $arghashref = $self->features;
	delete $arghashref->{size};
	delete $arghashref->{fill};
}

sub proto_args {
	my $self = shift;
	my $target = shift;
	my $url = $target->{vars}{url};
	$url = $self->{properties}{url} unless defined $url;
	$url = "/" unless defined $url;

	my @args = ("-i", $url);

	return @args;
}

sub test_usage {
	my $self = shift;
	my $bin = $self->{properties}{binary};
	croak("Your echoping binary doesn't support ICP")
		if `$bin -i/ 127.0.0.1 2>&1` =~ /not compiled|usage/i;
	$self->SUPER::test_usage;
	return;
}

sub ProbeDesc($) {
        return "ICP pings using echoping(1)";
}

1;
