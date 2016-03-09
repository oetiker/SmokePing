package Smokeping::probes::RshSkymanPing;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::RshSkymanPing>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::RshSkymanPing>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork);
use IPC::Open3;
use Symbol;
use Carp;

sub pod_hash {
      return {
              name => <<DOC,
Smokeping::probes::RshSkymanPing - TCPPing Probe for SmokePing
DOC
              description => <<DOC,
Integrates TCPPing as a probe into smokeping. The variable B<binary> must
point to your copy of the TCPPing program. If it is not installed on
your system yet, you can get it from http://www.vdberg.org/~richard/tcpping.
You can also get it from http://www.darkskies.za.net/~norman/scripts/tcpping.

The (optional) port option lets you configure the port for the pings sent.
The TCPPing manpage has the following to say on this topic:

The problem is that with the widespread use of firewalls on the modern Internet,
many of the packets that traceroute(8) sends out end up being filtered, 
making it impossible to completely trace the path to the destination. 
However, in many cases, these firewalls will permit inbound TCP packets to specific 
ports that hosts sitting behind the firewall are listening for connections on. 
By sending out TCP SYN packets instead of UDP or ICMP ECHO packets, 
tcptraceroute is able to bypass the most common firewall filters.

It is worth noting that tcptraceroute never completely establishes a TCP connection 
with the destination host. If the host is not listening for incoming connections, 
it will respond with an RST indicating that the port is closed. If the host instead 
responds with a SYN|ACK, the port is known to be open, and an RST is sent by 
the kernel tcptraceroute is running on to tear down the connection without completing 
three-way handshake. This is the same half-open scanning technique that nmap(1) uses 
when passed the -sS flag.
DOC
                authors => <<'DOC',
Norman Rasmussen <norman@rasmussen.co.za>
Patched for Smokeping 2.x compatibility by Anton Chernev <maznio@doom.bg>
DOC
        }
}


sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {
        my $return = `$self->{properties}{binary} -C -x 1 localhost 2>&1`;
        if ($return =~ m/bytes, ([0-9.]+)\sms\s+.*\n.*\n.*:\s+([0-9.]+)/ and $1 > 0){
            $self->{pingfactor} = 1000 ;
	    #* $2/$1;
            #print "### tcpping seems to report in ", $1/$2, " milliseconds\n";
        } else {
            $self->{pingfactor} = 1000; # Gives us a good-guess default
            #print "### assuming you are using an tcpping copy reporting in milliseconds\n";
        }
    };

    return $self;
}

sub ProbeDesc($){
    my $self = shift;
    my $bytes = $self->{properties}{packetsize};
    return "Skyman Wanflex Pings - ICMP Echo Pings ($bytes Bytes)";
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		_mandatory => [ 'packetsize' ],

                packetsize => {
                        _doc => <<DOC,
The (optional) packetsize option lets you configure the packetsize for
the pings sent.
DOC
                        _default => 56,
                        _re => '\d+',
                        _sub => sub {
                                my $val = shift;
                                return "ERROR: packetsize must be between 12 and 64000"
                                        unless $val >= 12 and $val <= 64000;
                                return undef;
                        },
                },
	});
}

sub targetvars {
        my $class = shift;
        return $class->_makevars($class->SUPER::targetvars, {
                _mandatory => [  'source' ],
                source => {
                        _doc => <<DOC,
The source option specifies the JunOS device to which we telnet.  This
is an IP address of an JunOS Device that you/your server:
        1)  Have the ability to telnet to
        2)  Have a valid username and password for
DOC
                        _example => "192.168.2.1",
                },
                psource => {
                        _doc => <<DOC,
The (optional) psource option specifies an alternate IP address or
Interface from which you wish to source your pings from.  Routers
can have many many IP addresses, and interfaces.  When you ping from a
router you have the ability to choose which interface and/or which IP
address the ping is sourced from.  Specifying an IP/interface does not
necessarily specify the interface from which the ping will leave, but
will specify which address the packet(s) appear to come from.  If this
option is left out the JunOS Device will source the packet automatically
based on routing and/or metrics.  If this doesn't make sense to you
then just leave it out.
DOC
                        _example => "192.168.2.129",
                },
        });
}




sub pingone ($$){
    my $self = shift;
    my $target = shift;
    my $source = $target->{vars}{source};
    my $dest = $target->{vars}{host};
    my $psource = $target->{vars}{psource};
    my $port = 23;
    my @output = ();
    my $bytes = $self->{properties}{packetsize};
#    my $pings = $self->pings($target);
    my $pings = "20";

    # do NOT call superclass ... the ping method MUST be overwriten
    my %upd;
    my @args = ();

#open(FFF,">>/tmp/file.txt");

    my @output = ();

    my $flag = 0;

     if ( $psource ) {
#	open (PINGTEST, "/usr/bin/rsh -l root $source ping $dest  size $bytes count $pings source $psource|");
#    $flag = 1;
#    open(FFF,">>/tmp/file.txt");

  open (PINGTEST,"/usr/bin/expect  -c 'set  timeout  60 
	spawn /usr/bin/rsh -l root $source ping $dest size $bytes count $pings source $psource
	expect eof' |");
	    while (<PINGTEST>){
	    push @output, $_;
	}

     } else {
#         print (FFF "/usr/bin/rsh -l root $source ping $dest  size $bytes count $pings");

#	open (PINGTEST, "/usr/bin/rsh -l root $source ping $dest size $bytes count $pings |");
      open (PINGTEST,"/usr/bin/expect  -c 'set  timeout  60 
	spawn /usr/bin/rsh -l root $source ping $dest size $bytes count $pings 
	expect eof' |");
	while (<PINGTEST>){
	push @output, $_;
	}
     }

#print "All done!\n";
close PINGTEST;





if ( $flag ) {
    print(FFF @output);
}

    my @times = ();
      foreach (@output) {
	my    $line=$_;
	    chop($line);
	    chop($line);
#	    print (FFF $line);
		#RWR
		$line =~ /^\d+ bytes from $dest: icmp_seq=\d+ ttl=\d+ time=(\d+) ms$/ && push(@times,$1);
		#skyman
		$line =~ /^\d+ bytes from $dest: icmp_seq=\d+ ttl=\d+ time=(\d+\.\d+) ms$/ && push(@times,$1);
       }


      @times = map {sprintf "%.10e", $_ / $self->{pingfactor}} sort {$a <=> $b} @times;

if ( $flag ) {
    foreach (@times) {
	print(FFF $_."\n");
    }
}


if ($flag) {
    close (FFF);
}

      return @times;

}

1;