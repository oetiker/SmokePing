package Smokeping::probes::AnotherCurl;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::AnotherCurl>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::AnotherCurl>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork);
use Carp;

my $DEFAULTBIN = "/usr/bin/curl";

sub pod_hash {
    return {
	name => "Smokeping::probes::AnotherCurl - a curl(1) probe for SmokePing",
	overview => "Fetches an HTTP or HTTPS URL using curl(1).",
	description => "(see curl(1) for details of the options below)",
	authors => <<'DOC',
 Gerald Combs <gerald [AT] ethereal.com>
 Niko Tyni <ntyni@iki.fi>
 Jean Baptiste Favre <smokeping@jbfavre.org>
DOC
	notes => <<DOC,
You should consider setting a lower value for the C<pings> variable than the
default 20, as repetitive URL fetching may be quite heavy on the server.

The URL to be tested used to be specified by the variable 'url' in earlier
versions of Smokeping, and the 'host' setting did not influence it in any
way. The variable name has now been changed to 'urlformat', and it can
(and in most cases should) contain a placeholder for the 'host' variable.

Legacy Curl probe only returns page load time. With AnotherCurl, you can
specify which 'write-out' value you want to get (please refer to curl(1) for
more details about write_out option.
DOC
	see_also => "curl(1), L<http://curl.haxx.se/>",
    }
}

sub probevars {
	my $class = shift;
	my $h = $class->SUPER::probevars;
	delete $h->{timeout};
	return $class->_makevars($h, {
		binary => {
			_doc => "The location of your curl binary.",
			_default => $DEFAULTBIN,
			_sub => sub {
				my $val = shift;
				return "ERROR: Curl 'binary' $val does not point to an executable"
					unless -f $val and -x _;
				return undef;
			},
		},
	});
}

sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		_mandatory => [ 'urlformat' ],
		agent => {
			_doc => <<DOC,
The "-A" curl(1) option.  This is a full HTTP User-Agent header including
the words "User-Agent:". Note that it does not need any quotes around it.
DOC
			_example => 'User-Agent: Lynx/2.8.4rel.1 libwww-FM/2.14 SSL-MM/1.4.1 OpenSSL/0.9.6c',
			_sub => sub {
				my $val = shift;
				return "The Curl 'agent' string does not need any quotes around it anymore."
					if $val =~ /^["']/ or $val =~ /["']$/;
				return undef;
			},
		},
		timeout => {
			_doc => qq{The "-m" curl(1) option.  Maximum timeout in seconds.},
			_re => '\d+',
			_example => 20,
			_default => 10,
		},
		interface => {
			_doc => <<DOC,
The "--interface" curl(1) option.  Bind to a specific interface, IP address or
host name.
DOC
			_example => 'eth0',
		},
		ssl2 => {
			_doc => qq{The "-2" curl(1) option.  Force SSL2.},
			_example => 1,
		},
		urlformat => {
			_doc => <<DOC,
The template of the URL to fetch.  Can be any one that curl supports.
Any occurrence of the string '%host%' will be replaced with the
host to be probed.
DOC
			_example => "http://%host%/",
		},
        insecure_ssl => {
            _doc => <<DOC,
The "-k" curl(1) option. Accept SSL connections that don't have a secure
certificate chain to a trusted CA. Note that if you are going to monitor
https targets, you'll probably have to either enable this option or specify
the CA path to curl through extraargs below. For more info, see the
curl(1) manual page.
DOC
            _example => 1,
        },
		extrare=> {
			_doc => <<DOC,
The regexp used to split the extraargs string into an argument list,
in the "/regexp/" notation.  This contains just the space character 
(" ") by default, but if you need to specify any arguments containing spaces,
you can set this variable to a different value.
DOC
			_default => "/ /",
			_example => "/ /",
			_sub => sub {
				my $val = shift;
				return "extrare should be specified in the /regexp/ notation"
					unless $val =~ m,^/.*/$,;
				return undef;
			},
		},
		follow_redirects => {
			_doc => <<DOC,
If this variable is set to 'yes', curl will follow any HTTP redirection steps (the '-L' option).
If set to 'no', HTTP Location: headers will not be followed. See also 'include_redirects'.
DOC
			_default => "no",
			_re => "(yes|no)",
			_example => "yes",
		},

		include_redirects => {
			_doc => <<DOC,
If this variable is set to 'yes', the measurement result will include the time
spent on following any HTTP redirection steps. If set to 'no', only the last
step is measured. See also 'follow_redirects'.
DOC
			_default => "no",
			_re => "(yes|no)",
			_example => "yes",
		},
		extraargs => {
			_doc => <<DOC,
Any extra arguments you might want to hand to curl(1). The arguments
should be separated by the regexp specified in "extrare", which
contains just the space character (" ") by default.

Note that curl will be called with the resulting list of arguments
without any shell expansion. If you need to specify any arguments
containing spaces, you should set "extrare" to something else.

As a complicated example, to explicitly set the "Host:" header in Curl
requests, you need to set "extrare" to something else, eg. "/;/",
and then specify C<extraargs = --header;Host: www.example.com>.
DOC
			_example => "-6 --head --user user:password",
		},
		write_out => {
			_doc => <<DOC,
Choose which write-out value you want to send to Smokeping. Value can
be one of: 'time_appconnect', 'time_connect', 'time_namelookup',
'time_pretransfer', 'time_redirect', 'time_starttransfer', 'time_total'.

Default behaviour is the same as legacy Curl probe one.
DOC
		},
	});
}

# derived class will mess with this through the 'features' method below
my $featurehash = {
	agent => "-A",
	timeout => "-m",
	interface => "--interface",
};

