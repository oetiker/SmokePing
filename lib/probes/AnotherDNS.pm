package probes::AnotherDNS;

=head1 NAME

probes::AnotherDNS - Alternate DNS Probe

=head1 SYNOPSIS

 *** Probes ***
 + AnotherDNS

 *** Targets *** 
 probe = AnotherDNS
 forks = 10

 + First
 menu = First
 title = First Target
 # .... 

 ++ PROBE_CONF
 lookup = www.mozilla.org

=head1 DESCRIPTION

Like DNS, but uses Net::DNS and Time::HiRes instead of dig. This probe does
*not* retry the request three times before it is considerd "lost", like dig and
other resolver do by default. If operating as caching Nameserver, BIND (and
maybe others) expect clients to retry the request if the answer is not in the
cache. So, ask the nameserver for something that he is authorative for if you
want measure the network packet loss correctly. 

If you have a really fast network and nameserver, you will notice that this
probe reports the query time in microsecond resolution. :-)

=over

=item forks

The number of concurrent processes to be run. See probes::basefork(3pm)
for details.

=back

Supported target-level probe variables:

=over

=item lookup

Name of the host to look up in the dns.

=item sleeptime

Time to sleep between two lookups in microseconds. Default is 500000.

=item recordtype

Record type to look up. Default is "A".

=item timeout

Timeout for a single request in seconds. Default is 5.

=item port

UDP Port to use. Default is 53. (Surprise!)

=back


=head1 AUTHOR

Christoph Heine E<lt>Christoph.Heine@HaDiKo.DEE<gt>

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

use base qw(probes::basefork);
use IPC::Open3;
use Symbol;
use Carp;
use Time::HiRes qw(usleep ualarm gettimeofday tv_interval);
use IO::Socket;
use IO::Select;

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
    my $sleeptime  = $target->{vars}{sleeptime};
    my $recordtype = $target->{vars}{recordtype};
    my $timeout = $target->{vars}{timeout};
    my $port = $target->{vars}{port};
    $recordtype = "A"    unless defined $recordtype;
    $timeout = 5    unless defined $timeout;
    $port = 53    unless defined $port;
    $sleeptime  = 500000 unless defined $sleeptime;
    $lookuphost = $target->{addr} unless defined $lookuphost;

    my $packet = Net::DNS::Packet->new( $lookuphost, $recordtype )->data;
    my $sock = IO::Socket::INET->new(
        "PeerAddr" => $host,
        "PeerPort" => $port,
        "Proto"    => "udp",
    );
    my $sel = IO::Select->new($sock);

    my @times;

    for ( my $run = 0 ; $run < $self->pings($target) ; $run++ ) {
        my $t0 = [gettimeofday];
        $sock->send($packet);
        my ($ready) = $sel->can_read($timeout);
        my $t1 = [gettimeofday];
        if ( defined $ready ) {
            my $time = tv_interval( $t0, $t1 );
            push @times, $time;
            my $buf = '';
            $ready->recv( $buf, &Net::DNS::PACKETSZ );
        }
        usleep($sleeptime);
    }
    @times =
      map { sprintf "%.10e", $_ } sort { $a <=> $b } grep { $_ ne "-" } @times;

    return @times;
}

1;

