package Smokeping::probes::EchoPingPlugin;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::EchoPingPlugin>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::EchoPingPlugin>

to generate the POD document.

=cut

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::EchoPingPlugin - a basis for using echoping(1) plugins as probes for SmokePing
DOC
		overview => <<DOC,
Measures roundtrip times for SmokePing with an echoping(1) plugin. The plugins
currently shipped with echoping are implemented as separate probes based
on this class, but the class can also be used directly.
DOC
		authors => <<'DOC',
Niko Tyni <ntyni@iki.fi>
DOC
        notes => <<'DOC',
The I<fill>, I<size> and I<udp> EchoPing variables are not valid by default for EchoPingPlugin -derived probes.
DOC
		see_also => <<DOC,
L<Smokeping::probes::EchoPing>
DOC
	}
}

use strict;
use base qw(Smokeping::probes::EchoPing);
use Carp;

sub _init {
    my $self = shift;
    # plugins don't generally fit with filling, size or udp.
    my $arghashref = $self->features;
    delete $arghashref->{size};
    delete $arghashref->{fill};
    delete $arghashref->{udp};
}


sub proto_args {
	my $self = shift;
	my $target = shift;
	my $plugin = $target->{vars}{plugin};
	return ("-m", $plugin);
}

sub test_usage {
	my $self = shift;
	my $bin = $self->{properties}{binary};
    # side effect: this sleeps for a random time between 0 and 1 seconds
    # is there anything smarter to do?
	croak("Your echoping binary doesn't support plugins")
		if `$bin -m random 127.0.0.1 2>&1` =~ /(not compiled|invalid option|usage)/i;
	$self->SUPER::test_usage;
	return;
}

sub ProbeDesc($) {
	return "Pings using an echoping(1) plugin";
}


1;
