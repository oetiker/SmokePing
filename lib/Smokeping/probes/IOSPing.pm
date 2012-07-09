package Smokeping::probes::IOSPing;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::IOSPing>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::IOSPing>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork);
use IPC::Open2;
use Symbol;
use Carp;

my $e = "=";

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::IOSPing - Cisco IOS Probe for SmokePing
DOC
		description => <<DOC,
Integrates Cisco IOS as a probe into smokeping.  Uses the rsh / remsh
protocol to run a ping from an IOS device.
DOC
	notes => <<DOC,
=head2 IOS Configuration

The IOS device must have rsh enabled and an appropriate trust defined,
eg:

    !
    ip rcmd rsh-enable
    ip rcmd remote-host smoke 192.168.1.2 smoke enable
    !

Some IOS devices have a maximum of 5 VTYs available, so be careful not to 
hit a limit with the 'forks' variable.

${e}head2 Password authentication

It is not possible to use password authentication with rsh or remsh
due to fundamental limitations of the protocol.

${e}head2 Ping packet size

The FPing manpage has the following to say on the topic of ping packet
size:

Number of bytes of ping data to send.  The minimum size (normally 12)
allows room for the data that fping needs to do its work (sequence
number, timestamp).  The reported received data size includes the IP
header (normally 20 bytes) and ICMP header (8 bytes), so the minimum
total size is 40 bytes.  Default is 56, as in ping. Maximum is the
theoretical maximum IP datagram size (64K), though most systems limit
this to a smaller, system-dependent number.
DOC
	authors => <<'DOC',
Paul J Murphy <paul@murph.org>

based on L<Smokeping::probes::FPing|Smokeping::probes::FPing> by

Tobias Oetiker <tobi@oetiker.ch>
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
	$self->{pingfactor} = 1000; # Gives us a good-guess default
	print "### assuming you are using an IOS reporting in milliseconds\n";
    };

    return $self;
}

sub ProbeDesc($){
    my $self = shift;
    my $bytes = $self->{properties}{packetsize};
    return "Cisco IOS - ICMP Echo Pings ($bytes Bytes)";
}

sub pingone ($$){
    my $self = shift;
    my $target = shift;
    my $bytes = $self->{properties}{packetsize};
    # do NOT call superclass ... the ping method MUST be overwriten
    my %upd;
    my $inh = gensym;
    my $outh = gensym;
    my @args = ();
    my $pings = $self->pings($target);

    push(@args,$self->{properties}{binary});
    push(@args,'-l',$target->{vars}{iosuser})
	if defined $target->{vars}{iosuser};
    push(@args,$target->{vars}{ioshost});
    push(@args,'ping');

    my $pid = open2($outh,$inh,@args);
    #
    # The following comments are the dialog produced by
    # "remsh <router> ping" to a Cisco 800 series running IOS 12.2T
    #
    # Other hardware or versions of IOS may need adjustments here.
    #
    # Protocol [ip]: 
    print { $inh } "\n";
    # Target IP address: 
    print { $inh } $target->{addr},"\n";
    # Repeat count [5]: 
    print { $inh } $pings,"\n";
    # Datagram size [100]: 
    print { $inh } $bytes,"\n";
    # Timeout in seconds [2]: 
    print { $inh } "\n";
    # Extended commands [n]: 
    print { $inh } "y\n";
    # Source address or interface: 
    print { $inh } "".($target->{vars}{iosint} || "") ,"\n";
         # Added by Mars Wei to make
         # Source address an option
    # Type of service [0]: 
    print { $inh } "\n";
    # Set DF bit in IP header? [no]: 
    print { $inh } "\n";
    # Validate reply data? [no]: 
    print { $inh } "\n";
    # Data pattern [0xABCD]: 
    print { $inh } "\n";
    # Loose, Strict, Record, Timestamp, Verbose[none]: 
    print { $inh } "V\n";
    # Loose, Strict, Record, Timestamp, Verbose[V]: 
    print { $inh } "\n";
    # Sweep range of sizes [n]: 
    print { $inh } "\n";
    #
    # Type escape sequence to abort.
    # Sending 20, 56-byte ICMP Echos to 192.168.1.2, timeout is 2 seconds:
    # Reply to request 0 (4 ms)
    # Reply to request 1 (4 ms)
    # Reply to request 2 (4 ms)
    # Reply to request 3 (1 ms)
    # Reply to request 4 (1 ms)
    # Reply to request 5 (1 ms)
    # Reply to request 6 (4 ms)
    # Reply to request 7 (4 ms)
    # Reply to request 8 (4 ms)
    # Reply to request 9 (4 ms)
    # Reply to request 10 (1 ms)
    # Reply to request 11 (1 ms)
    # Reply to request 12 (1 ms)
    # Reply to request 13 (1 ms)
    # Reply to request 14 (4 ms)
    # Reply to request 15 (4 ms)
    # Reply to request 16 (4 ms)
    # Reply to request 17 (4 ms)
    # Reply to request 18 (1 ms)
    # Reply to request 19 (1 ms)
    # Success rate is 100 percent (20/20), round-trip min/avg/max = 1/2/4 ms

    my @times = ();
    while (<$outh>){
	chomp;
	/^Reply to request \d+ \((\d+) ms\)/ && push(@times,$1);
    }
    @times = map {sprintf "%.10e", $_ / $self->{pingfactor}} sort {$a <=> $b} @times;

    waitpid $pid,0;
    close $inh;
    close $outh;

    return @times;
}

sub probevars {
	my $class = shift;
        return $class->_makevars($class->SUPER::probevars, {
		_mandatory => ['binary'],
		binary => {
			_doc => <<DOC,
The binary option specifies the path of the binary to be used to
connect to the IOS device.  Commonly used binaries are /usr/bin/rsh
and /usr/bin/remsh, although any script or binary should work if can
be called as 

    /path/to/binary [ -l user ] router ping

to produce the IOS ping dialog on stdin & stdout.
DOC
			_example => '/usr/bin/rsh',
			_sub => sub {
				my $val = shift;
				-x $val or return "ERROR: binary '$val' is not executable";
				return undef;
			},
		},
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
		_mandatory => [ 'ioshost' ],
		ioshost => {
			_doc => <<DOC,
The ioshost option specifies the IOS device which should be used for
the ping.
DOC
			_example => 'my.cisco.router',
		},
		iosuser => {
			_doc => <<DOC,
The (optional) iosuser option allows you to specify the remote
username the IOS device.  If this option is omitted, the username
defaults to the default user used by the remsh command (usually the
user running the remsh command, ie the user running SmokePing).
DOC
			_example => 'admin',
		},
		iosint => {
			_doc => <<DOC,
The (optional) iosint option allows you to specify the source address
or interface in the IOS device. The value should be an IP address or
an interface name such as "Ethernet 1/0". If this option is omitted,
the IOS device will pick the IP address of the outbound interface to
use.
DOC
			_example => 'Ethernet 1/0',
		},
	});
}

1;
