# -*- perl -*-
package Smokeping::Examples;
use strict;
use Smokeping;

=head1 NAME

Smokeping::Examples - A module for generating the smokeping_examples document

=head1 OVERVIEW

This module generates L<smokeping_examples> and the example
configuration files distributed with Smokeping. It is supposed to be
invoked from the smokeping distribution top directory, as it will need
the C<etc/config.dist> template configuration file and will create files
in the directories C<doc> and C<doc/examples>.

=head1 DESCRIPTION

The entry point to the module is the C<make> subroutine. It takes one optional
parameter, C<check>, that makes the module run a syntax check for all the
created example configuration files.

=head1 BUGS

This module uses more or less internal functions from L<Smokeping.pm|Smokeping>. It's a 
separate module only because the latter is much too big already.

It should be possible to include POD markup in the configuration explanations
and have this module filter them away for the config files.

It might be nice for the probe module authors to be able to provide an
example configuration as part of the probe module instead of having to
modify Smokeping::Examples too.

=head1 COPYRIGHT

Copyright 2005 by Niko Tyni.

=head1 LICENSE

This program is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.  See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public
License along with this program; if not, write to the Free
Software Foundation, Inc., 675 Mass Ave, Cambridge, MA
02139, USA.

=head1 AUTHOR

Niko Tyni <ntyni@iki.fi>

=cut

use strict;

sub read_config_template {
	my $file = "../etc/config.dist";
	my $h = {
		common => "", # everything up to the Probes section
		probes => "",   # the Probes section, without the *** Probes *** line
		targets => "",   # the Targets section, without the *** Targets *** line
	};
	open(F, "<$file") or die("open template configuration file $file for reading: $!");
	my %found;
	while (<F>) {
		/\*\*\*\s*(Probes|Targets)\s*\*\*\*/ and $found{$1} = 1, next;
		$h->{common}   .= $_ and next unless $found{Probes};
		$h->{probes}   .= $_ and next unless $found{Targets};
		$h->{targets}  .= $_;
	}
	close F;
	return $h;
}

sub prologue {
	my $e = "=";
	return <<DOC;
${e}head1 NAME

smokeping_examples - Examples of Smokeping configuration

${e}head1 OVERVIEW

This document provides some examples of Smokeping configuration files.
All the examples can be found in the C<examples> directory in the
Smokeping documentation. Note that the DNS names in the examples are
non-functional.

Details of the syntax and all the variables are found in 
L<smokeping_config> and in the documentation of the
corresponding probe, if applicable.

This manual is automatically generated from the Smokeping source code,
specifically the L<Smokeping::Examples|Smokeping::Examples> module.

${e}head1 DESCRIPTION

Currently the examples differ only in the C<Probes> and C<Targets>
sections. The other sections are taken from the C<etc/config.dist>
configuration template in the Smokeping distribution so that the example
files are complete.

If you would like to provide more examples, document the other sections
or enhance the existing examples, please do so, preferably by sending
the proposed changes to the smokeping-users mailing list.

DOC
}

sub epilogue {
	my $e = "=";
	return <<DOC;

${e}head1 COPYRIGHT

Copyright 2005 by Niko Tyni.

${e}head1 LICENSE

This program is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.  See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public
License along with this program; if not, write to the Free
Software Foundation, Inc., 675 Mass Ave, Cambridge, MA
02139, USA.

${e}head1 AUTHOR

Niko Tyni <ntyni\@iki.fi>

${e}head1 SEE ALSO

The other Smokeping documents, especially L<smokeping_config>.
DOC
}

sub make {
	print "Generating example files...\n";
	my $check = shift; # check the syntax of the generated config files
	my $template = read_config_template();
	my $examples = examples($template);
	my $manual = prologue();
	for my $ex (sort { $examples->{$a}{order} <=> $examples->{$b}{order} } keys %$examples) {
		my $h = $examples->{$ex};
		$manual .= "\n=head2 Example $h->{order}: config.$ex\n\n"
			.   genpod($h);
		my $cfgfile = "examples/config.$ex";
		print "\t$cfgfile ...\n";
		writecfg($cfgfile, $template, $h);
		if ($check) {
			local $Smokeping::cfg = undef;
			eval { 
				Smokeping::verify_cfg($cfgfile);
			};
			die("Syntax check for $cfgfile failed: $@") if $@;
		}
	}
	$manual .= epilogue();
	writemanual($manual);
	print "done.\n";
}

