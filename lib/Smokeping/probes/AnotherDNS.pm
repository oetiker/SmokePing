package Smokeping::probes::AnotherDNS;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::AnotherDNS>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::AnotherDNS>

to generate the POD document.

=cut

use strict;

# And now, an extra ugly hack
# Reason: Net::DNS does an eval("use Win32:Registry") to
# find out if it is running on Windows. This triggers the signal
# handler in the cgi mode. 

my $tmp = $SIG{__DIE__};
$SIG{__DIE__} = sub { };
eval("use Net::DNS;");
$SIG{__DIE__} = $tmp;

use base qw(Smokeping::probes::basefork);
use IPC::Open3;
use Symbol;
use Carp;
use Time::HiRes qw(sleep ualarm gettimeofday tv_interval);
use IO::Socket;
use IO::Select;

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
    $lookuphost = $target->{addr} unless defined $lookuphost;

    my $packet = Net::DNS::Packet->new( $lookuphost, $recordtype )->data;
    my $sock = IO::Socket::INET->new(
        "PeerAddr" => $host,
        "PeerPort" => $port,
        "Proto"    => "udp",
    );
    my $sel = IO::Select->new($sock);

    my @times;

    my $elapsed;
    for ( my $run = 0 ; $run < $self->pings($target) ; $run++ ) {
    	if (defined $elapsed) {
		my $timeleft = $mininterval - $elapsed;
		sleep $timeleft if $timeleft > 0;
	}
        my $t0 = [gettimeofday];
        $sock->send($packet);
        my ($ready) = $sel->can_read($timeout);
        my $t1 = [gettimeofday];
        $elapsed = tv_interval( $t0, $t1 );
        if ( defined $ready ) {
            push @times, $elapsed;
            my $buf = '';
            $ready->recv( $buf, &Net::DNS::PACKETSZ );
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
	});
}

1;

