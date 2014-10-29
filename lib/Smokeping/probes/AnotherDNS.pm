package Smokeping::probes::AnotherDNS;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::AnotherDNS>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::AnotherDNS>

to generate the POD document.

=cut

use strict;

use base qw(Smokeping::probes::basefork);
use IPC::Open3;
use Symbol;
use Carp;
use Time::HiRes qw(sleep ualarm gettimeofday tv_interval);
use IO::Socket;
use IO::Select;
use Net::DNS;

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::AnotherDNS - Alternate DNS Probe
DOC
		description => <<DOC,
Like DNS, but uses Net::DNS and Time::HiRes instead of dig. This probe does
*not* retry the request three times before it is considerd "lost", like dig and
other resolver do by default. If operating as caching Nameserver, BIND (and
maybe others) expect clients to retry the request if the answer is not in the
cache. So, ask the nameserver for something that he is authoritative for if you
want measure the network packet loss correctly. 

If you have a really fast network and nameserver, you will notice that this
probe reports the query time in microsecond resolution. :-)
DOC
		authors => <<'DOC',
Christoph Heine <Christoph.Heine@HaDiKo.DE>
DOC
	}
}

sub new($$$) {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new(@_);
    return $self;
}

sub ProbeDesc($) {
    my $self = shift;
    return "DNS requests";
}

sub pingone ($) {
    my $self   = shift;
    my $target = shift;

    my $host       = $target->{addr};
    my $lookuphost = $target->{vars}{lookup};
    my $mininterval = $target->{vars}{mininterval};
    my $recordtype = $target->{vars}{recordtype};
    my $timeout = $target->{vars}{timeout};
    my $port = $target->{vars}{port};
    my $ipversion = $target->{ipversion} || 4;
    my $protocol = $target->{protcol} || "udp";
    my $require_noerror = $target->{vars}{require_noerror};
    $lookuphost = $target->{addr} unless defined $lookuphost;

    my $packet = Net::DNS::Packet->new( $lookuphost, $recordtype )->data;
    my $sock = 0;
    
    if ($ipversion == 6) {
        $sock = IO::Socket::INET6->new(
            "PeerAddr" => $host,
            "PeerPort" => $port,
            "Proto"    => $protocol,
        );
    } else {
        $sock = IO::Socket::INET->new(
            "PeerAddr" => $host,
            "PeerPort" => $port,
            "Proto"    => $protocol,
        );
    }

    my $sel = IO::Select->new($sock);

    my @times;

    my $elapsed;
    for ( my $run = 0 ; $run < $self->pings($target) ; $run++ ) {
    	if (defined $elapsed) {
		my $timeleft = $mininterval - $elapsed;
		sleep $timeleft if $timeleft > 0;
	}
        my $t0 = [gettimeofday()];
        $sock->send($packet);
        my ($ready) = $sel->can_read($timeout);
        my $t1 = [gettimeofday()];
        $elapsed = tv_interval( $t0, $t1 );
        if ( defined $ready ) {
            my $buf = '';
            $ready->recv( $buf, 512 );
	    my ($recvPacket, $err) = Net::DNS::Packet->new(\$buf);
	    if (defined $recvPacket) {
		my $recvHeader = $recvPacket->header();
		next if $recvHeader->ancount() < $target->{vars}{require_answers};
	    	if (not $require_noerror) {
		    push @times, $elapsed;
		} else {
		    # Check the Response Code for the NOERROR.
		    if ($recvHeader->rcode() eq "NOERROR") {
		         push @times, $elapsed;
		    }
		}
	    }
        }
    }
    @times =
      map { sprintf "%.10e", $_ } sort { $a <=> $b } grep { $_ ne "-" } @times;

    return @times;
}

sub probevars {
	my $class = shift;
	my $h = $class->SUPER::probevars;
	delete $h->{timeout};
	return $h;
}

sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		lookup => {
			_doc => <<DOC,
Name of the host to look up in the dns.
DOC
			_example => 'www.example.org',
		},
		mininterval => {
			_doc => <<DOC,
Minimum time between sending two lookup queries in (possibly fractional) seconds.
DOC
			_default => .5,
			_re => '(\d*\.)?\d+',
		},
		require_noerror => {
			_doc => 'Only Count Answers with Response Status NOERROR.',
			_default => 0,
		},
		require_answers => {
			_doc => 'Only Count Answers with answer count >= this value.',
			_default => 0,
		},
		recordtype => {
			_doc => 'Record type to look up.',
			_default => 'A',
		},
		timeout => {
			_doc => 'Timeout for a single request in seconds.',
			_default => 5,
			_re => '\d+',
		},
		port => {
			_doc => 'The UDP Port to use.',
			_default => 53,
			_re => '\d+',
		},
                protocol => {
                        _doc => 'The Network Protocol to use.',
                        _default => 'udp',
                },
                ipversion => {
                        _doc => <<DOC,
The IP protocol used. Possible values are "4" and "6". 
Passed to echoping(1) as the "-4" or "-6" options.
DOC
                        _example => 4,
                        _re => '[46]'
                },
	});
}

1;

