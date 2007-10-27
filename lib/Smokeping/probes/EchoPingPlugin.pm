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

Plugins are available starting with echoping version 6.
DOC
		see_also => <<DOC,
L<Smokeping::probes::EchoPing>,
L<Smokeping::probes::EchoPingLDAP>,
L<Smokeping::probes::EchoPingDNS>,
L<Smokeping::probes::EchoPingWhois>
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

sub post_args {
    my $self = shift;
    my $target = shift;
    return $self->plugin_args($target);
}

# derived classes should override this
sub plugin_args {
    my $self = shift;
    my $target = shift;
    return ();
}

sub proto_args {
	my $self = shift;
	my $target = shift;
	my $plugin = $target->{vars}{plugin};
	return ("-m", $plugin);
}

sub ProbeDesc($) {
	return "Pings using an echoping(1) plugin";
}

sub targetvars {
	my $class = shift;
	my $h = $class->SUPER::targetvars;
	delete $h->{udp};
	delete $h->{fill};
	delete $h->{size};
    return $class->_makevars($h, {
        _mandatory => [ 'plugin' ],
        plugin => {
            _doc => <<DOC,
The echoping plugin that will be used. See echoping(1) for details.
This can either be the name of the plugin or a full path to the
plugin shared object.
DOC
            _example => "random",
        },
        pluginargs => {
            _doc => <<DOC,
Any extra arguments needed by the echoping plugin specified with the 
I<pluginname> variable. These are generally provided by the subclass probe.
DOC
            _example => "-p plugin_specific_arg",
        },
    },
    );
}

1;
