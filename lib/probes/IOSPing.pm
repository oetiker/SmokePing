package probes::IOSPing;

=head1 NAME

probes::IOSPing - Cisco IOS Probe for SmokePing

=head1 SYNOPSIS

 *** Probes ***
 + IOSPing
 binary = /usr/bin/remsh
 packetsize = 1024
 forks = 1

 ++ PROBE_CONF
 ioshost = router
 iosuser = user
 iosint = source_address

=head1 DESCRIPTION

Integrates Cisco IOS as a probe into smokeping.  Uses the rsh / remsh
protocol to run a ping from an IOS device.

=head1 OPTIONS

The binary and ioshost options are mandatory.

The binary option specifies the path of the binary to be used to
connect to the IOS device.  Commonly used binaries are /usr/bin/rsh
and /usr/bin/remsh, although any script or binary should work if can
be called as 

    /path/to/binary [ -l user ] router ping

to produce the IOS ping dialog on stdin & stdout.

The (optional) packetsize option lets you configure the packetsize for
the pings sent.

The (optional) forks options lets you configure the number of
simultaneous remote pings to be run.  NB Some IOS devices have a
maximum of 5 VTYs available, so be careful not to hit a limit.

The ioshost option specifies the IOS device which should be used for
the ping.

The (optional) iosuser option allows you to specify the remote
username the IOS device.  If this option is omitted, the username
defaults to the default user used by the remsh command (usually the
user running the remsh command, ie the user running SmokePing).

The (optional) iosint option allows you to specify the source address
or interface in the IOS device. The value should be an IP address or
an interface name such as "Ethernet 1/0". If this option is omitted,
the IOS device will pick the IP address of the outbound interface to
use.

=head1 IOS CONFIGURATION

The IOS device must have rsh enabled and an appropriate trust defined,
eg:

    !
    ip rcmd rsh-enable
    ip rcmd remote-host smoke 192.168.1.2 smoke enable
    !

=head1 NOTES

=head2 Password authentication

It is not possible to use password authentication with rsh or remsh
due to fundamental limitations of the protocol.

=head2 Ping packet size

The FPing manpage has the following to say on the topic of ping packet
size:

Number of bytes of ping data to send.  The minimum size (normally 12)
allows room for the data that fping needs to do its work (sequence
number, timestamp).  The reported received data size includes the IP
header (normally 20 bytes) and ICMP header (8 bytes), so the minimum
total size is 40 bytes.  Default is 56, as in ping. Maximum is the
theoretical maximum IP datagram size (64K), though most systems limit
this to a smaller, system-dependent number.

=head1 AUTHOR

Paul J Murphy <paul@murph.org>

based on probes::FPing by

Tobias Oetiker <tobi@oetiker.ch>

=cut

use strict;
use base qw(probes::basefork);
use IPC::Open2;
use Symbol;
use Carp;

sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {
        croak "ERROR: IOSPing packetsize must be between 12 and 64000"
           if $self->{properties}{packetsize} and 
              ( $self->{properties}{packetsize} < 12 or $self->{properties}{packetsize} > 64000 ); 

        croak "ERROR: IOSPing 'binary' not defined in IOSPing probe definition"
            unless defined $self->{properties}{binary};

        croak "ERROR: IOSPing 'binary' does not point to an executable"
            unless -f $self->{properties}{binary} and -x $self->{properties}{binary};

	$self->{pingfactor} = 1000; # Gives us a good-guess default
	print "### assuming you are using an IOS reporting in miliseconds\n";
    };

    return $self;
}

sub ProbeDesc($){
    my $self = shift;
    my $bytes = $self->{properties}{packetsize} || 56;
    return "Cisco IOS - ICMP Echo Pings ($bytes Bytes)";
}

sub pingone ($$){
    my $self = shift;
    my $target = shift;
    my $bytes = $self->{properties}{packetsize} || 56;
    # do NOT call superclass ... the ping method MUST be overwriten
    my %upd;
    my $inh = gensym;
    my $outh = gensym;
    my @args = ();
    my $pings = $self->pings($target);

    croak "ERROR: IOSPing 'ioshost' not defined"
	unless defined $target->{vars}{ioshost};

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

1;
