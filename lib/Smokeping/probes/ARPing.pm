package Smokeping::probes::ARPing;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command

C<smokeping -man Smokeping::probes::ARPing>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::ARPing>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork);
use IPC::Open3;
use Symbol;
use Carp;

sub pod_hash {
    return {
        name => <<DOC,
Smokeping::probes::ARPing - ARP Ping Probe for SmokePing
DOC
        description => <<DOC,
Integrates arping as a probe into SmokePing. The variable B<binary> must
point to your copy of the arping program. This probe uses ARP requests
to measure round-trip times to hosts on the local network segment.

This probe is compatible with both B<iputils arping> and B<busybox arping>.
Note that the C<interval> option is only supported by iputils arping.

ARP pings are useful for:

=over 4

=item *

Measuring latency to hosts that block ICMP

=item *

Detecting hosts on the local network segment

=item *

Measuring Layer 2 connectivity without relying on IP routing

=back

B<Note:> arping only works for hosts on the same network segment (local LAN).
It will not work across routers. The probe typically requires root privileges
or appropriate capabilities (CAP_NET_RAW) to send raw ARP packets.

The arping output format expected is:

    Unicast reply from 192.168.0.1 [00:11:22:33:44:55]  1.234ms

DOC
        authors => <<'DOC',
SmokePing Developers
DOC
        see_also => <<DOC,
arping(8)
DOC
    };
}

sub new($$$) {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new(@_);

    # Enable debug if configured
    if ( $self->{properties}{debug} and $self->{properties}{debug} eq 'true' ) {
        $self->debug(1);
    }

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {
        my $binary = $self->{properties}{binary};
        my $return = `$binary -V 2>&1`;
        croak "ERROR: arping ('$binary') could not be run: $return"
          if $return =~ m/not found|No such file/i;
    }

    return $self;
}

sub ProbeDesc($) {
    my $self = shift;
    return "ARP Pings";
}

sub probevars {
    my $class = shift;
    return $class->_makevars(
        $class->SUPER::probevars,
        {
            _mandatory => ['binary'],
            binary     => {
                _doc     => "The location of your arping binary.",
                _example => '/usr/bin/arping',
                _sub     => sub {
                    my $val = shift;
                    return undef
                      if $ENV{SERVER_SOFTWARE};    # skip check in CGI mode
                    return
                      "ERROR: arping 'binary' does not point to an executable"
                      unless -f $val and -x _;
                    return undef;
                },
            },
            debug => {
                _doc =>
"Enable debug logging for this probe. Set to 'true' to enable.",
                _example => 'true',
                _re      => '(true|false)',
            },
        }
    );
}

sub targetvars {
    my $class = shift;
    return $class->_makevars(
        $class->SUPER::targetvars,
        {
            interface => {
                _doc => <<DOC,
The network interface to use for sending ARP requests.
This is the arping "-I" parameter. Required for most arping implementations.
DOC
                _example => 'eth0',
            },
            sourceaddress => {
                _doc => <<DOC,
The source IP address to use in ARP requests.
This is the arping "-s" parameter.
DOC
                _re      => '\d+\.\d+\.\d+\.\d+',
                _example => '192.168.0.1',
            },
            waittimeout => {
                _doc => <<DOC,
Total timeout in seconds for the entire arping run.
This is the arping "-w" parameter. If not specified, arping will wait
until all pings are sent/received. If you set this, make sure it's long
enough for all pings (e.g., at least pings × 1 second).
DOC
                _re      => '\d+',
                _example => '30',
            },
            interval => {
                _doc => <<DOC,
Interval between sending ARP requests in seconds.
This is the arping "-i" parameter.
B<Note:> This option is NOT supported by busybox arping. Only use with iputils arping.
DOC
                _re      => '(\d*\.)?\d+',
                _example => '0.5',
            },
            broadcast => {
                _doc => <<DOC,
Keep on broadcasting, do not unicast. Set to 'true' to enable.
This is the arping "-b" parameter.
DOC
                _re      => '(true|false)',
                _example => 'false',
            },
        }
    );
}

