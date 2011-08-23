#
#
# a few variable definitions to use pingMIB
#
# Bill Fenner, 10/23/06
# Based on ciscoRttMonMIB.pm
#

package Smokeping::pingMIB;

require 5.004;

use vars qw($VERSION);
use Exporter;

use BER;
use SNMP_Session;
use SNMP_util "0.89";

$VERSION = '0.1';

@ISA = qw(Exporter);

sub version () { $VERSION; };

# Scalars:
snmpmapOID("pingMaxConcurrentRequests",      "1.3.6.1.2.1.80.1.1.0");

# pingCtlTable
snmpmapOID("pingCtlOwnerIndex",              "1.3.6.1.2.1.80.1.2.1.1");
snmpmapOID("pingCtlTestName",                "1.3.6.1.2.1.80.1.2.1.2");
snmpmapOID("pingCtlTargetAddressType",       "1.3.6.1.2.1.80.1.2.1.3");
snmpmapOID("pingCtlTargetAddress",           "1.3.6.1.2.1.80.1.2.1.4");
snmpmapOID("pingCtlDataSize",                "1.3.6.1.2.1.80.1.2.1.5");
snmpmapOID("pingCtlTimeOut",                 "1.3.6.1.2.1.80.1.2.1.6");
snmpmapOID("pingCtlProbeCount",              "1.3.6.1.2.1.80.1.2.1.7");
snmpmapOID("pingCtlAdminStatus",             "1.3.6.1.2.1.80.1.2.1.8");
snmpmapOID("pingCtlDataFill",                "1.3.6.1.2.1.80.1.2.1.9");
snmpmapOID("pingCtlFrequency",               "1.3.6.1.2.1.80.1.2.1.10");
snmpmapOID("pingCtlMaxRows",                 "1.3.6.1.2.1.80.1.2.1.11");
snmpmapOID("pingCtlStorageType",             "1.3.6.1.2.1.80.1.2.1.12");
snmpmapOID("pingCtlTrapGeneration",          "1.3.6.1.2.1.80.1.2.1.13");
snmpmapOID("pingCtlTrapProbeFailureFilter",  "1.3.6.1.2.1.80.1.2.1.14");
snmpmapOID("pingCtlTrapTestFailureFilter",   "1.3.6.1.2.1.80.1.2.1.15");
snmpmapOID("pingCtlType",                    "1.3.6.1.2.1.80.1.2.1.16");
snmpmapOID("pingCtlDescr",                   "1.3.6.1.2.1.80.1.2.1.17");
snmpmapOID("pingCtlSourceAddressType",       "1.3.6.1.2.1.80.1.2.1.18");
snmpmapOID("pingCtlSourceAddress",           "1.3.6.1.2.1.80.1.2.1.19");
snmpmapOID("pingCtlIfIndex",                 "1.3.6.1.2.1.80.1.2.1.20");
snmpmapOID("pingCtlByPassRouteTable",        "1.3.6.1.2.1.80.1.2.1.21");
snmpmapOID("pingCtlDSField",                 "1.3.6.1.2.1.80.1.2.1.22");
snmpmapOID("pingCtlRowStatus",               "1.3.6.1.2.1.80.1.2.1.23");

# pingResultsTable
snmpmapOID("pingResultsOperStatus",          "1.3.6.1.2.1.80.1.3.1.1");
snmpmapOID("pingResultsIpTargetAddressType", "1.3.6.1.2.1.80.1.3.1.2");
snmpmapOID("pingResultsIpTargetAddress",     "1.3.6.1.2.1.80.1.3.1.3");
snmpmapOID("pingResultsMinRtt",              "1.3.6.1.2.1.80.1.3.1.4");
snmpmapOID("pingResultsMaxRtt",              "1.3.6.1.2.1.80.1.3.1.5");
snmpmapOID("pingResultsAverageRtt",          "1.3.6.1.2.1.80.1.3.1.6");
snmpmapOID("pingResultsProbeResponses",      "1.3.6.1.2.1.80.1.3.1.7");
snmpmapOID("pingResultsSentProbes",          "1.3.6.1.2.1.80.1.3.1.8");
snmpmapOID("pingResultsRttSumOfSquares",     "1.3.6.1.2.1.80.1.3.1.9");
snmpmapOID("pingResultsLastGoodProbe",       "1.3.6.1.2.1.80.1.3.1.10");

# pingProbeHistoryTable
snmpmapOID("pingProbeHistoryIndex",          "1.3.6.1.2.1.80.1.4.1.1");
snmpmapOID("pingProbeHistoryResponse",       "1.3.6.1.2.1.80.1.4.1.2");
snmpmapOID("pingProbeHistoryStatus",         "1.3.6.1.2.1.80.1.4.1.3");
snmpmapOID("pingProbeHistoryLastRC",         "1.3.6.1.2.1.80.1.4.1.4");
snmpmapOID("pingProbeHistoryTime",           "1.3.6.1.2.1.80.1.4.1.5");

# pingImplementationTypeDomains - if we end up supporting other ping types
snmpmapOID("pingIcmpEcho",                   "1.3.6.1.2.1.80.3.1");
snmpmapOID("pingUdpEcho",                    "1.3.6.1.2.1.80.3.2");
snmpmapOID("pingSnmpQuery",                  "1.3.6.1.2.1.80.3.3");
snmpmapOID("pingTcpConnectionAttempt",       "1.3.6.1.2.1.80.3.4");

# return 1 to indicate that all is ok..
1;