sub features {
	my $self = shift;
	my $newval = shift;
	$featurehash = $newval if defined $newval;
	return $featurehash;
}

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new(@_);

	$self->_init if $self->can('_init');

    # no need for this if running as a CGI
	$self->test_usage unless $ENV{SERVER_SOFTWARE};

	return $self;
}

# warn about unsupported features
sub test_usage {
	my $self = shift;
	my $bin = $self->{properties}{binary};
	my @unsupported;

	my $arghashref = $self->features;
	my %arghash = %$arghashref;
        my $curl_man = `$bin --help`;
        
	for my $feature (keys %arghash) {
		next if $curl_man =~ /\Q$arghash{$feature}/;
        	push @unsupported, $feature;
		$self->do_log("Note: your curl doesn't support the $feature feature (option $arghash{$feature}), disabling it");
	}
	map { delete $arghashref->{$_} } @unsupported;
#	if ($curl_man !~ /\stime_redirect\s/) {
#		$self->do_log("Note: your curl doesn't support the 'time_redirect' output variable; 'include_redirects' will not function.");
#	}
	return;
}

sub ProbeDesc($) {
	return "URLs using curl(1)";
}

# other than host, count and protocol-specific args come from here
sub make_args {
	my $self = shift;
	my $target = shift;
	my @args;
	my %arghash = %{$self->features};

	for (keys %arghash) {
		my $val = $target->{vars}{$_};
		push @args, ($arghash{$_}, $val) if defined $val;
	}
	return @args;
}

# This is what derived classes will override
sub proto_args {
	my $self = shift;
	my $target = shift;
	# XXX - It would be neat if curl had a "time_transfer".  For now,
	# we take the total time minus the DNS lookup time.
	my @args = ("-w", "Total: %{time_total} DNS: %{time_namelookup} Redirect: %{time_redirect} Connect: %{time_connect} Appconnect: %{time_appconnect} Pretransfert: %{time_pretransfer} Starttransfert: %{time_starttransfer}\\n");
	my $ssl2 = $target->{vars}{ssl2};
	push (@args, "-2") if $ssl2;
	my $insecure_ssl = $target->{vars}{insecure_ssl};
	push (@args, '-k') if $insecure_ssl;
	my $follow = $target->{vars}{follow_redirects};
	push (@args, '-L') if $follow eq "yes";

	return(@args);
}

sub extra_args {
	my $self = shift;
	my $target = shift;
	my $args = $target->{vars}{extraargs};
	return () unless defined $args;
	my $re = $target->{vars}{extrare};
	($re =~ m,^/(.*)/$,) and $re = qr{$1};
	return split($re, $args);
}

sub make_commandline {
	my $self = shift;
	my $target = shift;
	my $count = shift;

	my @args = $self->make_args($target);
	my $url = $target->{vars}{urlformat};
	my $host = $target->{addr};
	$url =~ s/%host%/$host/g;
	my @urls = split(/\s+/, $url);
	push @args, ("-o", "/dev/null") for (@urls);
	push @args, $self->proto_args($target);
	push @args, $self->extra_args($target);
	
	return ($self->{properties}{binary}, @args, @urls);
}

sub pingone {
	my $self = shift;
	my $t = shift;

	my @cmd = $self->make_commandline($t);

	$self->do_debug("executing command list " . join(",", map { qq('$_') } @cmd));

	my @times;
	my $count = $self->pings($t);

	for (my $i = 0 ; $i < $count; $i++) {
		open(P, "-|") or exec @cmd;

		my $val;

		while (<P>) {
			chomp;
			/^Total: (\d+\.\d+) DNS: (\d+\.\d+) Redirect: (\d+\.\d+) Connect: (\d+\.\d+) Appconnect: (\d+\.\d+) Pretransfert: (\d+\.\d+) Starttransfert: (\d+\.\d+)?/ and do {
				# Total: time_total
				# DNS: time_namelookup
				# Redirect: time_redirect
				# Connect: time_connect
				# Appconnect: time_appconnect
				# Pretransfert: time_pretransfer
				# Starttransfert: time_starttransfer
				# Default is current behaviour where we take total minus DNS resolution.
				if ($t->{vars}{write_out} eq 'time_total') {$val += $1}
				elsif ($t->{vars}{write_out} eq 'time_namelookup') {$val += $2}
				elsif ($t->{vars}{write_out} eq 'time_redirect') {$val += $3}
				elsif ($t->{vars}{write_out} eq 'time_connect') {$val += $4}
				elsif ($t->{vars}{write_out} eq 'time_appconnect') {$val += $5}
				elsif ($t->{vars}{write_out} eq 'time_pretransfer') {$val += $6}
				elsif ($t->{vars}{write_out} eq 'time_starttransfer') {$val += $7}
				else {$val += $1 - $2;}

				if ($t->{vars}{include_redirects} eq "yes" and defined $3) {
					$val += $3;
				}
				$self->do_debug("curl output: '$_', result: $val");
			};
		}
		close P;
		if ($?) {
			my $status = $? >> 8;
			my $signal = $? & 127;
			my $why = "with status $status";
			$why .= " [signal $signal]" if $signal;

			# only log warnings on the first ping of the first ping round
			my $function = ($self->rounds_count == 1 and $i == 0) ? 
				"do_log" : "do_debug";

			$self->$function(qq(WARNING: curl exited $why on $t->{addr}));
		}
		push @times, $val if defined $val;
	}
	
	# carp("Got @times") if $self->debug;
	return sort { $a <=> $b } @times;
}

1;
