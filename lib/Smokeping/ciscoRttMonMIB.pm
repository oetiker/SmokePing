#
#
# a few variable definitions to use ciscoRttMonMIB
#
# Joerg Kummer, 10/9/03
#

package Smokeping::ciscoRttMonMIB;

require 5.004;

use vars qw($VERSION);
use Exporter;

use BER;
use SNMP_Session;
use SNMP_util "0.89";

$VERSION = '0.2';

@ISA = qw(Exporter);

sub version () { $VERSION; };

snmpmapOID("rttMonApplVersion", 		"1.3.6.1.4.1.9.9.42.1.1.1.0");
snmpmapOID("rttMonApplSupportedRttTypesValid", 	"1.3.6.1.4.1.9.9.42.1.1.7.1.2");

# generic variables for all measurement types
# cisco(9).ciscoMgmt(9).ciscoRttMonMIB(42).ciscoRttMonObjects(1).rttMonCtrl(2).rttMonCtrlAdminTable(1).rttMonCtrlAdminEntry(1)
snmpmapOID("rttMonCtrlAdminIndex", 		"1.3.6.1.4.1.9.9.42.1.2.1.1.1");
snmpmapOID("rttMonCtrlAdminOwner", 		"1.3.6.1.4.1.9.9.42.1.2.1.1.2");
snmpmapOID("rttMonCtrlAdminTag", 		"1.3.6.1.4.1.9.9.42.1.2.1.1.3");
snmpmapOID("rttMonCtrlAdminRttType", 		"1.3.6.1.4.1.9.9.42.1.2.1.1.4");
snmpmapOID("rttMonCtrlAdminThreshold", 		"1.3.6.1.4.1.9.9.42.1.2.1.1.5");
snmpmapOID("rttMonCtrlAdminFrequency", 		"1.3.6.1.4.1.9.9.42.1.2.1.1.6");
snmpmapOID("rttMonCtrlAdminTimeout", 		"1.3.6.1.4.1.9.9.42.1.2.1.1.7");
snmpmapOID("rttMonCtrlAdminVerifyData",		"1.3.6.1.4.1.9.9.42.1.2.1.1.8");
snmpmapOID("rttMonCtrlAdminStatus", 		"1.3.6.1.4.1.9.9.42.1.2.1.1.9");
snmpmapOID("rttMonCtrlAdminNvgen", 		"1.3.6.1.4.1.9.9.42.1.2.1.1.10");


