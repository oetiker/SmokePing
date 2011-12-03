package Smokeping::probes::TCPPing;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::FPing>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::FPing>

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
Smokeping::probes::TCPPing - TCPPing Probe for SmokePing
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
            $self->{pingfactor} = 1000 * $2/$1;
            print "### tcpping seems to report in ", $1/$2, " milliseconds\n";
        } else {
            $self->{pingfactor} = 1000; # Gives us a good-guess default
            print "### assuming you are using an tcpping copy reporting in milliseconds\n";
        }
    };

    return $self;
}

sub ProbeDesc($){
    my $self = shift;
    return "TCP Pings";
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		_mandatory => [ 'binary' ],
		binary => { 
			_doc => "The location of your tcpping script.",
			_example => '/usr/bin/tcpping',
			_sub => sub { 
				my $val = shift;

        			return "ERROR: TCPPing 'binary' does not point to an executable"
            				unless -f $val and -x _;

				my $return = `$val -C -x 1 localhost 2>&1`;
				return "ERROR: tcpping must be installed setuid root or it will not work\n"
					if $return =~ m/only.+root/;

				return undef;
			},
		},
		tcptraceroute => { 
			_doc => "tcptraceroute Options to pass to tcpping.",
			_example => '-e "sudo /bin/tcptraceroute"',
		},
	});
}

sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		port => {
			_doc => "The TCP port the probe should measure.",
			_example => '80',
			_sub => sub {
				my $val = shift;

				return "ERROR: TCPPing port must be between 0 and 65535"
					if $val and ( $val < 0 or $val > 65535 ); 

				return undef;
			},
		},
	});
}

sub pingone ($){
    my $self = shift;
    my $target = shift;
    # do NOT call superclass ... the ping method MUST be overwriten
    my $inh = gensym;
    my $outh = gensym;
    my $errh = gensym;

    my @times; # Result times

    my @port = () ;
    push @port, $target->{vars}{port} if $target->{vars}{port};

    my @cmd = (
                    $self->{properties}{binary},
                    '-C', '-x', $self->pings($target)
	);

    if ($self->{properties}{tcptraceroute})
    {
        push @cmd, '-e', $self->{properties}{tcptraceroute};
    }

    push @cmd, $target->{addr}, @port;

    $self->do_debug("Executing @cmd");
    my $pid = open3($inh,$outh,$errh, @cmd);
    while (<$outh>){
        chomp;
        $self->do_debug("Received: $outh");
        next unless /^\S+\s+:\s+[\d\.]/; #filter out error messages from tcpping
        @times = split /\s+/;
        my $ip = shift @times;
        next unless ':' eq shift @times; #drop the colon

        @times = map {sprintf "%.10e", $_ / $self->{pingfactor}} sort {$a <=> $b} grep /^\d/, @times;
    }
    waitpid $pid,0;
    close $inh;
    close $outh;
    close $errh;

    return @times;
}

1;
