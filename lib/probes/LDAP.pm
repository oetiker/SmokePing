package probes::LDAP;

=head1 NAME

probes::LDAP - a LDAP probe for SmokePing

=head1 OVERVIEW

Measures LDAP search latency for SmkoePing

=head1 SYNOPSYS

 *** Probes ***
 + LDAP

 passwordfile = /usr/share/smokeping/etc/password # optional
 sleeptime = 0.5 # optional, 1 second by default

 *** Targets ***

 probe = LDAP

 + PROBE_CONF
 port = 389 # optional
 version = 3 # optional
 start_tls = 1 # disabled by default
 timeout = 60 # optional
 
 base = dc=foo,dc=bar # optional
 filter = uid=testuser # the actual search
 attrs = uid,someotherattr
 
 # if binddn isn't present, the LDAP bind is unauthenticated
 binddn = uid=testuser,dc=foo,dc=bar  
 password = mypass # if not present in <passwordfile>
  
=head1 DESCRIPTION

This probe measures LDAP query latency for SmokePing.
The query is specified by the target-specific variable `filter' and,
optionally, by the target-specific variable `base'. The attributes 
queried can be specified in the comma-separated list `attrs'.

The TCP port of the LDAP server and the LDAP version to be used can
be specified by the variables `port' and `version'.

The probe can issue the starttls command to convert the connection
into encrypted mode, if so instructed by the `start_tls' variable.
It can also optionally do an authenticated LDAP bind, if the `binddn'
variable is present. The password to be used can be specified by the
target-specific variable `password' or in an external file.
The location of this file is given in the probe-specific variable
`passwordfile'. See probes::passwordchecker(3pm) for the format
of this file (summary: colon-separated triplets of the form
`<host>:<bind-dn>:<password>')

The probe tries to be nice to the server and sleeps for the probe-specific
variable `sleeptime' (one second by default) between each authentication
request.

=head1 AUTHOR

Niko Tyni E<lt>ntyni@iki.fiE<gt>

=head1 BUGS

There should be a way of specifying TLS options, such as the certificates
involved etc.

The probe has an ugly way of working around the fact that the 
IO::Socket::SSL class complains if start_tls() is done more than once
in the same program. But It Works For Me (tm).

=cut

use strict;
use probes::passwordchecker;
use Net::LDAP;
use Time::HiRes qw(gettimeofday sleep);
use base qw(probes::passwordchecker);
use IO::Socket::SSL;

sub ProbeDesc {
	return "LDAP queries";
}

sub new {
	my $proto = shift;
        my $class = ref($proto) || $proto;
        my $self = $class->SUPER::new(@_);

	my $sleeptime = $self->{properties}{sleeptime};
        $sleeptime = 1 unless defined $sleeptime;
        $self->sleeptime($sleeptime);

	return $self;
}

sub sleeptime {
        my $self = shift;
        my $newval = shift;
        
        $self->{sleeptime} = $newval if defined $newval;
        return $self->{sleeptime};
}


sub pingone {
	my $self = shift;
	my $target = shift;
	my $host = $target->{addr};
	my $vars = $target->{vars};

	my $version = $vars->{version} || 3;
	my $port = $vars->{port};

	my $binddn = $vars->{binddn};

	my $timeout = $vars->{timeout};

	my $password = $vars->{password} || $self->password($host, $binddn) if defined $binddn;

	my $start_tls = $vars->{start_tls};

	my $filter = $vars->{filter};

	my $base = $vars->{base};

	my $attrs = $vars->{attrs};

	my @attrs = split(/,/, $attrs);

	my @times;
	
	for (1..$self->pings($target)) {
		local $IO::Socket::SSL::SSL_Context_obj; # ugly but necessary
		sleep $self->sleeptime unless $_ == 1; # be nice
		my $start = gettimeofday();
		my $ldap = new Net::LDAP($host, port => $port, version => $version, timeout => $timeout) 
			or do {
				$self->do_log("connection error on $host: $!");
				next;
			};
		my $mesg;
		if ($start_tls) {
			$mesg = $ldap->start_tls;
			$mesg->code and do {
				$self->do_log("start_tls error on $host: " . $mesg->error);
				$ldap->unbind;
				next;
			}
		}
		if (defined $binddn and defined $password) {
			$mesg = $ldap->bind($binddn, password => $password);
		} else {
			if (defined $binddn and not defined $password) {
				$self->do_debug("No password specified for $binddn, doing anonymous bind instead");
			}
			$mesg = $ldap->bind();
		}
		$mesg->code and do {
			$self->do_log("bind error on $host: " . $mesg->error);
			$ldap->unbind;
			next;
		};
		$mesg = $ldap->search(base => $base, filter => $filter, attrs => [ @attrs ]);
		$mesg->code and do {
			$self->do_log("filter error on $host: " . $mesg->error);
			$ldap->unbind;
			next;
		};
		$ldap->unbind;
		my $end = gettimeofday();
		my $elapsed = $end - $start;

		$self->do_debug("$host: LDAP query $_ took $elapsed seconds");

		push @times, $elapsed;
	}
	return sort { $a <=> $b } @times;
}


1;
