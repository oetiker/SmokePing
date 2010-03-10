package Smokeping::probes::CiscoRTTMonDNS;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::CiscoRTTMonDNS>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::CiscoRTTMonDNS>

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

my $e = "=";
sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::CiscoRTTMonDNS.pm - Probe for SmokePing
DOC
		description => <<DOC,
A probe for smokeping, which uses the ciscoRttMon MIB functionality ("Service Assurance Agent", "SAA") of Cisco IOS to time ( recursive, type A) DNS queries to a DNS server.

DOC

		notes => <<DOC,
${e}head2 host parameter

The host parameter specifies the DNS server, which the router will use.

${e}head2 IOS VERSIONS

This probe only works with IOS 12.0(3)T or higher.  It is recommended to test it on less critical routers first. 

${e}head2 INSTALLATION

To install this probe copy ciscoRttMonMIB.pm to (\$SMOKEPINGINSTALLDIR)/lib/Smokeping and CiscoRTTMonDNS.pm to (\$SMOKEPINGINSTALLDIR)/lib/Smokeping/probes.

The router(s) must be configured to allow read/write SNMP access. Sufficient is:

	snmp-server community RTTCommunity RW
 
If you want to be a bit more restrictive with SNMP write access to the router, then consider configuring something like this 

	access-list 2 permit 10.37.3.5
	snmp-server view RttMon ciscoRttMonMIB included
	snmp-server community RTTCommunity view RttMon RW 2

The above configuration grants SNMP read-write only to 10.37.3.5 (the smokeping host) and only to the ciscoRttMon MIB tree. The probe does not need access to SNMP variables outside the RttMon tree.
DOC
		bugs => <<DOC,
The probe does unnecessary DNS queries, i.e. more than configured in the "pings" variable, because the RTTMon MIB only allows to set a total time for all queries in one measurement run (one "life"). Currently the probe sets the life duration to "pings"*5+3 seconds (5 secs is the timeout value hardcoded into this probe). 
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
    return "CiscoRTTMonDNS.pm";
}

sub pingone ($$) { 
    my $self = shift;
    my $target = shift;

    my $name = $target->{vars}{name};
    
    my $pings = $self->pings($target) || 20;

    # use the proces ID as as row number to make this poll distinct on the router; 
    my $row=$$;

    if (defined 
        StartRttMibEcho($target->{vars}{ioshost}.":::::2", $target->{addr}, $name,
        $pings, $target->{vars}{iosint}, $row)) 
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
	my ($host, $target, $dnsName, $pings, $sourceip, $row) = @_;

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

	my $DnsSupported=0==1;
	snmpmaptable ($host,
		sub () {
			my ($proto, $supported) = @_;
			# 1 is true , 2 is false
			$DnsSupported=0==0 if ($proto==8 && $supported==1);
		},
		"rttMonApplSupportedRttTypesValid");

	if (! $DnsSupported) {
		Smokeping::do_log ("$host doesn't support DNS resolution time measurements !\n");
		return undef;
	}


	#############################################################
	#setup the new data row

	my @params=();
	push @params,  
		"rttMonCtrlAdminStatus.$row",		'integer', 	5,
		"rttMonCtrlAdminRttType.$row",		'integer',	8,
		"rttMonEchoAdminProtocol.$row",		'integer',	26,
		"rttMonEchoAdminNameServer.$row",	'octetstring',	$encoded_target,
		"rttMonEchoAdminTargetAddressString.$row",'octetstring', $dnsName,
		"rttMonCtrlAdminTimeout.$row",		'integer',	$pingtimeout*1000,
		"rttMonCtrlAdminFrequency.$row",	'integer',	$pingtimeout,
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

	# snmpmaptable walks two tables (of equal size)
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
		_mandatory => [ 'ioshost', 'name' ],
		ioshost => {
			_doc => <<DOC,
The (mandatory) ioshost parameter specifies the Cisco router, which will send the DNS requests, 
as well as the SNMP community string on the router.
DOC
			_example => 'RTTcommunity@Myrouter.foobar.com.au',
		},
		name => {
			_doc => "The (mandatory) name parameter is the DNS name to resolve.",
			_example => 'www.foobar.com.au',
		},
        timeout => {
             _re => '\d+', 
             _example => 15,
             _default => $pingtimeout+10,
             _doc => "How long a single RTTMonDNS 'ping' take at maximum plus 10 seconds to spare. Since we control our own timeout the only purpose of this is to not have us killed by the ping method from basefork.",
        },
		iosint => {
			_doc => <<DOC,
The (optional) iosint parameter is the source address for the DNS packets.
This should be one of the active (!) IP addresses of the router to get
results. IOS looks up the target host address in the forwarding table
and then uses the interface(s) listed there to send the DNS packets. By
default IOS uses the (primary) IP address on the sending interface as
source address for packets originated by the router.
DOC
			_example => '10.33.22.11',
		},
	});
}

=head1 
1;

