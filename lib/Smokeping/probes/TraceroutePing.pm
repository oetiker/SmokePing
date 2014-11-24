package Smokeping::probes::TraceroutePing;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::TraceroutePing>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::TraceroutePing>

to generate the POD document.

=cut

use feature "switch";
use strict;
use base qw(Smokeping::probes::basefork); 
# or, alternatively
# use base qw(Smokeping::probes::base);
use Carp;
use IPC::Open3;
use Symbol;
use Socket qw(:addrinfo);


sub pod_hash {
    return {
	name => <<'DOC',
Smokeping::probes::TraceroutePing - use traceroute to obtain RTT for a router
DOC
        description => <<'DOC',
Integrates standard traceroute as a probe into smokeping.  The use
case for this probe is gateways that do not respond to TCP/UDP/ICMP
packets addressed to them, but do return ICMP TTL_EXCEEDED packets for
traceroute packets to a host they route to.  It's best used in
situations where routing for the path is static or nearly so;
attempting to use this on networks with dynamic routing will yield
poor results.

The mandatory probe variable B<binary> must point to your copy of the
traceroute program.

The mandatory target variable B<desthost> must name a destination host
for the probe.  The destination host itself is not of interest and no
data is gathered on it, its only purpose is to route traffic past your
actual target.

The mandatory target variable B<host> must name the target host for
the probe.  This is the router that you want to collect RTT data for.
This variable must either be the valid reverse-lookup name of the
router, or its IP address.  Using the IP address is preferable since
it allows us to tell traceroute to avoid DNS lookups.

The target variables B<minttl> and B<maxttl> can be used to bracket
the expected hop count to B<host>.  On longer paths, this reduces the
amount of time this probe takes to execute.  These default to 1 and
30.

The target variables B<wait> sets traceroute's probe timeout in
seconds.  This defaults to 1, instead of traceroute's traditionally
higher value.  Traceroute programs often enforce a lower bound on this
value.
DOC
	authors => <<'DOC',
John Hood <cgull@glup.org>,
DOC
	see_also => <<DOC
L<smokeping_extend>
DOC
    };
}

sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    return $self;
}

sub ProbeDesc($){
    my $self = shift;
    return "Traceroute (UDP + TTL)  Pings";
}

# Probe-specific variables.

sub probevars {
    my $class = shift;
    return $class->_makevars($class->SUPER::probevars, {
	_mandatory => [ 'binary' ],
	binary => { 
	    _doc => "The location of your traceroute binary.",
	    _example => '/usr/bin/traceroute',
	    _sub => sub { 
		my $val = shift;
		return "ERROR: traceroute 'binary' does not point to an executable"
		    unless -f $val and -x _;
		return undef;
	    },
	},
			     });
}

# Target-specific variables.

sub targetvars {
    my $class = shift;
    return $class->_makevars($class->SUPER::targetvars, {
	_mandatory => [ 'desthost', 'host' ],
	#weight => { _doc => "The weight of the pingpong ball in grams",
	#	       _example => 15
	#},
	desthost => { 
	    _doc => "Final destination host for traceroute packets.  Does not have to be reachable unless it is also your host.",
	    _example => 'www.example.com',
	    _sub => sub { 
		my $val = shift;
		return undef;
	    },
	},
	host => { 
	    _doc => "Host of interest to gather actual data on.  Must be either the host's reverse-lookup name, or an IP address.",
	    _example => 'www-net-router.example.com',
	    _sub => sub { 
		my $val = shift;
		return undef;
	    },
	},
	minttl => { 
	    _doc => "Minimum TTL.  Set to the minimum expected number of hops to host.",
	    _example => '11',
	    _sub => sub { 
		my $val = shift;
		return undef;
	    }
	},
	maxttl => { 
	    _doc => "Maximum TTL.  Set to the maximum expected number of hops to host.",
	    _example => '15',
	    _sub => sub { 
		my $val = shift;
		return undef;
	    },
	},
	wait => { 
	    _doc => "Waittime.  The timeout value for traceroute's probes, in seconds.",
	    _example => '3',
	    _sub => sub { 
		my $val = shift;
		return undef;
	    },
	},
			     });
}

