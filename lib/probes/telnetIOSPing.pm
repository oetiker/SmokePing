package probes::telnetIOSPing;

=head1 NAME

probes::telnetIOSPing - Cisco IOS Probe for SmokePing

=head1 SYNOPSIS

 *** Probes ***
 + telnetIOSPing
 packetsize = 56
 forks = 1

 ++ PROBE_CONF
 iospass = password
 iosuser = user
 target = 192.168.1.1
 source = 192.168.2.1
 psource = 192.168.2.129

=head1 DESCRIPTION

Integrates Cisco IOS as a probe into smokeping.  Uses the telnet protocol 
to run a ping from an IOS device (source) to another device (target).
This probe basically uses the "extended ping" of the Cisco IOS.  You have
the option to specify which interface the ping is sourced from as well.

=head1 OPTIONS

The iosuser, iospass, source, and target options are mandatory.

The (optional) packetsize option lets you configure the packetsize for
the pings sent.  The default size is 56.

The (optional) forks options lets you configure the number of
simultaneous remote pings to be run.  NB Some IOS devices have a
maximum of 5 VTYs available, so be careful not to hit a limit.

The source option specifies the IOS device to which we telnet.  This
is an IP address of an IOS Device that you/your server:
	1)  Have the ability to telnet to
	2)  Have a valid username and password for

The target option specifies the device you wish to ping from your IOS
Device.

The (optional) psource option specifies an alternate IP address or
Interface from which you wish to source your pings from.  Routers
can have many many IP addresses, and interfaces.  When you ping from a
router you have the ability to choose which interface and/or which IP
address the ping is sourced from.  Specifying an IP/interface does not 
necessarily specify the interface from which the ping will leave, but
will specify which address the packet(s) appear to come from.  If this
option is left out the IOS Device will source the packet automatically
based on routing and/or metrics.  If this doesn't make sense to you
then just leave it out.

The iosuser option allows you to specify a username that has ping
capability on the IOS Device.

The iospass option allows you to specify the password for the username
specified with the option iosuser.

=head1 IOS CONFIGURATION

The IOS device should have a username/password configured, as well as
the ability to connect to the VTY(s).
eg:

    !
    username smokeping privilege 5 password 0 SmokepingPassword
    !
    line vty 0 4
     login local
     transport input telnet
    !

=head1 NOTES

=head2 Requirements

This module requires the Net::Telnet module for perl.  This is usually
included on most newer OSs which include perl.

=head2 Debugging

There is some VERY rudimentary debugging code built into this module (it's
based on the debugging code written into Net::Telnet).  It will log
information into three files "TIPreturn", "TIPoutlog", and "TIPdump".
These files will be written out into your current working directory (CWD).
You can change the names of these files to something with more meaning to
you.

=head2 Password authentication

You should be advised that the authentication method of telnet uses
clear text transmissions...meaning that without proper network security
measures someone could sniff your username and password off the network.
I may attempt to incorporate SSH in a future version of this module, but
it is very doubtful.  Right now SSH adds a LOT of processing overhead to
a router, and isn't incredibly easy to implement in perl.

Having said this, don't be too scared of telnet.  Remember, the
original IOSPing module used RSH, which is even more scary to use from
a security perspective.

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

John A Jackson <geonjay@infoave.net>

based HEAVILY on probes::IOSPing by

Paul J Murphy <paul@murph.org>

based on probes::FPing by

Tobias Oetiker <tobi@oetiker.ch>

=cut

use strict;

use base qw(probes::basefork);
use Net::Telnet ();
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

	$self->{pingfactor} = 1000; # Gives us a good-guess default
	print "### assuming you are using an IOS reporting in miliseconds\n";
    };

    return $self;
}

sub ProbeDesc($){
    my $self = shift;
    my $bytes = $self->{properties}{packetsize} || 56;
    return "InfoAve Cisco IOS - ICMP Echo Pings ($bytes Bytes)";
}

sub pingone ($$){
    my $self = shift;
    my $target = shift;
    my $source = $target->{vars}{source};
    my $dest = $target->{vars}{target};
    my $psource = $target->{vars}{psource} || "";
    my $port = 23;
    my @output = ();
    my $login = $target->{vars}{iosuser};
    my $pssword = $target->{vars}{iospass};
    my $bytes = $self->{properties}{packetsize} || 56;
    my $pings = $self->pings($target);

    # do NOT call superclass ... the ping method MUST be overwriten
    my %upd;
    my @args = ();


     my $telnet = new Net::Telnet;
#               These are for debugging
#               $telnet->errmode("TIPreturn");
#               $telnet->input_log("TIPinlog");
#               $telnet->dump_log("TIPdumplog");

#Open the Connection to the router
#     open(OUTF,">outfile.IA") || die "Can't open OUTF: $!";
#     print OUTF "target => $dest\nsource => $source\nuser => $login\n";
     my $ok = $telnet->open(Host => $source,
                   Port => $port);
#    print OUTF "Connection is a $ok\n";

    #Authenticate
     $telnet->waitfor('/(ogin|name|word):.*$/');
     $telnet->print("$login");
     $telnet->waitfor('/word:.*$/');
     $telnet->print("$pssword");
    #Do the work
     $telnet->waitfor('/[\@\w\-\.]+[>#][ ]*$/');
     $telnet->print("terminal length 0");
     $telnet->waitfor('/[\@\w\-\.]+[>#][ ]*$/');
     $telnet->print("ping");
     $telnet->waitfor('/Protocol \[ip\]: $/');
     $telnet->print("");
     $telnet->waitfor('/Target IP address: $/');
     $telnet->print("$dest");
     $telnet->waitfor('/Repeat count \[5\]: $/');
     $telnet->print($pings);
     $telnet->waitfor('/Datagram size \[100\]: $/');
     $telnet->print("$bytes");
     $telnet->waitfor('/Timeout in seconds \[2\]: $/');
     $telnet->print("");
     $telnet->waitfor('/Extended commands \[n\]: $/');
     $telnet->print("y");
     $telnet->waitfor('/Source address or interface: $/');
     $telnet->print("$psource");
     $telnet->waitfor('/Type of service \[0\]: $/');
     $telnet->print("");
     $telnet->waitfor('/Set DF bit in IP header\? \[no\]: $/');
     $telnet->print("");
     $telnet->waitfor('/Validate reply data\? \[no\]: $/');
     $telnet->print("");
     $telnet->waitfor('/Data pattern \[0xABCD\]: $/');
     $telnet->print("");
     $telnet->waitfor('/Loose, Strict, Record, Timestamp, Verbose\[none\]: $/');
     $telnet->print("v");
     $telnet->waitfor('/Loose, Strict, Record, Timestamp, Verbose\[V\]: $/');
     $telnet->print("");
     $telnet->waitfor('/Sweep range of sizes.+$/');

     $telnet->prompt('/[\@\w\-\.]+[>#][ ]*$/');
     @output = $telnet->cmd("n");
     
     #$telnet->waitfor('/[\@\w\-\.]+[>#][ ]*$/');
     $telnet->print("quit");
     $telnet->close;
#     print OUTF "closed Telnet connection\n";

    my @times = ();
    while (@output) {
	my $outputline = shift @output;
	chomp($outputline);
#	print OUTF "$outputline\n";
	$outputline =~ /^Reply to request \d+ \((\d+) ms\)/ && push(@times,$1);
	#print OUTF "$outputline => $1\n";
    }
    @times = map {sprintf "%.10e", $_ / $self->{pingfactor}} sort {$a <=> $b} @times;
#    close(OUTF);
    return @times;
}

1;
