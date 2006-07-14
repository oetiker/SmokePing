package Smokeping::probes::TacacsPlus;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::TacacsPlus>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::TacacsPlus>

to generate the POD document.

=cut
use strict;
use base qw(Smokeping::probes::passwordchecker);
use Authen::TacacsPlus;
use Time::HiRes qw(gettimeofday sleep);
use Carp;

my $DEFAULTINTERVAL = 1;

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::TacacsPlus - a TacacsPlus authentication probe for SmokePing
DOC
		overview => <<DOC,
Measures TacacsPlus authentication latency for SmokePing
DOC
		description => <<DOC,
This probe measures TacacsPlus authentication latency for SmokePing.

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

The TacacsPlus protocol requires a shared secret between the server and the client.
This secret can be specified either (in order of precedence, with the latter
overriding the former) in the probe-specific variable `secret', in an external file
or in the target-specific variable `secret'.
This external file is located by the probe-specific variable `secretfile', and it should
contain whitespace-separated pairs of the form `<host> <secret>'. Comments and blank lines
are OK.

The default TacacsPlus authentication type is ASCII.  PAP and CHAP are also available.
See the Authen::TacacsPlus documentation for more information;

The probe tries to be nice to the server and does not send authentication
requests more frequently than once every X seconds, where X is the value
of the target-specific "min_interval" variable ($DEFAULTINTERVAL by default).
DOC
		authors => <<'DOC',
Gary Mikula <g2ugzm@hotmail.com>
DOC
		bugs => <<DOC,
Not as yet....
DOC
	}
}

sub ProbeDesc {
	return "TacacsPlus Authentication Attempts";
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
	my $self        = shift;
	my $target      = shift;
	my $host        = $target->{addr};
	my $vars        = $target->{vars};
	my $mininterval = $vars->{mininterval};
	my $username    = $vars->{username};
	my $authen_type = $vars->{authtype};
	my $secret      = $self->secret($host);
	my @times;
	my $elapsed;
	my $result;
	my $start;
	my $authen;
	my $end;

	if (defined $vars->{secret} and 
	    $vars->{secret} ne ($self->{properties}{secret}||"")) {
		$secret = $vars->{secret};
	}
	$secret ||= $self->{properties}{secret};

	my $timeout = $vars->{timeout};

	$self->do_log("Missing TacacsPlus secret for $host"), return 
		unless defined $secret;

	$self->do_log("Missing TacacsPlus username for $host"), return 
		unless defined $username;

	my $password = $self->password($host, $username);
	if (defined $vars->{password} and
	    $vars->{password} ne ($self->{properties}{password}||"")) {
	    	$password = $vars->{password};
	}
	$password ||= $self->{properties}{password};

	$self->do_log("Missing TacacsPlus password for $host/$username"), return 
		unless defined $password;

	my $port = $vars->{port};
	$host .= ":$port" if defined $port;

	for (1..$self->pings($target)) {
		if (defined $elapsed) {
			my $timeleft = $mininterval - $elapsed;
			sleep $timeleft if $timeleft > 0;
		}
		$host =~ s/:[0-9]+//g;
		my $r = new Authen::TacacsPlus(Host => $host, Key => $secret, Port =>$port);
		if( $r ) {
		  $start = gettimeofday();
		  if( $authen_type eq 'PAP' ){
		    $authen = &Authen::TacacsPlus::TAC_PLUS_AUTHEN_TYPE_PAP;
		  }elsif( $authen_type eq 'CHAP'){
		    $authen = &Authen::TacacsPlus::TAC_PLUS_AUTHEN_TYPE_CHAP;
		  }else{
		    $authen = &Authen::TacacsPlus::TAC_PLUS_AUTHEN_TYPE_ASCII;
		  }
		  if( $r->authen($username, $password, $authen ) ) {
		    $end = gettimeofday();
		    $elapsed = $end - $start;
		    $self->do_debug("$host: TacacsPlus Authen Granted: $elapsed time");
		    push @times, $elapsed;
		    $r->close();
		  }else{
	            $self->do_log("Unable to Autenticate to:$host with ID:$username Key:$secret");
		    $result = "Unable to Authenticate Msg: " . Authen::TacacsPlus::errmsg();
		    $self->do_debug("$result");
		  }
		}else{
	          $self->do_log("Unable to Create Constructor Authen::TacacsPlus for host:$host");
		  $result = "Unable to Build Constructor Msg: " . Authen::TacacsPlus::errmsg();
		  $self->do_debug("$result");
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
A file containing the TacacsPlus shared secrets for the targets. It should contain
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
			_doc => 'The TacacsPlus shared secret for the target, if not present in the secrets file.',
			_example => 'test-secret',
		},
		mininterval => {
                        _default => $DEFAULTINTERVAL,
                        _doc => "The minimum interval between each authentication request sent, in (possibly fractional) seconds.",
                        _re => '(\d*\.)?\d+',
		},
		timeout => {
			_default => 5,
			_doc => "Timeout in seconds for the TacacsPlus queries.",
			_re => '\d+',
		},
		port => {
                        _default => 49,
			_doc => 'The TacacsPlus port to be used',
			_re => '\d+',
			_example => 49,
		},
		authtype => {
                        _default => 'ASCII',
			_doc => 'The TacacsPlus Authentication type:ASCII(default), CHAP, PAP',
			_re => '(ASCII|CHAP|PAP)',
			_example => 'CHAP',
		},
	});
}

1;
