package Smokeping::probes::EchoPingDNS;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::EchoPingDNS>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::EchoPingDNS>

to generate the POD document.

=cut

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::EchoPingDNS - an echoping(1) probe for SmokePing
DOC
		overview => <<DOC,
Measures DNS roundtrip times for SmokePing with the echoping_dns plugin. 
DOC
		authors => <<'DOC',
Niko Tyni <ntyni@iki.fi>
DOC
        notes => <<'DOC',
The I<fill>, I<size> and I<udp> EchoPing variables are not valid.

Plugins, including echoping_dns, are available starting with echoping version 6.
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
    my @args = ("-t", $target->{vars}{dns_type});
    my $tcp = $target->{vars}{dns_tcp};
    if ($tcp and $tcp ne "no") {
        push @args, "--tcp";
    }
    push @args, $target->{vars}{dns_request};
    return @args;
}

sub ProbeDesc($) {
	return "DNS pings using the echoping_dns plugin";
}

sub targetvars {
	my $class = shift;
	my $h = $class->SUPER::targetvars;
	delete $h->{udp};
	delete $h->{fill};
	delete $h->{size};
    $h->{_mandatory} = [ grep { $_ ne "plugin" } @{$h->{_mandatory}}];
    $h->{plugin}{_default} = 'dns';
    $h->{plugin}{_example} = '/path/to/dns.so';
    return $class->_makevars($h, {
        _mandatory => [ 'dns_request' ],
        dns_request => {
            _doc => <<DOC,
The DNS request (domain name) to be queried.
DOC
            _example => 'example.org',
        },
        dns_type => {
            _doc => <<DOC,
The echoping_dns '-t' option: type of data requested (NS, A, SOA etc.) 
DOC
            _example => 'AAAA',
            _default => 'A',
        },
        dns_tcp => {
            _doc => <<DOC,
The echoping_dns '--tcp' option: use only TCP ('virtual circuit').
Enabled if specified with a value other than 'no' or '0'.
DOC
            _example => 'yes',
        },
    },
    );
}

1;