sub writemanual {
	my $text = shift;
	my $filename = "smokeping_examples.pod";
	print "\t$filename ...\n";
	open(F, ">$filename") or die("open $filename for writing: $!");
	print F $text;
	close F;
}

sub genpod {
	my $h = shift;
	my $text = "";
	$text .= "=over\n\n";
	$text .= "=item Probe configuration\n\n";
	$text .= " *** Probes ***\n";
	$text .= join("\n", map { " $_" } split(/\n/, $h->{probes}));
	$text .= "\n\n=item Probe explanation\n\n";
	$text .= $h->{probedoc} || "No probedoc found !";
	$text .= "\n\n=item Target configuration\n\n";
	$text .= " *** Targets ***\n";
	$text .= join("\n", map { " $_" } split(/\n/, $h->{targets}));
	$text .= "\n\n=item Target explanation\n\n";
	$text .= $h->{targetdoc} || "No targetdoc found !";
	$text .= "\n\n=back\n\n";
	return $text;
}

sub writecfg {
	my $file = shift;
	my $template = shift;
	my $h = shift;
	open(F, ">$file") or die("open $file for writing: $!");
	print F <<DOC;
# This Smokeping example configuration file was automatically generated.
#
# Everything up to the Probes section is derived from a common template file.
# See the Probes and Targets sections for the actual example.
#
# This example is included in the smokeping_examples document.

DOC
	print F $template->{common};
	print F "# (The actual example starts here.)\n";
	print F "\n*** Probes ***\n\n";
	print F join("\n", map { "# $_" } split(/\n/, $h->{probedoc} || 'No probedoc found!'));
	print F "\n\n";
	print F $h->{probes};
	print F "\n*** Targets ***\n\n";
	print F join("\n", map { "# $_" } split(/\n/, $h->{targetdoc} || 'No targetdoc found'));
	print F "\n\n";
	print F $h->{targets};
	close F;
}

