package probes::Radius;

=head1 NAME

probes::Radius - a RADIUS authentication probe for SmokePing

=head1 OVERVIEW

Measures RADIUS authentication latency for SmokePing

=head1 SYNOPSYS

 *** Probes ***
 + Radius

 passwordfile = /usr/share/smokeping/etc/password
 secretfile = /etc/raddb/secret
 sleeptime = 0.5 # optional, 1 second by default
 username = test-user     # optional, overridden by target
 password = test-password # optional, overridden by target
 secret   = test-secret   # optional, overridden by target

 *** Targets ***

 probe = Radius

 + PROBE_CONF
 username = testuser
 secret = myRadiusSecret # if not present in <secretfile>
 password = testuserPass # if not present in <passwordfile>
 port = 1645 # optional
 nas_ip_address = 1.2.3.4 # optional

=head1 DESCRIPTION

This probe measures RADIUS (RFC 2865) authentication latency for SmokePing.

The username to be tested is specified in either the probe-specific or the 
target-specific variable `username', with the target-specific one overriding
the probe-specific one.

The password can be specified either (in order of precedence, with the latter
overriding the former) in the probe-specific variable `password', in the 
target-specific variable `password' or in an external file.  The location of
this file is given in the probe-specific variable `passwordfile'. See 
probes::passwordchecker(3pm) for the format of this file (summary: 
colon-separated triplets of the form `<host>:<username>:<password>')

The RADIUS protocol requires a shared secret between the server and the client.
This secret can be specified either (in order of precedence, with the latter
overriding the former) in the probe-specific variable `secret', in the
target-specific variable `secret' or in an external file.
This external file is located by the probe-specific variable `secretfile', and it should
contain whitespace-separated pairs of the form `<host> <secret>'. Comments and blank lines
are OK.

If the optional probe-specific variable `nas_ip_address' is specified, its
value is inserted into the authentication requests as the `NAS-IP-Address'
RADIUS attribute.

The probe tries to be nice to the server and sleeps for the probe-specific
variable `sleeptime' (one second by default) between each authentication
request.

=head1 AUTHOR

Niko Tyni E<lt>ntyni@iki.fiE<gt>

=head1 BUGS

There should be a more general way of specifying RADIUS attributes.

=cut

use strict;
use probes::passwordchecker;
use base qw(probes::passwordchecker);
use Authen::Radius;
use Time::HiRes qw(gettimeofday sleep);
use Carp;

sub ProbeDesc {
	return "RADIUS queries";
}

sub new {
        my $proto = shift;
        my $class = ref($proto) || $proto;
        my $self = $class->SUPER::new(@_);

	# no need for this if we run as a cgi
	unless ($ENV{SERVER_SOFTWARE}) {
	        if (defined $self->{properties}{secretfile}) {
			open(S, "<$self->{properties}{secretfile}") 
				or croak("Error opening specified secret file $self->{properties}{secretfile}: $!");
			while (<S>) {
				chomp;
				next unless /\S/;
				next if /^\s*#/;
				my ($host, $secret) = split;
				carp("Line $. in $self->{properties}{secretfile} is invalid"), next 
					unless defined $host and defined $secret;
				$self->secret($host, $secret);
			}
			close S;
	        }

		my $sleeptime = $self->{properties}{sleeptime};
		$sleeptime = 1 unless defined $sleeptime;
		$self->sleeptime($sleeptime);

	}

        return $self;
}

sub secret {
	my $self = shift;
	my $host = shift;
	my $newval = shift;
	
	$self->{secret}{$host} = $newval if defined $newval;
	return $self->{secret}{$host};
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
	my $username = $vars->{username} || $self->{properties}->{username};
	my $secret = $vars->{secret} || $self->secret($host) || $self->{properties}->{secret};

	$self->do_log("Missing RADIUS secret for $host"), return 
		unless defined $secret;

	$self->do_log("Missing RADIUS username for $host"), return 
		unless defined $username;

	my $password = $vars->{password} || $self->password($host, $username) || $self->{properties}->{password};

	my $port = $vars->{port};
	$host .= ":$port" if defined $port;

	$self->do_log("Missing RADIUS password for $host/$username"), return 
		unless defined $password;

	my @times;
	for (1..$self->pings($target)) {
		my $r = new Authen::Radius(Host => $host, Secret => $secret);
		$r->add_attributes(
			{ Name => 1, Value => $username, Type => 'string' },
			{ Name => 2, Value => $password, Type => 'string' },
		);
		$r->add_attributes( { Name => 4, Type => 'ipaddr', Value => $vars->{nas_ip_address} })
			if exists $vars->{nas_ip_address};
		my $c;
		my $start = gettimeofday();
		$r->send_packet(ACCESS_REQUEST) and $c = $r->recv_packet;
		my $end = gettimeofday();
		my $result;
		if (defined $c) {
			$result = $c;
			$result = "OK" if $c == ACCESS_ACCEPT;
			$result = "fail" if $c == ACCESS_REJECT;
		} else {
			$result = "no reply";
		}
		$self->do_debug("$host: radius query $_: $result, " . ($end - $start));
		push @times, $end - $start if (defined $c and $c == ACCESS_ACCEPT);
		sleep $self->sleeptime; # be nice
	}
	return sort { $a <=> $b } @times;
}

1;
