package Smokeping::probes::DismanPing;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::DismanPing>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::DismanPing>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basevars);
use SNMP_Session "1.13";
use SNMP_util "1.13";
use Smokeping::pingMIB "0.1";
use Socket;
use Net::Domain qw(hostname);

sub pod_hash {
    my $e = "=";
    return {
        name => <<DOC,
Smokeping::probes::DismanPing - DISMAN-PING-MIB Probe for SmokePing
DOC
        description => <<DOC,
Uses the DISMAN-PING-MIB to cause a remote system to send probes.
DOC
        authors => <<DOC,
Bill Fenner <fenner\@research.att.com>,
Tobi Oetiker <tobi\@oetiker.ch>
DOC
        credits => <<DOC,
This structure of this probe module is heavily based on
L<Smokeping::probes::CiscoRTTMonEchoICMP|Smokeping::probes::CiscoRTTMonEchoICMP>
by Joerg.Kummer at Roche.com.
DOC
        notes => <<DOC,
${e}head2 MENU NAMES

This probe uses the menu name of a test as part of the unique
index.  If the menu name is longer than 32 characters, the last
32 characters are used for the index.  Collisions are *B<not>*
detected and simply cause one test's results to be used for
all colliding names.

${e}head2 CONFIGURATION

This probe requires read/write access to the pingCtlTable.  
It also requires read-only access to the pingResultsTable and the
pingHistoryTable.  The DISMAN-PING-MIB is structured such that
it is possible to restrict by pingCtlOwnerIndex.  This probe
uses a pingCtlOwnerIndex of "SP on hostname"
as ownerindex by default; use B<ownerindex> to configure this if needed.

${e}head2 SAMPLE JUNOS CONFIGURATION

This configuration permits the community "pinger" read-write
access to the full DISMAN-PING-MIB, but only when sourced
from the manager at B<192.0.2.134>.

    snmp {
        view pingMIB {
            oid .1.3.6.1.2.1.80 include;
        }
        community pinger {
            view pingMIB;   
            authorization read-write;
            clients {
                192.0.2.134/32;
            }
        }
    }

${e}head2 SAMPLE CONFIGURATIONS NOTE

This configuration allows the "pinger" community full access to the
DISMAN-PING-MIB.  There is information in the description of
B<pingCtlOwnerIndex> in RFC 4560 (L<http://tools.ietf.org/html/rfc4560>)
about using the vacmViewTreeFamilyTable to further restrict access.
The author has not tried this method.
DOC

        #${e}head2 SAMPLE IOS CONFIGURATION
        #
        #Note: I have no clue if IOS supports DISMAN-PING-MIB.
        #
        #    access-list 2 permit 192.0.2.134
        #    snmp-server view pingMIB .1.3.6.1.2.1.80 included
        #    snmp-server community pinger view pingMIB RW 2
        #
    };
}

sub probevars {
    my $class = shift;

    # This is structured a little differently than the
    # average probe.  _makevars prefers values from the
    # first argument, but we have to override the superclass's
    # pings value.  So, we put our values in the first argument.
    # However, _makevars modifies its second argument, and we
    # don't want to modify the superclass's value, so we
    # make a copy in $tmp.
    my $tmp = { %{ $class->SUPER::probevars } };
    return $class->_makevars(
        {
            pings => {
                _re      => '\d+',
                _default => 15,
                _example => 15,
                _sub     => sub {
                    my $val = shift;
                    return
                        "ERROR: for DismanPing, pings must be between 1 and 15."
                        unless $val >= 1 and $val <= 15;
                    return undef;
                },
                _doc => <<DOC,
How many pings should be sent to each target. Note that the maximum value
for DismanPing MIP is 15, which is less than the SmokePing default, so this
class has its own default value.  If your Database section specifies a
value less than 15, you must also set it for this probe.
Note that the number of pings in
the RRD files is fixed when they are originally generated, and if you
change this parameter afterwards, you'll have to delete the old RRD
files or somehow convert them.
DOC
            },
        },
        $tmp
    );
}

sub targetvars {
    my $class = shift;
    return $class->_makevars(
        $class->SUPER::targetvars,
        {
            _mandatory => ['pinghost'],
            ownerindex => {
                _doc => <<DOC,
The SNMP OwnerIndex to use when setting up the test.
When using VACM, can map to a Security Name or Group Name
of the entity running the test.

By default this will be set to

DOC
                _example => "smokeping"
            },
            pinghost => {
                _example => 'pinger@router.example.com',
                _doc     => <<DOC,
The (mandatory) pinghost parameter specifies the remote system which will
execute the pings, as well as the SNMP community string on the device.
DOC
            },
            pingsrc => {
                _example => '192.0.2.9',
                _doc     => <<DOC,
The (optional) pingsrc parameter specifies the source address to be used
for pings.  If specified, this parameter must identify an IP address
assigned to pinghost.
DOC
            },

        #                tos => {
        #                        _example => 160,
        #                        _default => 0,
        #                        _doc => <<DOC,
        #The (optional) tos parameter specifies the value of the ToS byte in
        #the IP header of the pings. Multiply DSCP values times 4 and Precedence
        #values times 32 to calculate the ToS values to configure, e.g. ToS 160
        #corresponds to a DSCP value 40 and a Precedence value of 5.
        #DOC
        #                },
            packetsize => {
                _doc => <<DOC,
The packetsize parameter lets you configure the packet size for the pings
sent. The minimum is 8, the maximum 65507. Use the same number as with
fping if you want the same packet sizes being used on the network.
DOC
                _default => 56,
                _re      => '\d+',
                _sub     => sub {
                    my $val = shift;
                    return "ERROR: packetsize must be between 8 and 65507"
                        unless $val >= 8 and $val <= 65507;
                    return undef;
                    }
            },
        }
    );
}

# XXX
# This is copied from basefork.pm; it actually belongs
# in basevars.pm.
sub pod_variables {
    my $class      = shift;
    my $pod        = $class->SUPER::pod_variables;
    my $targetvars = $class->targetvars;
    $pod .= "Supported target-specific variables:\n\n";
    $pod .= $class->_pod_variables($targetvars);
    return $pod;
}

sub new($$$) {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new(@_);

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {

        # Initialization stuff that might take time
    }
    return $self;
}

sub ProbeDesc($) {
    my $self = shift;
    my $bytes = $self->{properties}{packetsize} || 56;
    return "DISMAN ICMP Echo Pings ($bytes Bytes)";
}

# RFC 4560:
#        A single SNMP PDU can be used to create and start a remote
#   ping test.  Within the PDU, pingCtlTargetAddress should be set to the
#   target host's address (pingCtlTargetAddressType will default to
#   ipv4(1)), pingCtlAdminStatus to enabled(1), and pingCtlRowStatus to
#   createAndGo(4).
#
# At least one implementation doesn't implement a default for
# pingCtlTargetAddressType (and the MIB itself doesn't specify
# such a default)
#
# Philosophically, I'd like to just leave the row there and
# re-enable the test if the row is there - but there's no easy
# way to verify that the values haven't changed since the last
# time we set it.
sub ping($) {
    my $self    = shift;
    my $pending = {};
    my $longest = 0;
    my $start   = time;

    # Empty out any RTTs from the last round.  Otherwise, if we get an
    # SNMP error for a target, we'll report his last result.
    $self->{rtts} = {};

    foreach my $t ( @{ $self->targets } ) {
        my $addr = $t->{addr};
        my $idx  = idx($t);
        my $host = host($t);

        # Delete any existing row.  Ignore error.
        #Smokeping::do_log("DismanPing deleting for $host $t->{vars}{menu}");
        my $ret =
            snmpset( $host, "pingCtlRowStatus.$idx", "integer", 6 );   #destroy

        if ( !defined($ret) ) {
            my ( $err ) = ( $SNMP_Session::errmsg =~ /error status: (\S+)/ );
            my $msgmap = {
                'notWritable' => 'does the remote support DISMAN-PING-MIB?',
                'inconsistentValue' => 'is an old ping running?',
                'noAccess' => 'is access control set up properly?'
            };
            if ( !defined( $err ) ) {
                # errmsg can have arbitrary text on the first line.
                $err = "SNMP error";
            }
            # SNMP::Sesison already carp()d errmsg, so don't include it here.
            # It's already in the log.
            Smokeping::do_log( "DismanPing: got $err trying to clean up $t->{vars}{host}" .
                        ( $msgmap->{ $err } ? " -- " . $msgmap->{ $err } : "" ) );
            next;
        }

        my $targetaddr = inet_aton($addr);
        if ( not defined $targetaddr ) {
            Smokeping::do_log("DismanPing can't resolve destination address $addr for $t->{vars}{host}");
            next;
        }

        #XXX consider ipv6 - esp. what does inet_aton() return
        #XXX todo: test failure handling code by setting ProbeCOunt and MaxRows
        #  differently than pings
        my @values = (
            "pingCtlTargetAddressType.$idx", "integer",     1,             #ipv4
            "pingCtlTargetAddress.$idx",     "octetstring", $targetaddr,
            "pingCtlFrequency.$idx",   "gauge",   0,                # run test only once
            "pingCtlTimeOut.$idx",     "gauge",   3,                # timeout ping after 3 seconds (this is also the interval for sending pings)
            "pingCtlProbeCount.$idx",  "gauge",   $t->{vars}{pings},
            "pingCtlMaxRows.$idx",     "gauge",   $t->{vars}{pings},
            "pingCtlAdminStatus.$idx", "integer", 1,                #enabled
            "pingCtlRowStatus.$idx",   "integer", 4,                #createAndGo
        );

        # add pingsrc, packetsize into @values if defined
        if ( defined  $t->{vars}{packetsize} ) {
            unshift( @values,
                "pingCtlDataSize.$idx", "gauge", $t->{vars}{packetsize} );
        }
        if ( defined  $t->{vars}{pingsrc} ) {
            my $srcaddr = inet_aton( $t->{vars}{pingsrc} );
            if ( not defined $srcaddr ) {
                Smokeping::do_log("WARNING: DismanPing can't resolve source address $t->{vars}{pingsrc} for $t->{vars}{host}");
            }
            else {
                unshift(
                    @values,
                    "pingCtlSourceAddressType.$idx", "integer", 1,    #ipv4
                    "pingCtlSourceAddress.$idx", "octetstring", $srcaddr
                );
            }
        }

        # Todo: pingCtlDSField.
        # Todo: pingCtlTimeout.
        my @snmpsetret;
        if ( ( @snmpsetret = snmpset( $host, @values ) )
            and defined $snmpsetret[0] ) {
            $pending->{ $t->{tree} } = 1;
        }
        else {
            Smokeping::do_log( "ERROR: DismanPing row creation failed for $t->{vars}{host} on $t->{vars}{pinghost}: $SNMP_Session::errmsg" );
        }
        my $timeout = 3;    # XXX DEFVAL for pingCtlTimeOut
        my $length = $t->{vars}{pings} * $timeout;
        if ( $length > $longest ) {
            $longest = $length;
        }
    }
    my $setup = time - $start;
    Smokeping::do_debuglog(
        "DismanPing took $setup s to set up, now sleeping for $longest s");
    sleep($longest);
    my $allok    = 0;
    my $startend = time;
    while ( !$allok ) {
        $allok = 1;
        foreach my $t ( @{ $self->targets } ) {
            next unless ( $pending->{ $t->{tree} } );
            my $idx  = idx($t);
            my $host = host($t);

            # check if it's done - pingResultsOperStatus != 1
            my $status = snmpget( $host, "pingResultsOperStatus.$idx" );
            if ( not defined $status or $status == 1 ) {
                # if SNMP fails, assume it's not done.
                my $howlong = time - $start;
                if ( $howlong > $self->step ) {
                    Smokeping::do_log( "DismanPing: abandoning $t->{vars}{host} after $howlong seconds" );
                    $pending->{ $t->{tree} } = 0;
                }
                else {
                    Smokeping::do_log( "DismanPing: $t->{vars}{host} is still running after $howlong seconds" );
                    $allok = 0;
                }
                next;
            }
            # if so, get results from History Table
            my @times = ();

            # TODO: log message if you have a bad status other than TimedOut
            my $ret = snmpmaptable(
                $host,
                sub() {
                    my ( $index, $rtt, $status ) = @_;
                    push @times, [ sprintf( "%.10e", $rtt / 1000 ), $status ];
                },
                "pingProbeHistoryResponse.$idx",
                "pingProbeHistoryStatus.$idx"
            );
            Smokeping::do_debuglog( "DismanPing: table download returned "
                    . ( defined($ret) ? $ret : "undef" ) );
            
            # Make sure we have exactly pings results.
            # Fewer are probably an implementation problem (we asked for
            #  15, it said the test was done, but didn't return 15).
            # More are a less-bad implementation problem - we can keep
            #  the last 15.
            if ( @times < $t->{vars}{pings} ) {
                Smokeping::do_log( "DismanPing: $t->{vars}{host} only returned "
                        . scalar(@times)
                        . " results" );
                @times = ();
            }
            elsif ( @times > $t->{vars}{pings} ) {
                Smokeping::do_log( "DismanPing: $t->{vars}{host} returned "
                        . scalar(@times)
                        . " results, taking last $t->{vars}{pings}" );
                @times = @times[ $#times - $t->{vars}{pings} .. $#times ];
            }
            
            if (@times) {
                my (@goodtimes) = ();
                foreach my $result (@times) {
                    push( @goodtimes, $result->[0] )
                        if ( $result->[1] == 1 );    # responseReceived(1)
                }
                $self->{rtts}{ $t->{tree} } = [ sort { $a <=> $b } @goodtimes ];
            }
            $pending->{ $t->{tree} } = 0;
        }
        sleep 5 unless ($allok);
    }
    my $howlong = time - $start;
    my $endtime = time - $startend;
    Smokeping::do_debuglog( "DismanPing took $howlong total, $endtime collecting results");
}

# Return index string for this test:
#       INDEX {
#                pingCtlOwnerIndex,
#                pingCtlTestName
#             }
# This is the full index for pingCtlTable and
# pingResultsTable, and the prefix of the index for
# pingProbeHistoryTable.
#
# Uses the last 32 characters of menu name to
# get a unique test name.
sub idx ($) {
    my $t = shift;
    my $ownerindex = substr($t->{vars}{ownerindex} || 'SP on '.hostname(),0,32);
    print STDERR $ownerindex;
    my $testname =  substr($t->{vars}{host} . ' ICMP ping',0,32);
    return join( ".",
        length($ownerindex), unpack( "C*", $ownerindex ),
        length($testname),   unpack( "C*", $testname ) 
    );
}

sub host ($) {
    my $t = shift;
    # gotta be aggressive with the SNMP to keep within
    #  the time budget, so set the timeout to 1 second
    #  and only try twice.
    # hostname:port:timeout:retries:backoff:version
    return $t->{vars}{pinghost} . "::1:2::2";
}

1;