sub examples {
	my $template = shift;
	return {
		simple => {
			order => 1,
			probes => <<DOC,
+FPing
binary = /usr/bin/fping
DOC
			targets => <<DOC,
probe = FPing

menu = Top
title = Network Latency Grapher
remark = Welcome to this SmokePing website.

+ mysite1
menu = Site 1
title = Hosts in Site 1

++ myhost1
host = myhost1.mysite1.example
++ myhost2
host = myhost2.mysite1.example

+ mysite2
menu = Site 2
title = Hosts in Site 2

++ myhost3
host = myhost3.mysite2.example
++ myhost4
host = myhost4.mysite2.example
DOC
			probedoc => <<DOC,
Here we have just one probe, fping, pinging four hosts. 

The fping probe is using the default parameters, some of them supplied
from the Database section ("step" and "pings"), and some of them by
the probe module.
DOC
			targetdoc => <<DOC,
The hosts are located in two sites of two hosts each, and the
configuration has been divided to site sections ('+') and host subsections
('++') accordingly.
DOC
		}, # simple
		"multiple-probes" => {
			order => 2,
			probes => <<DOC,
+ FPing
binary = /usr/bin/fping
packetsize = 1000

+ DNS
binary = /usr/bin/dig
lookup = name.example
pings = 5
step = 180

+ EchoPingHttp
pings = 5
url = /test-url
DOC
			targets => <<DOC,
probe = FPing
menu = Top
title = Network Latency Grapher
remark = Welcome to this SmokePing website.

+ network
menu = Net latency
title = Network latency (ICMP pings)

++ myhost1
host = myhost1.example
++ myhost2
host = myhost2.example

+ services
menu = Service latency
title = Service latency (DNS, HTTP)

++ DNS
probe = DNS
menu = DNS latency
title = Service latency (DNS)

+++ dns1
host = dns1.example

+++ dns2
host = dns2.example

++ HTTP
menu = HTTP latency
title = Service latency (HTTP)

+++ www1
host = www1.example

+++ www2
host = www2.example
DOC
	probedoc => <<DOC,
Here we have three probes: FPing for the regular ICMP pings,
DNS for name server latency measurement and EchoPingHttp
for web servers.

The FPing probe runs with the default parameters, except that the ICMP
packet size is 1000 bytes instead of the default 56 bytes.

The DNS and EchoPingHttp probes have been configured to be a bit more
gentle with the servers, as they only do 5 queries (pings) instead of the
default 20 (or whatever is specified in the Database section). However,
DNS queries are made more often: 5 queries every 3 minutes instead of
every 5 minutes.
DOC
		targetdoc => <<DOC,
The target tree has been divided by the probe used. This does not have
to be the case: every target (sub)section can use a different probe,
and the same probe can be used in different parts of the config tree.
DOC
	}, # multiple-probes
	"fping-instances" => {
		order => 3,
		probes => <<DOC,
+ FPing
binary = /usr/bin/fping

++ FPingNormal
offset = 0%

++ FPingLarge
packetsize = 5000
offset = 50%
DOC
		probedoc => <<DOC,
This example demonstrates the concept of probe instances. The FPingLarge
and FPingNormal probes are independent of each other, they just use
the same module, FPing. FPingNormal uses the default parameters, and
so does FPingLarge except for the 5 kilobyte packetsize. Both use the
same fping binary, and its path is configured FPing top section. 

The 'offset' parameters make sure the probes don't run at the same time -
FPingNormal is run every 'full' 5 minutes (eg. 8:00, 8:05, 8:10 and so on,
in wallclock time) while FPingLarge is run halfway through these intervals
(eg. 8:02:30, 8:07:30 etc.)

The top FPing section does not define a probe in itself because it
has subsections. If we really wanted to have one probe named "FPing",
we could do so by making a subsection by that name.
DOC
		targets => <<DOC,
probe = FPingNormal
menu = Top
title = Network Latency Grapher
remark = Welcome to this SmokePing website.

+ network
menu = Net latency
title = Network latency (ICMP pings)

++ myhost1
menu = myhost1
title = ICMP latency for myhost1

+++ normal
title = Normal packetsize (56 bytes)
probe = FPingNormal
host = myhost1.example

+++ large
title = Large packetsize (5000 bytes)
probe = FPingLarge
host = myhost1.example

++ myhost2
menu = myhost2
title = ICMP latency for myhost2

+++ normal
title = Normal packetsize (56 bytes)
probe = FPingNormal
host = myhost2.example

+++ large
title = Large packetsize (5000 bytes)
probe = FPingLarge
host = myhost2.example
DOC
		targetdoc => <<DOC,
The target section shows two host, myhost1.example and myhost2.example,
being pinged with two differently sized ICMP packets. This time the tree
is divided by the target host rather than the probe.
DOC
	}, # fping-instances
	"targetvars-with-Curl" => {
		order => 4,
		probes => <<DOC,
+ Curl
# probe-specific variables
binary = /usr/bin/curl
step = 60

# a default for this target-specific variable
urlformat = http://%host%/
DOC
	probedoc => <<DOC,
This example explains the difference between probe- and target-specific
variables. We use the Curl probe for this.

Every probe supports at least some probe-specific variables. The values
of these variables are common to all the targets of the probe, and
they can only be configured in the Probes section. In this case, 
the probe-specific variables are "binary" and "step".

Target-specific variables are supported by most probes, the most notable
exception being the FPing probe and its derivatives. Target-specific
variables can have different values for different targets. They can be
configured in both Probes and Targets sections. The values assigned in the
Probes section function become default values that can be overridden
in the Targets section. 

The documentation of each probe states which of its variables are
probe-specific and which are target-specific.

In this case the "urlformat" variable is a target-specific one.  It is
also quite uncommon, because it can contain a placeholder for the "host"
variable in the Targets section. This is not a general feature, its
usage is only limited to the "urlformat" variable and the "%host%" escape.

(The reason why the FPing probe does not support target-specific variables
is simply the fact that the fping program measures all its targets in one
go, so they all have the same parameters. The other probes ping their targets
one at a time.)
DOC
		targets => <<DOC,
probe = Curl
menu = Top
title = Network Latency Grapher
remark = Welcome to this SmokePing website.

+ HTTP
menu = http
title = HTTP latency 

++ myhost1
menu = myhost1
title = HTTP latency for myhost1
host = myhost1.example

++ myhost2
menu = myhost2
title = HTTP latency for myhost2
host = myhost2.example

++ myhost3
menu = myhost3
title = HTTP latency for myhost3 (port 8080!)
host = myhost3.example
urlformat = http://%host%:8080/

+ FTP
menu = ftp
title = FTP latency
urlformat = ftp://%host%/

++ myhost1
menu = myhost1
title = FTP latency for myhost1
host = myhost1.example

++ myhost2
menu = myhost2
title = FTP latency for myhost2
host = myhost2.example
DOC
	targetdoc => <<DOC,
The target tree is divided into an HTTP branch and an FTP one.
The servers "myhost1.example" and "myhost2.example" are probed
in both. The third server, "myhost3.example", only has an HTTP
server, and it's in a non-standard port (8080).

The "urlformat" variable is specified for the whole FTP branch
as "ftp://%host%/". For the HTTP branch, the default from the
Probes section is used, except for myhost3, which overrides
it to tag the port number into the URL. 

The myhost3 assignment could just as well have included the hostname
verbatim (ie. urlformat = http://myhost3.example:8080/) instead of
using the %host% placeholder, but the host variable would still have
been required (even though it wouldn't have been used for anything).
DOC
	}, # targetvars-with-Curl
	echoping => {
		order => 5,
		probes => <<DOC,
+ FPing
binary = /usr/bin/fping

# these expect to find echoping in /usr/bin
# if not, you'll have to specify the location separately for each probe
# + EchoPing         # uses TCP or UDP echo (port 7)
# + EchoPingDiscard  # uses TCP or UDP discard (port 9)
# + EchoPingChargen  # uses TCP chargen (port 19)
+ EchoPingSmtp       # SMTP (25/tcp) for mail servers
+ EchoPingHttps      # HTTPS (443/tcp) for web servers
+ EchoPingHttp       # HTTP (80/tcp) for web servers and caches
+ EchoPingIcp        # ICP (3130/udp) for caches
# these need at least echoping 6 with the corresponding plugins
+ EchoPingDNS        # DNS (53/udp or tcp) servers
+ EchoPingLDAP       # LDAP (389/tcp) servers
+ EchoPingWhois      # Whois (43/tcp) servers
DOC
		probedoc => <<DOC,
This example shows most of the echoping-derived probes in action.
DOC
		targets => <<DOC,
# default probe
probe = FPing

menu = Top
title = Network Latency Grapher
remark = Welcome to this SmokePing website.

+ MyServers

menu = My Servers
title = My Servers 

++ www-server
menu = www-server
title = Web Server (www-server) / ICMP
# probe = FPing propagated from top
host = www-server.example

+++ http
menu = http
title = Web Server (www-server) / HTTP
probe = EchoPingHttp
host = www-server.example 
# default url is /

+++ https
menu = https
title = Web Server (www-server) / HTTPS
probe = EchoPingHttps
host = www-server.example

++ cache
menu = www-cache
title = Web Cache (www-cache) / ICMP
host = www-cache.example

+++ http
menu = http
title = www-cache / HTTP
probe = EchoPingHttp
host = www-cache.example
port = 8080 # use the squid port
url = http://www.somehost.example/

+++ icp
menu = icp
title = www-cache / ICP
probe = EchoPingIcp
host = www-cache.example
url = http://www.somehost.example/

++ mail
menu = mail-server
title = Mail Server (mail-server) / ICMP
host = mail-server.example

+++ smtp
menu = mail-server / SMTP
title = Mail Server (mail-server) / SMTP
probe = EchoPingSmtp
host = mail-server.example

++ ldap-server
menu = ldap-server
title = ldap-server / ICMP
host = ldap-server.example

+++ ldap
menu = ldap-server / LDAP
title = LDAP Server (ldap-server) / LDAP
probe = EchoPingLDAP
ldap_request = (objectclass=*)
host = ldap-server.example

++ name-server
menu = name-server
title = name-server / ICMP
host = name-server.example

+++ DNS
menu = name-server / DNS
title = DNS Server (name-server) / DNS
probe = EchoPingDNS
dns_request = name.example
host = name-server.example

++ whois-server
menu = whois-server
title = whois-server / ICMP
host = whois-server.example

+++ Whois
menu = whois-server / Whois
title = Whois Server (whois-server) / Whois
probe = EchoPingWhois
whois_request = domain.example
host = whois-server.example
DOC
	targetdoc => <<DOC,
All the servers are pinged both with ICMP (the FPing probe)
and their respective echoping probe. The proxy server, www-cache,
is probed with both HTTP requests and ICP requests for the same
URL.
DOC
	}, # echoping
	template => {
		order => 6, # last
		probes => $template->{probes},
		targets => $template->{targets},
		probedoc => <<DOC,
This is the template configuration file distributed with Smokeping.
It is included in the examples as well for the sake of completeness.
DOC
		targetdoc => <<DOC,
This is the template configuration file distributed with Smokeping.
It is included in the examples as well for the sake of completeness.
DOC
	},
    }; # return
} # sub examples

1;
