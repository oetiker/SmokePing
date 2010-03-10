package Smokeping::probes::CiscoRTTMonTcpConnect;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::CiscoRTTMonTcpConnect>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::CiscoRTTMonTcpConnect>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork);
use Symbol;
use Carp;
use BER;
use SNMP_Session;
use SNMP_util "0.97";
use Smokeping::ciscoRttMonMIB "0.2";

sub pod_hash {
	my $e = "=";
	return {
		name => <<DOC,
Smokeping::probes::CiscoRTTMonTcpConnect - Probe for SmokePing
DOC
		description => <<DOC,
A probe for smokeping, which uses the ciscoRttMon MIB functionality ("Service Assurance Agent", "SAA") of Cisco IOS to measure TCP connect times between a Cisco router and a TCP server. The measured value is the time is the time to establish a TCP session, i.e. the time between the initial "SYN" TCP packet of the router and the "SYN ACK" packet of the host. The router terminates the TCP session immediately after the reception of "SYN ACK" with a "FIN" packet.
DOC
		notes => <<DOC,
${e}head2 IOS VERSIONS

This probe only works with Cisco IOS 12.0(3)T or higher. It is recommended to test it on less critical routers first. 

${e}head2 INSTALLATION

To install this probe copy ciscoRttMonMIB.pm to (\$SMOKEPINGINSTALLDIR)/Smokeping/lib and CiscoRTTMonTcpConnect.pm to (\$SMOKEPINGINSTALLDIR)/lib/Smokeping/probes. V0.97 or higher of Simon Leinen's SNMP_Session.pm is required.

The router(s) must be configured to allow read/write SNMP access. Sufficient is:

	snmp-server community RTTCommunity RW
 
If you want to be a bit more restrictive with SNMP write access to the router, then consider configuring something like this 

	access-list 2 permit 10.37.3.5
	snmp-server view RttMon ciscoRttMonMIB included
	snmp-server community RTTCommunity view RttMon RW 2

The above configuration grants SNMP read-write only to 10.37.3.5 (the smokeping host) and only to the ciscoRttMon MIB tree. The probe does not need access to SNMP variables outside the RttMon tree.
DOC
		bugs => <<DOC,
The probe establishes unnecessary connections, i.e. more than configured in the "pings" variable, because the RTTMon MIB only allows to set a total time for all connections in one measurement run (one "life"). Currently the probe sets the life duration to "pings"*5+3 seconds (5 secs is the timeout value hardcoded into this probe). 
DOC
		see_also => <<DOC,
L<http://oss.oetiker.ch/smokeping/>

L<http://www.switch.ch/misc/leinen/snmp/perl/>

The best source for background info on SAA is Cisco's documentation on L<http://www.cisco.com> and the CISCO-RTTMON-MIB documentation, which is available at: 
L<ftp://ftp.cisco.com/pub/mibs/v2/CISCO-RTTMON-MIB.my>
DOC
		authors => <<DOC,
Joerg.Kummer at Roche.com 
DOC
	}
}

my $pingtimeout = 5;

sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {
        $self->{pingfactor} = 1000;
    };
    return $self;
}

sub ProbeDesc($){
    my $self = shift;
    return "CiscoRTTMonTcpConnect";
}

sub pingone ($$) { 
    my $self = shift;
    my $target = shift;

    my $pings = $self->pings($target) || 20;
    my $tos   = $target->{vars}{tos};
    my $port = $target->{vars}{port};

    # use the proces ID as as row number to make this poll distinct on the router; 
    my $row=$$;

    if (defined 
        StartRttMibEcho($target->{vars}{ioshost}.":::::2", $target->{addr}, $port,
        $pings, $target->{vars}{iosint}, $tos, $row)) 
	{
        # wait for the series to finish
        sleep ($pings*$pingtimeout+5);
        if (my @times=FillTimesFromHistoryTable($target->{vars}{ioshost}.":::::2", $pings, $row)){
		DestroyData ($target->{vars}{ioshost}.":::::2", $row);
		return @times;
	   }
	else {
		return();
		}
	}
    else {
        return ();
    } 
}

