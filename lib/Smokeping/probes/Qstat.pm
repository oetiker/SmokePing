package Smokeping::probes::Qstat;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::Qstat>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::Qstat>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork);
use IPC::Open3;
use Symbol;
use Carp;
use Time::HiRes qw(usleep);

sub pod_hash {
      return {
              name => <<DOC,
Smokeping::probes::Qstat - Qstat Probe for SmokePing
DOC
              description => <<DOC,
Integrates Qstat as a probe into smokeping. The variable B<binary> must 
point to your copy of the Qstat program.

Make sure to set your pings to 10, most Quake servers seem to throttle
after 10 rapid pings.

Set the game parameter to one of the valid options to check a different type
DOC
		authors => <<'DOC',
Walter Huf <hufman@gmail.com>
DOC
	}
}

sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {
    	my $binary = join(" ", $self->binary);
        my $return = `$binary 2>&1`;
        $self->{enable}{S} = (`$binary 2>&1` =~ /\s-S\s/);
        croak "ERROR: Qstat ('$binary') could not be run: $return"
            if $return =~ m/not found/;
    };

    return $self;
}

sub ProbeDesc($){
    my $self = shift;
    my $game = $self->{properties}{game}||'q3s';
    return "Game server $game pings";
}

# derived class can override this
sub binary {
	my $self = shift;
	return $self->{properties}{binary};
}

sub pingone($$) {
    my $self = shift;
    my $address = shift;

    my @times;
    for (my $count = 0; $count < $self->pings($address); $count++) {
        push @times, $self->pinghost($address);
    }
    return @times
}

sub pinghost($$) {
    my $self = shift;
    my $address = shift;

    my $inh = gensym;
    my $outh = gensym;
    my $errh = gensym;
    my $time;
    # pinging nothing is pointless
    return unless $address;
    $address = $address->{addr};
    my @params = ();
    push @params, "-nocfg";
    push @params, "-xml";
    push @params, "-timeout", $self->{properties}{timeout} if $self->{properties}{timeout};
    push @params, "-srcip", $self->{properties}{sourceaddress} if $self->{properties}{sourceaddress};
    push @params, "-srcport", $self->{properties}{sourceport} if $self->{properties}{sourceport};
    push @params, "-" . $self->{properties}{game};
    if ($self->{properties}{port} && $address !~ /:/) {
      push @params, $address . ':' . $self->{properties}{port};
    } else {
      push @params, $address;
    }
            
    my @cmd = (
                    $self->binary,
		    @params);
    $self->do_debug("Executing @cmd");
    my $pid = open3($inh,$outh,$errh, @cmd);
    while (<$outh>){
        chomp;
	$self->do_debug("Got quakestat output: '$_'");
        next unless /^\s*<ping>(\d+)<\/ping>\s*$/; #filter out the ping latency line
        $time = $1;
    }
    waitpid $pid,0;
    close $inh;
    close $outh;
    close $errh;
    return $time/1000.0 if defined($time);
    return;
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		_mandatory => [ 'binary' ],
		binary => {
			_sub => sub {
				my ($val) = @_;
				return undef if $ENV{SERVER_SOFTWARE}; # don't check for qstat presence in cgi mode
				return "ERROR: Qstat 'binary' does not point to an executable"
            				unless -f $val and -x _;
				return undef;
			},
			_doc => "The location of your quakestat binary.",
			_example => '/usr/bin/quakestatba',
		},
		game => {
			_example => "nexuizs",
			_default => "q3s",
			_doc => <<DOC,
What game type to check, from the -default flag of quakestat
DOC
		},
		port => {
			_re => '\d+',
			_example => 27970,
			_doc => <<DOC,
The game server port to check. It can also be overriden by adding :port to the host parameter in the Target config.
DOC
		},
		timeout => {
			_re => '\d+',
			_example => 1,
			_doc => <<DOC,
The quakestat "-timeout" parameter, in seconds.
DOC
		},
		mininterval => {
			_re => '(\d*\.)?\d+',
			_example => .1,
			_default => .5,
			_doc => <<DOC,
The minimum amount of time between sending a ping packet to the target.
DOC
		},
		sourceaddress => {
			_re => '\d+(\.\d+){3}',
			_example => '192.168.0.1',
			_doc => <<DOC,
The quakestat "-srcip" parameter . From quakestat(1):

Send packets using this IP address
DOC
		},
		sourceport => {
			_re => '\d{1,5}(-\d{1,5})?',
			_example => '9923-9943',
			_sub => sub {
				my ($val) = @_;
				my @ports = split('-', $val);
				if (scalar @ports == 2 and $ports[0] > $ports[1]) {
					return "ERROR: Qstat invalid source port range";
				}
				return undef;
			},
			_doc => <<DOC,
The quakestat "-srcport" parameter . From quakestat(1):

Send packets from these network ports
DOC
		},
	});
}

1;
