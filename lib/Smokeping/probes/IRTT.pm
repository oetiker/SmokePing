package Smokeping::probes::IRTT;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::IRTT>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::IRTT>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork); 
#use Data::Dumper;
use IPC::Open2 qw(open2);
use JSON::PP qw(decode_json);
use Path::Tiny qw(path);
use Scalar::Util qw(looks_like_number);
use Symbol qw(gensym);
use Time::HiRes qw(usleep gettimeofday tv_interval);

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::IRTT - a SmokePing Probe for L<IRTT|https://github.com/peteheist/irtt>
DOC
		description => <<DOC,
This SmokePing probe uses L<IRTT|https://github.com/peteheist/irtt> to record
network L<round-trip time|https://en.wikipedia.org/wiki/Round-trip_delay_time>,
L<one-way delay|https://en.wikipedia.org/wiki/End-to-end_delay> or
L<IPDV|https://en.wikipedia.org/wiki/Packet_delay_variation> (jitter), based on
the value of the B<metric> variable.

Additionally, the probe provides a results sharing feature, which allows using
results from a single IRTT run to record multiple metrics for a given host at
the same time. One target is defined with the B<writeto> variable set, which
selects the name of a temporary file to save the IRTT output to. Additional
targets are defined with the B<readfrom> variable set to the same value, which,
instead of running IRTT, wait for the main target's output to become available,
then parse it to record the chosen metric from the same data. See the
B<writeto> and B<readfrom> variables for more information.

=head2 WARNING

The results sharing feature (B<writeto> and B<readfrom> variables) requires the
number of B<forks> for the IRTT probe to be at least the total number of IRTT
targets defined (regardless of whether they have B<writeto> and B<readfrom>
set). Otherwise, there can be a deadlock while B<readfrom> targets wait for their
corresponding B<writeto> target to complete, which may never start.
DOC
		authors => <<'DOC',
Pete Heist <pete@heistp.net>
DOC
	};
}

sub new ($$$) {
	my $self = shift->SUPER::new(@_);

	# no need for this if we run as a cgi (still run at startup)
	unless ( $ENV{SERVER_SOFTWARE} ) {
		# check irtt version
		my $vout = `$self->{properties}->{binary} version`
			or die "ERROR: irtt version return code " . ($? >> 8);
		if ($vout =~ /irtt version: (\d+)\.(\d+)\.(\d+)/ ) {
			if ($1 == '0' && $2 < '9') {
				die "ERROR: unsupported irtt version: $1.$2.$3";
			}
		} else {
			die "ERROR: irtt version unexpected output: $vout";
		}
	};

	return $self;
}

sub probevars ($) {
	my $class = shift;
	my $pv = $class->_makevars($class->SUPER::probevars, {
		_mandatory => [ 'binary' ],
		binary => { 
			_doc => "The location of your irtt binary.",
			_default => '/usr/bin/irtt',
			_example => '/usr/local/bin/irtt',
			_sub => sub { 
				my $val = shift;
        			return "ERROR: irtt 'binary' does not point to an executable"
            				unless -f $val and -x _;
				return undef;
			},
		},
		tmpdir => { 
			_doc => "A temporary directory in which to place files for writeto/readfrom.",
			_default => '/tmp/smokeping-irtt',
		},
	});

	# TODO Delete probe timeout and define it per-target based on interval
	# (not ready yet as need to figure out logic in targetvars)
	#delete $pv->{timeout};

	return $pv;
}