sub StartRttMibEcho ($$$$$$){
	my ($host, $target, $port, $pings, $sourceip, $tos, $row) = @_;

	# resolve the target name and encode its IP address
	$_=$target;
	if (!/^([0-9]|\.)+/) {
		(my $name, my $aliases, my $addrtype, my $length, my @addrs) = gethostbyname ($target);
		$target=join('.',(unpack("C4",$addrs[0])));
		}
	my @octets=split(/\./,$target);
	my $encoded_target= pack ("CCCC", @octets);

	# resolve the source name and encode its IP address
	my $encoded_source = undef;
	if (defined $sourceip) {
		$_=$sourceip;
		if (!/^([0-9]|\.)+/) {
			(my $name, my $aliases, my $addrtype, my $length, my @addrs) = gethostbyname ($sourceip);
			$sourceip=join('.',(unpack("C4",$addrs[0])));
			}
		my @octets=split(/\./,$sourceip);
		$encoded_source= pack ("CCCC", @octets);
		}

	#############################################################
	# rttMonCtrlAdminStatus - 1:active 2:notInService 3:notReady 4:createAndGo 5:createAndWait 6:destroy
	#delete data from former measurements
	#return undef unless defined 
	#  &snmpset($host, "rttMonCtrlAdminStatus.$row",'integer', 	6);

	############################################################# 
	# Check RTTMon version and supported protocols
    	$SNMP_Session::suppress_warnings = 10; # be silent
	(my $version)=&snmpget ($host, "rttMonApplVersion");
	if (! defined $version ) {
		Smokeping::do_log ("$host doesn't support or allow RTTMon !\n");
		return undef;
	}
	Smokeping::do_log ("$host supports $version\n");
    	$SNMP_Session::suppress_warnings = 0; # report errors

	# echo(1), pathEcho(2), fileIO(3), script(4), udpEcho(5), tcpConnect(6), http(7), 
	# dns(8), jitter(9), dlsw(10), dhcp(11), ftp(12)

	my $tcpConnSupported=0==1;
	snmpmaptable ($host,
		sub () {
			my ($proto, $supported) = @_;
			# 1 is true , 2 is false
			$tcpConnSupported=0==0 if ($proto==6 && $supported==1);
			},
		"rttMonApplSupportedRttTypesValid");

	if (! $tcpConnSupported) {
		Smokeping::do_log ("$host doesn't support TCP connection time measurements !\n");
		return undef;
	}


	#############################################################
	#setup the new data row

	my @params=();
	push @params,  
		"rttMonCtrlAdminStatus.$row",		'integer', 	5,
		"rttMonCtrlAdminRttType.$row",		'integer',	6,
		"rttMonEchoAdminProtocol.$row",		'integer',	24,
		"rttMonEchoAdminTargetAddress.$row",	'octetstring',	$encoded_target,
		"rttMonEchoAdminTargetPort.$row",	'integer', 	$port,
		"rttMonCtrlAdminTimeout.$row",		'integer',	$pingtimeout*1000,
		"rttMonCtrlAdminFrequency.$row",	'integer',	$pingtimeout,
		"rttMonEchoAdminControlEnable.$row",	'integer',	2,
		"rttMonEchoAdminTOS.$row",		'integer',	$tos,
		"rttMonCtrlAdminNvgen.$row",		'integer',	2,
		"rttMonHistoryAdminNumBuckets.$row",	'integer', 	$pings,
		"rttMonHistoryAdminNumLives.$row",	'integer', 	1,
		"rttMonHistoryAdminFilter.$row", 	'integer', 	2,
		"rttMonScheduleAdminRttStartTime.$row",	'timeticks',	1,
		"rttMonScheduleAdminRttLife.$row",	'integer',	$pings*$pingtimeout+3,
		"rttMonScheduleAdminConceptRowAgeout.$row",'integer', 	60;

		# the router (or this script) doesn't check whether the IP address is one of 
		# the router's IP address, i.e. the router might send packets, but never 
		# gets replies..
		if (defined $sourceip) {
			push @params, 	"rttMonEchoAdminSourceAddress.$row",		'octetstring',	$encoded_source;
		}

	return undef unless defined 
	   &snmpset($host, @params);

	#############################################################
	# and go !
	return undef unless defined 
	   &snmpset($host, "rttMonCtrlAdminStatus.$row",'integer',1);

	return 1;
}