sub pingone ($) {
    my $self   = shift;
    my $target = shift;

    my $inh  = gensym;
    my $outh = gensym;
    my $errh = gensym;

    my @times;
    my $pings = $self->pings($target);

    my @cmd = ( $self->{properties}{binary} );

    # Add count parameter
    push @cmd, '-c', $pings;

    # Add interface if specified (usually required)
    push @cmd, '-I', $target->{vars}{interface}
      if $target->{vars}{interface};

    # Add source address if specified
    push @cmd, '-s', $target->{vars}{sourceaddress}
      if $target->{vars}{sourceaddress};

    # Add timeout if specified (arping -w is total timeout for entire run)
    push @cmd, '-w', $target->{vars}{waittimeout}
      if $target->{vars}{waittimeout};

    # Add interval if specified (note: arping uses -i for interval)
    # Be careful: some arping versions use -i for interface
    # The iputils arping uses -I for interface and -i for interval
    push @cmd, '-i', $target->{vars}{interval}
      if $target->{vars}{interval};

    # Add broadcast flag if enabled
    push @cmd, '-b'
      if $target->{vars}{broadcast} and $target->{vars}{broadcast} eq 'true';

    # Add target address
    push @cmd, $target->{addr};

    my $cmdline = join( " ", @cmd );
    $self->do_debug("Executing: $cmdline");

    my $pid = open3( $inh, $outh, $errh, @cmd );

    # Close stdin immediately
    close $inh;

    # Collect all output first
    my @stdout_lines;
    my @stderr_lines;

    while (<$outh>) {
        chomp;
        push @stdout_lines, $_;
    }

    while (<$errh>) {
        chomp;
        push @stderr_lines, $_;
    }

    waitpid $pid, 0;
    my $rc     = $?;
    my $status = $rc >> 8;

    # Debug: log all output
    $self->do_debug( "arping stdout: " . join( " | ", @stdout_lines ) )
      if @stdout_lines;
    $self->do_debug( "arping stderr: " . join( " | ", @stderr_lines ) )
      if @stderr_lines;
    $self->do_debug("arping exit status: $status (rc=$rc)");

# Parse stdout for ARP replies
# Expected format: "Unicast reply from 192.168.0.1 [00:11:22:33:44:55]  1.234ms"
# or: "Broadcast reply from 192.168.0.1 [00:11:22:33:44:55]  1.234ms"
    for my $line ( @stdout_lines, @stderr_lines ) {
        $self->do_debug("Parsing line: '$line'");

        # Match reply lines and extract time in milliseconds
        # Handles both "Unicast reply" and "Broadcast reply"
        if ( $line =~ /reply from \S+\s+\[[\da-fA-F:]+\]\s+([\d.]+)\s*ms/i ) {
            my $time_ms = $1;
            $self->do_debug("Matched time: ${time_ms}ms");

            # Convert milliseconds to seconds (SmokePing expects seconds)
            push @times, $time_ms / 1000;
        }
    }

    $self->do_debug( "Collected " . scalar(@times) . " time samples" );

    # arping exit codes:
    # 0 = at least one reply received
    # 1 = no reply received
    # 2 = error
    if ( $status == 2 ) {
        carp join( " ", @cmd )
          . " returned with exit code $rc. Run with debug enabled for more information.";
    }

    close $outh;
    close $errh;

    # Sort times and format for SmokePing
    @times = sort { $a <=> $b } @times;

    # ARP can sometimes receive more replies than probes sent (e.g., due to
    # broadcast + unicast responses). Truncate to requested ping count to
    # avoid RRD update errors. Keep the fastest (lowest) times.
    if ( scalar(@times) > $pings ) {
        $self->do_debug(
            "Truncating " . scalar(@times) . " samples to $pings" );
        @times = @times[ 0 .. $pings - 1 ];
    }

    @times = map { sprintf "%.10e", $_ } @times;

    return @times;
}

1;
