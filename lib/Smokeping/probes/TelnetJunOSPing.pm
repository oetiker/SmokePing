package Smokeping::probes::TelnetJunOSPing;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::TelnetJunOSPing>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::TelnetJunOSPing>

to generate the POD document.

=cut

use strict;

use base qw(Smokeping::probes::basefork);
use Net::Telnet ();
use Carp;

my $e = "=";
sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::TelnetJunOSPing - Juniper JunOS Probe for SmokePing
DOC
		description => <<DOC,
Integrates Juniper JunOS as a probe into smokeping.  Uses the telnet protocol 
to run a ping from an JunOS device (source) to another device (host).
This probe basically uses the "extended ping" of the Juniper JunOS.  You have
the option to specify which interface the ping is sourced from as well.
DOC
		notes => <<DOC,
${e}head2 JunOS configuration

The JunOS device should have a username/password configured, as well as
the ability to connect to the VTY(s).

Some JunOS devices have a maximum of 5 VTYs available, so be careful not
to hit a limit with the 'forks' variable.

${e}head2 Requirements

This module requires the Net::Telnet module for perl.  This is usually
included on most newer OSs which include perl.

${e}head2 Debugging

There is some VERY rudimentary debugging code built into this module (it's
based on the debugging code written into Net::Telnet).  It will log
information into three files "TIPreturn", "TIPoutlog", and "TIPdump".
These files will be written out into your current working directory (CWD).
You can change the names of these files to something with more meaning to
you.

${e}head2 Password authentication

You should be advised that the authentication method of telnet uses
clear text transmissions...meaning that without proper network security
measures someone could sniff your username and password off the network.
I may attempt to incorporate SSH in a future version of this module, but
it is very doubtful.  Right now SSH adds a LOT of processing overhead to
a router, and isn't incredibly easy to implement in perl.

Having said this, don't be too scared of telnet.  Remember, the
original JunOSPing module used RSH, which is even more scary to use from
a security perspective.

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
S H A N <shanali@yahoo.com>

based HEAVILY on Smokeping::probes::TelnetIOSPing by

John A Jackson <geonjay@infoave.net>

based on Smokeping::probes::JunOSPing by

Paul J Murphy <paul@murph.org>

based on Smokeping::probes::FPing by

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
	print "### assuming you are using an JunOS reporting in milliseconds\n";
    };

    return $self;
}

sub ProbeDesc($){
    my $self = shift;
    my $bytes = $self->{properties}{packetsize};
    return "InfoAve Juniper JunOS - ICMP Echo Pings ($bytes Bytes)";
}

sub pingone ($$){
    my $self = shift;
    my $target = shift;
    my $source = $target->{vars}{source};
    my $dest = $target->{vars}{host};
    my $psource = $target->{vars}{psource};
    my $port = 23;
    my @output = ();
    my $login = $target->{vars}{junosuser};
    my $pssword = $target->{vars}{junospass};
    my $bytes = $self->{properties}{packetsize};
    my $pings = $self->pings($target);

    # do NOT call superclass ... the ping method MUST be overwriten
    my %upd;
    my @args = ();


     my $telnet = Net::Telnet->new(Timeout => 60);
#               $telnet->errmode("TIPreturn");
#               $telnet->input_log("TIPinlog");
#               $telnet->dump_log("TIPdumplog");

# Open the Connection to the router
#     open(OUTF,">outfile.IA") || die "Can't open OUTF: $!";
#     print OUTF "target => $dest\nsource => $source\nuser => $login\n";
     my $ok = $telnet->open(Host => $source,
                   Port => $port);
    # print OUTF "Connection is a $ok\n";

    #Authenticate
     $telnet->waitfor('/(ogin):.*$/');
     $telnet->print("$login");
     $telnet->waitfor('/word:.*$/');
     $telnet->print("$pssword");
     $telnet->prompt('/[\@\w\-\.]+[>#][ ]*$/');
    #Do the work
     $telnet->waitfor('/[\@\w\-\.]+[>#][ ]*$/');
     $telnet->print("set cli screen-length 0");
     $telnet->waitfor('/[\@\w\-\.]+[>#][ ]*$/');
     if ( $psource ) {
         @output = $telnet->cmd("ping $dest count $pings size $bytes source $psource");
     } else {
         @output = $telnet->cmd("ping $dest count $pings size $bytes");
     }
     $telnet->print("quit");
     $telnet->close;
     # print OUTF "closed Telnet connection\n";

    my @times = ();
    while (@output) {
	my $outputline = shift @output;
	chomp($outputline);
	# print OUTF "$outputline\n";
        $outputline =~ /^\d+ bytes from $dest: icmp_seq=\d+ ttl=\d+ time=(\d+\.\d+) ms$/ && push(@times,$1);
	#print OUTF "$outputline => $1\n";
    }
    @times = map {sprintf "%.10e", $_ / $self->{pingfactor}} sort {$a <=> $b} @times;
#    close(OUTF);
    return @times;
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		packetsize => {
			_doc => <<DOC,
The (optional) packetsize option lets you configure the packetsize for
the pings sent.
DOC
			_default => 100,
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
		_mandatory => [ 'junosuser', 'junospass', 'source' ],
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
		junosuser => {
			_doc => <<DOC,
The junosuser option allows you to specify a username that has ping
capability on the JunOS Device.
DOC
			_example => 'user',
		},
		junospass => {
			_doc => <<DOC,
The junospass option allows you to specify the password for the username
specified with the option junosuser.
DOC
			_example => 'password',
		},
	});
}

1;