# RttResponseSense values
# 1:ok 2:disconnected 3:overThreshold 4:timeout 5:busy 6:notConnected 7:dropped 8:sequenceError 
# 9:verifyError 10:applicationSpecific 11:dnsServerTimeout 12:tcpConnectTimeout 13:httpTransactionTimeout
#14:dnsQueryError 15:httpError 16:error

sub FillTimesFromHistoryTable($$$$) {
	my ($host, $pings, $row) = @_;
	my @times;

	# snmpmaptable walks two columns of rttMonHistoryCollectionTable
	# - "rttMonHistoryCollectionCompletionTime.$row",
	# - "rttMonHistoryCollectionSense.$row"
	# The code in the sub() argument is executed for each index value snmptable walks
	snmpmaptable ($host,
		sub () {
			my ($index, $rtt, $status) = @_;
			push @times, (sprintf ("%.10e", $rtt/1000))
				if ($status==1);
		},
		"rttMonHistoryCollectionCompletionTime.$row",
		"rttMonHistoryCollectionSense.$row");

	return sort { $a <=> $b } @times;
}

sub DestroyData ($$) {
	my ($host, $row) = @_;

	&snmpset($host, "rttMonCtrlOperState.$row",             'integer',      3);
	&snmpset($host, "rttMonCtrlAdminStatus.$row",           'integer',      2);
	#delete any old config
	&snmpset($host, "rttMonCtrlAdminStatus.$row",           'integer',      6);
}

sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		_mandatory => [ 'ioshost' ],
		ioshost => {
			_example => 'RTTcommunity@Myrouter.foobar.com.au',
			_doc => <<DOC,
The (mandatory) ioshost parameter specifies the Cisco router, which will
establish the TCP connections as well as the SNMP community string on
the router.
DOC
		},
		port => {
			_default => 80,
			_re => '\d+',
			_doc => <<DOC,
The (optional) port parameter lets you configure the destination TCP
port on the host. The default is the http port 80.
DOC
		},
        timeout => {
             _re => '\d+', 
             _example => 15,
             _default => $pingtimeout+10,
             _doc => "How long a single RTTMon TcpConnect 'ping' take at maximum plus 10 seconds to spare. Since we control our own timeout the only purpose of this is to not have us killed by the ping method from basefork.",
        },
		iosint => {
			_example => '10.33.22.11',
			_doc => <<DOC,
The (optional) iosint parameter is the source address for the TCP
connections. This should be one of the active (!) IP addresses of the
router to get results. IOS looks up the target host address in the
forwarding table and then uses the interface(s) listed there to send
the TCP packets. By default IOS uses the (primary) IP address on the
sending interface as source address for a connection.
DOC
		},
		tos => {
			_default => 0,
			_example => 160,
			_re => '\d+',
			_doc => <<DOC,
The (optional) tos parameter specifies the value of the ToS byte in the
IP header of the packets from the router. Multiply DSCP values times 4
and Precedence values times 32 to calculate the ToS values to configure,
e.g. ToS 160 corresponds to a DSCP value 40 and a Precedence value of
5. Please note that this will not influence the ToS value in the packets
sent by the the host.
DOC
		},
	});
}

1;

