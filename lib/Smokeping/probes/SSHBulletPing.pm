package Smokeping::probes::SSHBulletPing;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::SSHBulletPing>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::TelnetBulletPing>

to generate the POD document.

=cut

use strict;

use base qw(Smokeping::probes::basefork);
use Net::SSH::Expect;
#use Net::Telnet ();
use Carp;

my $e = "=";
sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::SSHBulletPing - Cisco Bullet Probe for SmokePing
DOC
		description => <<DOC,
Integrates Cisco Bullet as a probe into smokeping.  Uses the telnet protocol 
to run a ping from an Bullet device (source) to another device (host).
This probe basically uses the "extended ping" of the Cisco Bullet.  You have
the option to specify which interface the ping is sourced from as well.
DOC
		notes => <<DOC,
${e}head2 Bullet configuration

The Bullet device should have a username/password configured, as well as
the ability to connect to the VTY(s).
eg:

    !
    username smokeping privilege 5 password 0 SmokepingPassword
    !
    line vty 0 4
     login local
     transport input ssh
    !

Some Bullet devices have a maximum of 5 VTYs available, so be careful not
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
original BulletPing module used RSH, which is even more scary to use from
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
John A Jackson <geonjay@infoave.net>

based HEAVILY on Smokeping::probes::BulletPing by

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
	print "### assuming you are using an Bullet reporting in miliseconds\n";
    };

    return $self;
}

sub ProbeDesc($){
    my $self = shift;
    my $bytes = $self->{properties}{packetsize};
    return "InfoAve Cisco Bullet - ICMP Echo Pings ($bytes Bytes)";
}

sub pingone ($$){
    my $self = shift;
    my $target = shift;
    my $source = $target->{vars}{source};
    my $dest = $target->{vars}{host};
    my $psource = $target->{vars}{psource} || "  ";
    my $port = 23;
    my @output = ();
    my $login = $target->{vars}{Bulletuser};
    my $pssword = $target->{vars}{Bulletpass};
    my $bytes = $self->{properties}{packetsize};
    my $pings = $self->pings($target);
    my $timeout = $self->{properties}{timeout};


      my $ssh = Net::SSH::Expect->new (
            host => $source,
            user => $login,
	    password=> $pssword,
            raw_pty => 1,
	    timeout => 15,
        );


     $ssh->run_ssh() or die "SSH process couldn't start: $!";
    # print  "Connection is a ok\n";


    my $login_output = $ssh->login();
    if ($login_output !~ /BusyBox/) {
            die "Login has failed. Login output was $login_output";
    }
    $ssh->waitfor('#');
#    print $login_output;

    $ssh->timeout($timeout);
    $ssh->send("ping -s ".$bytes." -c 20 ".$dest);
    $ssh->waitfor('#');
    my $output=$ssh->before();

    my @lines= split /\n/, $output;


    my @times = ();
    foreach (@lines) {
	my    $line=$_;
#        print ($line);
	$line =~ /^\d+ bytes from $dest: seq=\d+ ttl=\d+ time=(\d+\.\d+) ms$/ && push(@times,$1);
    }

#    print "TIMES:";
#    print @times;



  @times = map {sprintf "%.10e", $_ / $self->{pingfactor}} sort {$a <=> $b} @times;





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
		_mandatory => [ 'Bulletuser', 'Bulletpass', 'source' ],
		source => {
			_doc => <<DOC,
The source option specifies the Bullet device to which we telnet.  This
is an IP address of an Bullet Device that you/your server:
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
option is left out the Bullet Device will source the packet automatically
based on routing and/or metrics.  If this doesn't make sense to you
then just leave it out.
DOC
			_example => "192.168.2.129",
		},
		Bulletuser => {
			_doc => <<DOC,
The Bulletuser option allows you to specify a username that has ping
capability on the Bullet Device.
DOC
			_example => 'user',
		},
		Bulletpass => {
			_doc => <<DOC,
The Bulletpass option allows you to specify the password for the username
specified with the option Bulletuser.
DOC
			_example => 'password',
		},
	});
}

1;