sub targetvars ($) {
	my $class = shift;
	my $tv = $class->_makevars($class->SUPER::targetvars, {
		dscp => {
			_doc => <<DOC,
The packet L<DSCP|https://en.wikipedia.org/wiki/Differentiated_services> value
to use (C<irtt client --dscp>). This is the same as the classic one byte IP ToS
field, but on the modern Internet, typically only the lower 6 bits are used,
and this is called the DSCP value. The upper two bits are reserved for
L<ECN|https://en.wikipedia.org/wiki/Explicit_Congestion_Notification>. Hex may
be used if prefixed by C<0x>.
DOC
			_example => '46',
			_re => '(\d+|0x[0-9a-fA-F]{1,2})',
		},
		extraargs => {
			_doc => <<DOC,
Extra arguments to C<irtt client> (see L<irtt-client(1)>). B<Be careful> with
extra arguments, as some can corrupt the results.
DOC
			_example => '--ttl=32',
		},
		fill => {
			_doc => <<DOC,
The fill to use in the payload for the client to server packet (C<irtt client
--fill>). The B<length> variable must be large enough so there's a payload to fill.
Use rand for random fill, or see L<irtt-client(1)> for more options.
DOC
			_example => 'rand',
		},
		hmac => {
			_doc => <<DOC,
The
L<HMAC|https://en.wikipedia.org/wiki/Hash-based_message_authentication_code>
key to use when sending packets to the server (C<irtt client --hmac>).
DOC
			_example => 'opensesame',
		},
		interval => {
			_doc => <<DOC,
The interval between successive requests, in seconds (C<irtt client -i>, but the
unit is always seconds (s)).

B<WARNING>

If B<interval> is increased to greater than 5 seconds, the B<timeout> (which
defaults to B<pings> * 5 seconds + 1) must be modified so that SmokePing
doesn't kill the probe prematurely. Additionally, B<interval> must not be
increased such that B<pings> * B<interval> is greater than B<step>. For
example, at B<step>=300 and B<pings>=20, the B<interval> must not be greater
than 15 seconds, but should preferably be less to account for handshake and
packet wait times.
DOC
			_example => 1.5,
			_default => 1,
			_re => '(\d*\.)?\d+',
		},
		ipversion => {
			_doc => <<DOC,
The IP version to use for packets (4 or 6, corresponding to C<irtt client -4>
or C<irtt client -6>). By default the IP version is chosen based on the
supplied host variable.
DOC
			_example => 6,
			_re => '^(4|6)$',
		},
		length => {
			_doc => <<DOC,
The length (size) of the packet (C<irtt client -l>). The length includes IRTT
headers, but not IP or UDP headers. The actual packet length is increased to
accommodate the IRTT headers, if necessary. Header size as of IRTT 0.9.0 as used
in SmokePing is 48 bytes when B<writeto> is set (since both monotonic and wall
clock values are requested) and 40 bytes otherwise.
DOC
			_example => 172,
			_re => '\d+',
		},
		localaddr => {
			_doc => <<DOC,
The local address to bind to when sending packets (C<irtt client --local>).
See L<irtt-client(1)> Host formats for valid syntax.
DOC
			_example => '192.168.1.10:63814',
		},
		metric => {
			_doc => <<DOC,
The metric to record, one of:

=over

=item *

rtt: L<round-trip time|https://en.wikipedia.org/wiki/Round-trip_delay_time>

=item *

send: L<one-way send delay|https://en.wikipedia.org/wiki/End-to-end_delay>
I<(requires external time synchronization)>

=item *

receive: L<one-way receive delay|https://en.wikipedia.org/wiki/End-to-end_delay>
I<(requires external time synchronization)>

=item *

ipdv: L<IPDV|https://en.wikipedia.org/wiki/Packet_delay_variation>
(instantaneous packet delay variation, or jitter)

=item *

send_ipdv: IPDV for sent packets

=item *

receive_ipdv: IPDV for received packets

=back

Note that the C<send> and C<receive> metrics require accurate external system
clock synchronization, otherwise the values from one will be abnormally high and
the other will be abnormally low or even negative, in which case the value 0
will be given SmokePing. It is recommended to install ntp on both the SmokePing
client and IRTT server. Properly configured NTP may be able to synchronize time to
within a few milliseconds, which is usually enough to provide useful results.
PTP over a LAN may achieve microsecond-level accuracy. For best results between
geographically remote hosts, GPS receivers may be used. Since C<send_ipdv> and
C<receive_ipdv> measure the variation in times between successive packets,
and since C<rtt> and C<ipdv> use monotonic clock values on the client side
only, external time synchronization is not required for these metrics.

DOC
			_default => 'rtt',
			_re => '^(rtt|send|receive|ipdv|send_ipdv|receive_ipdv)$',
		},
		readfrom => {
			_doc => <<DOC,
The name of a file to read results from, instead of running IRTT. Use in
combination with B<writeto> to use the results from one IRTT run to record
multiple metrics. The value will become the name of a file in B<tmpdir>, and
must be the same as another target's setting for B<writeto>. Multiple targets
may use the same value for B<readfrom>, but B<writeto> and B<readfrom> may not
be both set for a given target. When B<readfrom> is set, any variables that
affect C<irtt client> are ignored because IRTT is not being invoked, including:
B<dscp>, B<extraargs>, B<fill>, B<hmac>, B<interval>, B<ipversion>, B<length>,
B<localaddr> and B<serverfill>. These values are only relevant in the
corresponding B<writeto> target.

Note that the B<host> variable must still be defined for targets that define
B<readfrom>, otherwise the target won't be used.

When using this feature, be sure to have at least as many B<forks> for the
IRTT probe as you have total IRTT targets defined. See the L</DESCRIPTION>
section for more information.
DOC
			_example => 'irtt1',
		},
		readfrompollinterval => {
			_doc => <<DOC,
The integer interval in seconds on which to poll for results when B<readfrom>
is set. Lower numbers will allow B<readfrom> to see the results a bit sooner,
at the cost of higher CPU usage. Polling does not begin until the soonest time
at which the IRTT client could have terminated normally.
DOC
			_default => 5,
			_re => '[1-9]\d*',
			_example => '2',
		},
		serverfill => {
			_doc => <<DOC,
The fill to use in the payload for the server to client packet (C<irtt client
--sfill>). The B<length> variable must be large enough to accommodate a
payload.  Use C<rand> for random fill, or see L<irtt-client(1)> for more
options.
DOC
			_example => 'rand',
		},
		sleep => {
			_doc => <<DOC,
The amount of time to sleep before starting requests or processing results (a
float in seconds). This may be used to avoid CPU spikes caused by invoking
multiple instances of IRTT at the same time.
DOC
			_example => '0.5',
			_re => '(\d*\.)?\d+',
		},
		writeto => {
			_doc => <<DOC,
The name of a file to write results to after running IRTT. Use in combination
with B<readfrom> to use the results from this IRTT run to record multiple
metrics. The value will become the name of a file in B<tmpdir>, and any targets
with B<readfrom> set to the same value will use this target's results. There
must be only one target with B<writeto> set for a given file, and B<writeto>
and B<readfrom> may not be both set for a given target.

When using this feature, be sure to have at least as many B<forks> for the IRTT
probe as you have total IRTT targets defined. See the L</DESCRIPTION> section
for more information.
DOC
			_example => 'irtt1',
		},
	});

	# TODO Here I would like to be able to set the target-specific timeout
	# based on the interval and number of pings, but I'm currently unable to
	# get the number of pings in this method, before I have a value for target.
	#my $pings = $tv->{pings} ? $tv->{pings} : $class->SUPER::pings();
	#$tv->{timeout} = $tv->{interval} * $pings + 5;

	return $tv;
}

