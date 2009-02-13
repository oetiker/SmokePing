package Smokeping::probes::Radius;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::Radius>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::Radius>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::passwordchecker);
use Authen::Radius;
use Time::HiRes qw(gettimeofday sleep);
use Carp;

my $DEFAULTINTERVAL = 1;

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::Radius - a RADIUS authentication probe for SmokePing
DOC
		overview => <<DOC,
Measures RADIUS authentication latency for SmokePing
DOC
		description => <<DOC,
This probe measures RADIUS (RFC 2865) authentication latency for SmokePing.

The username to be tested is specified in either the probe-specific or the 
target-specific variable `username', with the target-specific one overriding
the probe-specific one.

The password can be specified either (in order of precedence, with
the latter overriding the former) in the probe-specific variable
`password', in an external file or in the target-specific variable
`password'.  The location of this file is given in the probe-specific
variable `passwordfile'. See Smokeping::probes::passwordchecker(3pm) for the
format of this file (summary: colon-separated triplets of the form
`<host>:<username>:<password>')

The RADIUS protocol requires a shared secret between the server and the client.
This secret can be specified either (in order of precedence, with the latter
overriding the former) in the probe-specific variable `secret', in an external file
or in the target-specific variable `secret'.
This external file is located by the probe-specific variable `secretfile', and it should
contain whitespace-separated pairs of the form `<host> <secret>'. Comments and blank lines
are OK.

If the optional probe-specific variable `nas_ip_address' is specified, its
value is inserted into the authentication requests as the `NAS-IP-Address'
RADIUS attribute.

The probe tries to be nice to the server and does not send authentication
requests more frequently than once every X seconds, where X is the value
of the target-specific "min_interval" variable ($DEFAULTINTERVAL by default).
DOC
		authors => <<'DOC',
Niko Tyni <ntyni@iki.fi>
DOC
		bugs => <<DOC,
There should be a more general way of specifying RADIUS attributes.
DOC
	}
}

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
                        my @stat = stat($self->{properties}{secretfile});
                        my $mode = $stat[2];
                        carp("Warning: secret file $self->{properties}{secretfile} is world-readable\n") 
                                if defined $mode and $mode & 04;
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

sub pingone {
	my $self = shift;
	my $target = shift;
	my $host = $target->{addr};
	my $vars = $target->{vars};
	my $mininterval = $vars->{mininterval};
	my $username = $vars->{username};
	my $secret = $self->secret($host);
	if (defined $vars->{secret} and 
	    $vars->{secret} ne ($self->{properties}{secret}||"")) {
		$secret = $vars->{secret};
	}
	$secret ||= $self->{properties}{secret};

	my $timeout = $vars->{timeout};

       my $allowreject = $vars->{allowreject};
       $self->do_debug("$host: radius allowreject is $allowreject");
       $allowreject=(defined($allowreject)
               and $allowreject eq "true");

	$self->do_log("Missing RADIUS secret for $host"), return 
		unless defined $secret;

	$self->do_log("Missing RADIUS username for $host"), return 
		unless defined $username;

	my $password = $self->password($host, $username);
	if (defined $vars->{password} and
	    $vars->{password} ne ($self->{properties}{password}||"")) {
	    	$password = $vars->{password};
	}
	$password ||= $self->{properties}{password};

	$self->do_log("Missing RADIUS password for $host/$username"), return 
		unless defined $password;

	my $port = $vars->{port};
	$host .= ":$port" if defined $port;

	my @times;
	my $elapsed;
	for (1..$self->pings($target)) {
		if (defined $elapsed) {
			my $timeleft = $mininterval - $elapsed;
			sleep $timeleft if $timeleft > 0;
		}
		my $r = new Authen::Radius(Host => $host, Secret => $secret, TimeOut => $timeout);
		$r->add_attributes(
			{ Name => 1, Value => $username, Type => 'string' },
			{ Name => 2, Value => $password, Type => 'string' },
		);
		$r->add_attributes( { Name => 4, Type => 'ipaddr', Value => $vars->{nas_ip_address} })
			if exists $vars->{nas_ip_address};
		my $c;
		my $start = gettimeofday();
		$r->send_packet(&ACCESS_REQUEST) and $c = $r->recv_packet;
		my $end = gettimeofday();
		my $result;
		if (defined $c) {
			$result = $c;
			$result = "OK" if $c == &ACCESS_ACCEPT;
			$result = "fail" if $c == &ACCESS_REJECT;
                       $result = "fail-OK" if $c == &ACCESS_REJECT and $allowreject;
		} else {
			if (defined $r->get_error) {
				$result = "error: " . $r->strerror;
			} else {
				$result = "no reply";
			}
		}
		$elapsed = $end - $start;
		$self->do_debug("$host: radius query $_: $result, $elapsed");
               if (defined $c) {
                       if ( $c == &ACCESS_ACCEPT or
                               ($c == &ACCESS_REJECT and $allowreject) ) {
                               push @times, $elapsed;
                       }
               }
	}
	return sort { $a <=> $b } @times;
}

sub probevars {
	my $class = shift;
	my $h = $class->SUPER::probevars;
	delete $h->{timeout};
	return $class->_makevars($h, {
		secretfile => {
			_doc => <<DOC,
A file containing the RADIUS shared secrets for the targets. It should contain
whitespace-separated pairs of the form `<host> <secret>'. Comments and blank lines
are OK.
DOC
			_example => '/another/place/secret',
			_sub => sub {
				my $val = shift;
				-r $val or return "ERROR: secret file $val is not readable.";
				return undef;
			},
		},
	});
}
		
sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		_mandatory => [ 'username' ],
		username => {
			_doc => 'The username to be tested.',
			_example => 'test-user',
		},
		password => {
			_doc => 'The password for the user, if not present in the password file.',
			_example => 'test-password',
		},
		secret => {
			_doc => 'The RADIUS shared secret for the target, if not present in the secrets file.',
			_example => 'test-secret',
		},
		nas_ip_address => {
			_doc => 'The NAS-IP-Address RADIUS attribute for the authentication requests. Not needed everywhere.',
			_example => '10.1.2.3',
		},
		mininterval => {
                        _default => $DEFAULTINTERVAL,
                        _doc => "The minimum interval between each authentication request sent, in (possibly fractional) seconds.",
                        _re => '(\d*\.)?\d+',
		},
		timeout => {
			_default => 5,
			_doc => "Timeout in seconds for the RADIUS queries.",
			_re => '\d+',
		},
		port => {
			_doc => 'The RADIUS port to be used',
			_re => '\d+',
			_example => 1645,
		},
               allowreject => {
                       _doc => 'Treat "reject" responses as OK',
                       _re => '(true|false)',
                       _example => 'true',
               },
	});
}

1;