sub pingone ($) {
    my $self = shift;
    my $target = shift;

    # Defaults
    my $minttl = 1;
    my $maxttl = 30;
    my $wait = 1;

    # Fish out args
    my $binary = $self->{properties}{binary};
    # my $weight = $target->{vars}{weight}
    my $count = $self->pings($target); # the number of pings for this target
    my $desthost = $target->{vars}{desthost};
    my $host = $target->{vars}{host};
    $minttl = $target->{vars}{minttl} if $target->{vars}{minttl};
    $maxttl = $target->{vars}{maxttl} if $target->{vars}{maxttl};
    $wait = $target->{vars}{wait} if $target->{vars}{wait};

    # Process them
    $self->do_debug("Host $host");
    my ($err, @res) = getaddrinfo($host);
    return if $err;
    my $hostinfo = $res[0];
    my $v6 = $hostinfo->{family} eq Socket::AF_INET6;

    $self->do_debug("Desthost $desthost");
    my %hints = (Socket::AI_NUMERICHOST);
    ($err, @res) = getaddrinfo($desthost, 0, \%hints);
    my $use_numeric = ! $err;
    ($err, @res) = getaddrinfo($desthost);
    return if $err;
    my $destinfo = $res[0];
    my $destv6 = $destinfo->{family} eq Socket::AF_INET6;

    # Validate them
    if ($v6 != $destv6) {
	$self->do_debug("address families don't match, $host $desthost");
	return;
    }

    $self->do_debug("validated $host");
    # ping one target
    $self->do_debug("command: $self->{properties}{binary}, " . $self->{properties}{binary});

    my @times;

    my @cmd = (
	$self->{properties}{binary} . ($v6 ? '6' : ''),
	'-w', $wait,
	'-f', $minttl,
	'-m', $maxttl,
	'-q', '1',
	);

    push(@cmd, "-n") if $use_numeric;
    push(@cmd, $desthost);

    # Run traceroute for only one iteration in an external loop, to
    # avoid various problems parsing that can come up with >1.
    for (1..$count) {
	$self->do_debug("Executing @cmd");
	my $killed;
	my $f_stdin = gensym;
	my $f_stdout = gensym;
	my $errh = gensym;
	my $pid = open3($f_stdin, $f_stdout, $f_stderr, @cmd);
	while (<$f_stdout>){
	    my $line = $_;
	    chomp($line);
	    $self->do_debug("Received: $line");
	    next unless $line =~ /^\s+\d+\s+\S+\s+(\d|\.|,)+\s+\S+\s*$/; # only match RTT output

	    my @fields = split(/\s+/,$line);
	    shift @fields if @fields[0] eq '';
	    $self->do_debug("fields: " . join(':',@fields));
	    next unless $host eq @fields[1];

	    my $time = @fields[2];
	    # Adjust time units to smokeping's preferred units.  I'm
	    # not sure any traceroute implementations actually change
	    # their units.
	    for (@fields[3]) {
		when (/^s(|ec(|ond))$/i) { }
		when (/^(m|milli)s(|ec(|ond))$/i) { $time /= 1000 }
		when (/^(m|milli)s(|ec(|ond))$/i) { $time /= 1000000 }
		default { $time /= 1000 }
	    };
	    $self->do_debug("time: $time");
	    push @times, $time;

	    # if we have a time, there's no point in waiting for traceroute to finish the trace
	    $killed = kill(15, $pid);
	    last;
	}
	waitpid $pid,0;
	$self->do_debug("Exitstatus: " . $?) if ($? && !$killed);
	close $f_stdin;
	close $f_stdout;
	close $f_stderr;
    }
    @times = sort {$a <=> $b} @times;
    $self->do_debug("Times: " . join(' ', @times));
    return @times;
}
# That's all, folks!

1;