sub ProbeDesc ($) {
	my $self = shift;
	return "IRTT round-trips";
}

sub get_json_from_file ($$) {
	my $self = shift;
	my $target = shift;
	my $t = $target;
	my $tv = $t->{vars};
	my $p = $self->{properties};
	my $fname = path($p->{tmpdir}, $tv->{readfrom});

	# mark start
	my $t0 = [gettimeofday];

	# sleep, if requested
	usleep($tv->{sleep} * 1000000) if $tv->{sleep};

	# wait for earliest possible finish, then 5 seconds at a time
	sleep $tv->{interval} * $self->pings($t) + 2;
	while (1) {
		# break when the file is found
		last if -f $fname;

		# die if step elapsed, which should never happen as we should
		# be killed by smokeping's timeout sooner than this
		if (tv_interval ($t0, [gettimeofday]) > $self->step) {
			die("ERROR: step elapsed and $fname not found");
		}

		sleep $tv->{readfrompollinterval};
	};

	# return file contents
	return path($fname)->slurp;
}

sub run_irtt ($$) {
	my $self = shift;
	my $target = shift;
	my $t = $target;
	my $tv = $t->{vars};
	my $p = $self->{properties};

	# choose clock for requested metric
	my $clock;
	if ($tv->{writeto}) {
		$clock = 'both';
	} else {
		$clock = $tv->{metric} =~ /(send|receive)/ ? 'wall' : 'monotonic';
	}

	# build command
	my $count = $self->pings($t);
	my $interval = $tv->{interval};
	my $duration = $interval * $count;
	my @cmd = (
		$p->{binary}, 'client',
		'-i', $interval . 's',
		'-d', $duration . 's',
		'-Q',
		'--clock=' . $clock,
		'--tstamp=midpoint',
		'--stats=none',
		'-o', '-',
	);
	push @cmd, ("-l", $tv->{length}) if $tv->{length};
	push @cmd, "--hmac=" . $tv->{hmac} if $tv->{hmac};
	push @cmd, "--dscp=" . $tv->{dscp} if $tv->{dscp};
	push @cmd, "--fill=" . $tv->{fill} if $tv->{fill};
	push @cmd, "--sfill=" . $tv->{serverfill} if $tv->{serverfill};
	push @cmd, "--local=" . $tv->{localaddr} if $tv->{localaddr};
	push @cmd, "-$tv->{ipversion}" if $tv->{ipversion};
	push @cmd, $t->{addr};

	# sleep, if requested
	usleep($tv->{sleep} * 1000000) if $tv->{sleep};

	# execute irtt
	$self->do_debug("Executing @cmd");
	my $inh = gensym;
	my $outh = gensym;
	my $pid = open2($outh, $inh, @cmd);
	my $out = do { local $/; <$outh> };
	waitpid $pid,0;
	close $inh;
	close $outh;
	
	# write json output atomically if writeto set (empty for errors)
	if ($tv->{writeto}) {
		path($p->{tmpdir}, $tv->{writeto})->spew($out);
	}

	# die on non-zero status codes
	my $status = $? >> 8;
	die "ERROR: irtt client return code $status" if $status;

	return $out
}