#1. For echo, pathEcho and dlsw operations 
# cisco(9).ciscoMgmt(9).ciscoRttMonMIB(42).ciscoRttMonObjects(1).rttMonCtrl(2).rttMonEchoAdminTable(2).rttMonEchoAdminEntry (1)
snmpmapOID("rttMonEchoAdminProtocol",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.1");
snmpmapOID("rttMonEchoAdminTargetAddress",      	"1.3.6.1.4.1.9.9.42.1.2.2.1.2");
snmpmapOID("rttMonEchoAdminPktDataRequestSize",		"1.3.6.1.4.1.9.9.42.1.2.2.1.3");
snmpmapOID("rttMonEchoAdminPktDataResponseSize",	"1.3.6.1.4.1.9.9.42.1.2.2.1.4");
snmpmapOID("rttMonEchoAdminTargetPort",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.5");
snmpmapOID("rttMonEchoAdminSourceAddress",      	"1.3.6.1.4.1.9.9.42.1.2.2.1.6");
snmpmapOID("rttMonEchoAdminSourcePort",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.7");
snmpmapOID("rttMonEchoAdminControlEnable",      	"1.3.6.1.4.1.9.9.42.1.2.2.1.8");
snmpmapOID("rttMonEchoAdminTOS",      			"1.3.6.1.4.1.9.9.42.1.2.2.1.9");
snmpmapOID("rttMonEchoAdminLSREnable",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.10");
snmpmapOID("rttMonEchoAdminTargetAddressString",      	"1.3.6.1.4.1.9.9.42.1.2.2.1.11");
snmpmapOID("rttMonEchoAdminNameServer",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.12");
snmpmapOID("rttMonEchoAdminOperation",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.13");
snmpmapOID("rttMonEchoAdminHTTPVersion",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.14");
snmpmapOID("rttMonEchoAdminURL",      			"1.3.6.1.4.1.9.9.42.1.2.2.1.15");
snmpmapOID("rttMonEchoAdminCache",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.16");
snmpmapOID("rttMonEchoAdminInterval",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.17");
snmpmapOID("rttMonEchoAdminNumPackets",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.18");
snmpmapOID("rttMonEchoAdminProxy",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.19");
snmpmapOID("rttMonEchoAdminString1",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.20");
snmpmapOID("rttMonEchoAdminString2",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.21");
snmpmapOID("rttMonEchoAdminString3",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.22");
snmpmapOID("rttMonEchoAdminString4",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.231");
snmpmapOID("rttMonEchoAdminString5",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.24");
snmpmapOID("rttMonEchoAdminMode",      			"1.3.6.1.4.1.9.9.42.1.2.2.1.25");
snmpmapOID("rttMonEchoAdminVrfName",      		"1.3.6.1.4.1.9.9.42.1.2.2.1.26");

# cisco(9).ciscoMgmt(9).ciscoRttMonMIB(42).ciscoRttMonObjects(1).rttMonCtrl(2).rttMonScheduleAdminTable(5).rttMonScheduleAdminEntry(1)
snmpmapOID("rttMonScheduleAdminRttLife",      		"1.3.6.1.4.1.9.9.42.1.2.5.1.1");
snmpmapOID("rttMonScheduleAdminRttStartTime",		"1.3.6.1.4.1.9.9.42.1.2.5.1.2");
snmpmapOID("rttMonScheduleAdminConceptRowAgeout",   	"1.3.6.1.4.1.9.9.42.1.2.5.1.3");

# cisco(9).ciscoMgmt(9).ciscoRttMonMIB(42).ciscoRttMonObjects(1).rttMonCtrl(2).rttMonScheduleAdminTable(5).rttMonScheduleAdminEntry(1)
snmpmapOID("rttMonScheduleAdminRttLife",      		"1.3.6.1.4.1.9.9.42.1.2.5.1.1");


#  cisco(9).ciscoMgmt(9).ciscoRttMonMIB(42).ciscoRttMonObjects(1).rttMonCtrl(2).rttMonHistoryAdminTable(8).rttMonHistoryAdminEntry(1)
snmpmapOID("rttMonHistoryAdminNumLives",      		"1.3.6.1.4.1.9.9.42.1.2.8.1.1");
snmpmapOID("rttMonHistoryAdminNumBuckets",      	"1.3.6.1.4.1.9.9.42.1.2.8.1.2");
snmpmapOID("rttMonHistoryAdminNumSamples",      	"1.3.6.1.4.1.9.9.42.1.2.8.1.3");
snmpmapOID("rttMonHistoryAdminFilter",      		"1.3.6.1.4.1.9.9.42.1.2.8.1.4");

snmpmapOID("rttMonCtrlOperConnectionLostOccurred",	"1.3.6.1.4.1.9.9.42.1.2.9.1.5");
snmpmapOID("rttMonCtrlOperTimeoutOccurred",		"1.3.6.1.4.1.9.9.42.1.2.9.1.6");
snmpmapOID("rttMonCtrlOperOverThresholdOccurred",	"1.3.6.1.4.1.9.9.42.1.2.9.1.7");
snmpmapOID("rttMonCtrlOperNumRtts",			"1.3.6.1.4.1.9.9.42.1.2.9.1.8");
snmpmapOID("rttMonCtrlOperRttLife",			"1.3.6.1.4.1.9.9.42.1.2.9.1.9");
snmpmapOID("rttMonCtrlOperState",			"1.3.6.1.4.1.9.9.42.1.2.9.1.10");
snmpmapOID("rttMonCtrlOperVerifyErrorOccurred",		"1.3.6.1.4.1.9.9.42.1.2.9.1.11");

# cisco(9).ciscoMgmt(9).ciscoRttMonMIB(42).ciscoRttMonObjects(1).rttMonHistory(4).rttMonHistoryCollectionTable(1).rttMonHistoryCollectionEntry(1)
snmpmapOID("rttMonStatisticsAdminNumPaths",	"1.3.6.1.4.1.9.9.42.1.2.7.1.2");
snmpmapOID("rttMonStatisticsAdminNumHops",	"1.3.6.1.4.1.9.9.42.1.2.7.1.3");

# cisco(9).ciscoMgmt(9).ciscoRttMonMIB(42).ciscoRttMonObjects(1).rttMonHistory(4).rttMonHistoryCollectionTable(1).rttMonHistoryCollectionEntry(1)
snmpmapOID("rttMonHistoryCollectionLifeIndex",		"1.3.6.1.4.1.9.9.42.1.4.1.1.1");
snmpmapOID("rttMonHistoryCollectionBucketIndex",	"1.3.6.1.4.1.9.9.42.1.4.1.1.2");
snmpmapOID("rttMonHistoryCollectionSampleIndex",	"1.3.6.1.4.1.9.9.42.1.4.1.1.3");
snmpmapOID("rttMonHistoryCollectionSampleTime",		"1.3.6.1.4.1.9.9.42.1.4.1.1.4");
snmpmapOID("rttMonHistoryCollectionAddress",		"1.3.6.1.4.1.9.9.42.1.4.1.1.5");
snmpmapOID("rttMonHistoryCollectionCompletionTime",	"1.3.6.1.4.1.9.9.42.1.4.1.1.6");
snmpmapOID("rttMonHistoryCollectionSense",		"1.3.6.1.4.1.9.9.42.1.4.1.1.7");
snmpmapOID("rttMonHistoryCollectionApplSpecificSense",	"1.3.6.1.4.1.9.9.42.1.4.1.1.8");
snmpmapOID("rttMonHistoryCollectionSenseDescription",	"1.3.6.1.4.1.9.9.42.1.4.1.1.9");


# return 1 to indicate that all is ok..
1;
