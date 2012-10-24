package Smokeping::probes::basefork;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::basefork>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::basefork>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basevars);
use Symbol;
use Carp;
use IO::Select;
use POSIX; # for ceil() and floor()
use Config; # for signal names

my $DEFAULTFORKS = 5;

sub pod_hash {
    return {
    	name => <<DOC,
Smokeping::probes::basefork - Yet Another Base Class for implementing SmokePing Probes
DOC
	overview => <<DOC,
Like Smokeping::probes::basevars, but supports the probe-specific property `forks'
to determine how many processes should be run concurrently. The
targets are pinged one at a time, and the number of pings sent can vary
between targets.
DOC
	description => <<DOC,
Not all pinger programs support testing multiple hosts in a single go like
fping(1). If the measurement takes long enough, there may be not enough time 
perform all the tests in the time available. For example, if the test takes
30 seconds, measuring ten hosts already fills up the SmokePing default 
five minute step.

Thus, it may be necessary to do some of the tests concurrently. This module
defines the B<ping> method that forks the requested number of concurrent 
processes and calls the B<pingone> method that derived classes must provide.

The B<pingone> method is called with one argument: a hash containing
the target that is to be measured. The contents of the hash are
described in I<Smokeping::probes::basevars>(3pm).

The number of concurrent processes is determined by the probe-specific 
variable `forks' and is $DEFAULTFORKS by default. If there are more 
targets than this value, another round of forks is done after the first 
processes are finished. This continues until all the targets have been
tested.

The timeout in which each child has to finish is set to 5 seconds
multiplied by the maximum number of 'pings' of the targets. You can set
the base timeout differently if you want to, using the timeout property
of the probe in the master config file (this again will be multiplied
by the maximum number of pings). The probe itself can also provide
another default value if desired by modifying the _default value of
the timeout variable.

If the child isn't finished when the timeout occurs, it 
will be killed along with any processes it has started.

The number of pings sent can be specified in the target-specific variable
'pings'.
DOC
	authors => <<'DOC',
Niko Tyni <ntyni@iki.fi>
DOC
	see_also => <<DOC,
L<Smokeping::probes::basevars>, L<Smokeping::probes::EchoPing>
DOC
    }
}

my %signo;
my @signame;

{
	# from perlipc man page
	my $i = 0;
	defined $Config{sig_name} || die "No sigs?";
	foreach my $name (split(' ', $Config{sig_name})) {
		$signo{$name} = $i;
		$signame[$i] = $name;
		$i++;
	}
}

die("Missing TERM signal?") unless exists $signo{TERM};
die("Missing KILL signal?") unless exists $signo{KILL};

sub pingone {
	croak "pingone: this must be overridden by the subclass";
}

sub probevars {
	my $class = shift;
	my $h = $class->SUPER::probevars;
	delete $h->{pings};
	return $class->_makevars($h, {
		forks => { 
			_re => '\d+', 
			_example => 5,
			_doc => "Run this many concurrent processes at maximum",
			_default => $DEFAULTFORKS,
		},
		timeout => {
			_re => '\d+', 
			_example => 15,
			_default => 5,
			_doc => "How long a single 'ping' takes at maximum",
		},
	});
}

sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		pings => {
			_re => '\d+', 
			_sub => sub {
				my $val = shift;
				return "ERROR: The pings value must be at least 3."
					if $val < 3;
				return undef;
			},
			_example => 5,
			_doc => <<DOC,
How many pings should be sent to each target, if different from the global
value specified in the Database section. Note that the number of pings in
the RRD files is fixed when they are originally generated, and if you
change this parameter afterwards, you'll have to delete the old RRD
files or somehow convert them.
DOC
		},
	});
}

sub ping {
	my $self = shift;

	# increment the internal 'rounds' counter
	$self->increment_rounds_count;

	my @targets = @{$self->targets};
	return unless @targets;

	my $forks = $self->{properties}{forks};

	my $maxpings = 0;
	my $maxtimeout = $self->{properties}{timeout};
	for (@targets) {
		my $p = $self->pings($_);
		$maxpings = $p if $p > $maxpings;
		# some probes have a target-specific timeout variable
		# dig out the maximum timeout
		my $t = $_->{vars}{timeout};
		$maxtimeout = $t if $t > $maxtimeout;
	}

	# we add 1 so that the probes doing their own timeout handling
	# have time to do it even in the worst case
	my $timeout = $maxpings * $maxtimeout + 1;

        $self->{rtts}={};
	$self->do_debug("forks $forks, timeout for each target $timeout");

	while (@targets) {
		my %targetlookup;
		my %pidlookup;
		my $s = IO::Select->new();
		my $starttime = time();
		for (1..$forks) {
			last unless @targets;
			my $t = pop @targets;
			my $pid;
			my $handle = gensym;
			my $sleep_count = 0;
			do {
				$pid = open($handle, "-|");

				unless (defined $pid) {
					$self->do_log("cannot fork: $!");
					$self->fatal("bailing out") 
						if $sleep_count++ > 6;
					sleep 10;
				}
			} until defined $pid;
			if ($pid) { #parent
				$s->add($handle);
				$targetlookup{$handle} = $t;
				$pidlookup{$handle} = $pid;
			} else { #child
				# we detach from the parent's process group
				setpgrp(0, $$);

                # re-initialize the RNG for each subprocess
                srand(time()+$$);

				my @times = $self->pingone($t);
				print join(" ", @times), "\n";
				exit;
			}
		}
		my $timeleft = $timeout - (time() - $starttime);

		while ($s->handles and $timeleft > 0) {
			for my $ready ($s->can_read($timeleft)) {
				$s->remove($ready);
				my $response = <$ready>;
				close $ready;

				chomp $response;
				my @times = split(/ /, $response);
				my $target = $targetlookup{$ready};
				my $tree = $target->{tree};
				$self->{rtts}{$tree} = \@times;

				$self->do_debug("$target->{addr}: got $response");
			}
			$timeleft = $timeout - (time() - $starttime);
		}
		my @left = $s->handles;
		for my $handle (@left) {
			$self->do_log("$targetlookup{$handle}{addr}: timeout ($timeout s) reached, killing the probe.");

			# we kill the child's process group (negative signal) 
			# this should finish off the actual pinger process as well

			my $pid = $pidlookup{$handle};
			kill -$signo{TERM}, $pid;
			sleep 1;
			kill -$signo{KILL}, $pid;

			close $handle;
			$s->remove($handle);
		}
	}
}

# the "private" method that takes a "tree" argument is used by Smokeping.pm
sub _pings {
	my $self = shift;
	my $tree = shift;
	my $vars = $self->vars($tree);
	return $vars->{pings} if defined $vars->{pings};
	return $self->SUPER::pings();
}

# the "public" method that takes a "target" argument is used by the probes
sub pings {
	my $self = shift;
	my $target = shift;
	return $self->SUPER::pings() unless ref $target;
	return $self->_pings($target->{tree});
}

sub ProbeDesc {
	return "Probe that can fork and doesn't override the ProbeDesc method";
}

sub pod_variables {
	my $class = shift;
	my $pod = $class->SUPER::pod_variables;
	my $targetvars = $class->targetvars;
	$pod .= "Supported target-specific variables:\n\n";
	$pod .= $class->_pod_variables($targetvars);
	return $pod;
}

1;
