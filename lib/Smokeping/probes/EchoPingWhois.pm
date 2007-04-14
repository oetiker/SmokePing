package Smokeping::probes::EchoPingWhois;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::EchoPingWhois>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::EchoPingWhois>

to generate the POD document.

=cut

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::EchoPingWhois - an echoping(1) probe for SmokePing
DOC
		overview => <<DOC,
Measures whois roundtrip times for SmokePing with the echoping_whois plugin. 
DOC
		authors => <<'DOC',
Niko Tyni <ntyni@iki.fi>
DOC
        notes => <<'DOC',
The I<fill>, I<size> and I<udp> EchoPing variables are not valid.

Plugins, including echoping_whois, are available starting with echoping version 6.
DOC
		see_also => <<DOC,
L<Smokeping::probes::EchoPing>, 
L<Smokeping::probes::EchoPingPlugin>
DOC
	}
}

use strict;
use base qw(Smokeping::probes::EchoPingPlugin);
use Carp;

sub plugin_args {
    my $self = shift;
    my $target = shift;
    my @args;
    push @args, $target->{vars}{whois_request};

    return @args;
}

sub ProbeDesc($) {
	return "whois pings using the echoping_whois plugin";
}

sub targetvars {
	my $class = shift;
	my $h = $class->SUPER::targetvars;
	delete $h->{udp};
	delete $h->{fill};
	delete $h->{size};
    $h->{_mandatory} = [ grep { $_ ne "plugin" } @{$h->{_mandatory}}];
    $h->{plugin}{_default} = 'whois';
    $h->{plugin}{_example} = '/path/to/whois.so';
    return $class->_makevars($h, {
        _mandatory => [ 'whois_request' ],
        whois_request => {
            _doc => <<DOC,
The request to the whois server (typically a domain name).
DOC
            _example => 'example.org',
        },
    },
    );
}

1;
