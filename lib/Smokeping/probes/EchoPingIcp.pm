package Smokeping::probes::EchoPingIcp;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::EchoPingIcp>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::EchoPingIcp>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::EchoPing);
use Carp;

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::EchoPingIcp - an echoping(1) probe for SmokePing
DOC
		overview => <<DOC,
Measures ICP (Internet Cache Protocol, spoken by web caches)
roundtrip times for SmokePing.
DOC
		notes => <<DOC,
The I<fill>, I<size> and I<udp> EchoPing variables are not valid.
DOC
		authors => <<'DOC',
Niko Tyni <ntyni@iki.fi>
DOC
		see_also => <<DOC,
L<Smokeping::probes::EchoPing>, L<Smokeping::probes::EchoPingHttp>
DOC
	}
}

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

	my @args = ("-i", $url);

	return @args;
}

sub test_usage {
	my $self = shift;
	my $bin = $self->{properties}{binary};
	croak("Your echoping binary doesn't support ICP")
		if `$bin -t1 -i/ 127.0.0.1 2>&1` =~ /not compiled|usage/i;
	$self->SUPER::test_usage;
	return;
}

sub ProbeDesc($) {
        return "ICP pings using echoping(1)";
}

sub targetvars {
	my $class = shift;
	my $h = $class->SUPER::targetvars;
	delete $h->{udp};
	delete $h->{fill};
	delete $h->{size};
	return $class->_makevars($h, {
		_mandatory => [ 'url' ],
		url => {
			_doc => "The URL to be requested from the web cache.",
			_example => 'http://www.example.org/',
		},
	});
}

1;