sub nstos ($) {
	my $ns = shift;
	return $ns / 1000000000.0;
}

sub median {
	my @vals = sort {$a <=> $b} @_;
	my $len = @vals;
	if ($len%2) {
		return $vals[int($len/2)];
	} else {
        	return ($vals[int($len/2)-1] + $vals[int($len/2)])/2;
	}
}

sub pingone ($$) {
	my $self = shift;
	my $target = shift;
	my $t = $target;
	my $tv = $t->{vars};
	my $p = $self->{properties};

	# if writeto set, create temp directory or remove temp file
	if ($tv->{writeto}) {
		if ($tv->{readfrom}) {
			die("ERROR: writeto and readfrom must not both be set for the same target");
		}
		my $d = $p->{tmpdir};
		if (-d $d) {
			path($d, $tv->{writeto})->remove;
		} else {
			mkdir $d or die("ERROR: unable to create temp dir $d ($!)");
		}
	}

	# get json from irtt, or file if readfrom set
	my $json;
	if ($tv->{readfrom}) {
		$json = get_json_from_file($self, $target);
	} else {
		$json = run_irtt($self, $target);
	}
	die("ERROR: json content empty") if $json eq "";

	# decode json
	my $dec = decode_json($json) or die "ERROR: decode_json failed $!";

	# get times for chosen metric from json
	my @times;
	foreach my $rt ( @{$dec->{'round_trips'}} ) {
		if ($rt->{'lost'} eq 'false') {
			my $ns;
			my $dl = $rt->{'delay'};
			my $pv = $rt->{'ipdv'};
			for ($tv->{metric}) {
				/^(rtt|send|receive)$/ && do {
					$ns = $dl->{$tv->{metric}};
					if ($ns < 0) {
						$ns = 0;
					}
					next;
				};
				/^ipdv$/ && do {
					$ns = $pv->{'rtt'};
					next;
				};
				/^send_ipdv$/ && do {
					$ns = $pv->{'send'};
					next;
				};
				/^receive_ipdv$/ && do {
					$ns = $pv->{'receive'};
					next;
				};
				die("ERROR: impossible metric $tv->{metric}")
			}
			push @times, nstos(abs($ns)) if looks_like_number($ns);
		}
	}

	# push an extra median value for ipdv, which has one fewer values
	# than pings, so there isn't a lost packet reported
	if ($tv->{metric} =~ /ipdv/ && @times > 0) {
		push @times, median(@times);
	}

	return sort { $a <=> $b } @times;
}

1;
