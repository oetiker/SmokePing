package probes::basefork;

my $DEFAULTFORKS = 5;

=head1 NAME

probes::basefork - Yet Another Base Class for implementing SmokePing Probes

=head1 OVERVIEW

Like probes::basevars, but supports the probe-specific property `forks'
to determine how many processes should be run concurrently. The
targets are pinged one at a time, and the number of pings sent can vary
between targets.

=head1 SYNOPSYS

 *** Probes ***

 + MyForkingProbe
 # run this many concurrent processes
 forks = 10 
 # how long does a single 'ping' take
 timeout = 10
 # how many pings to send
 pings = 10

 + MyOtherForkingProbe
 # we don't want any concurrent processes at all for some reason.
 forks = 1 

 *** Targets ***

 menu = First
 title = First
 host = firsthost
 probe = MyForkingProbe

 menu = Second
 title = Second
 host = secondhost
 probe = MyForkingProbe
 +PROBE_CONF
 pings = 20

=head1 DESCRIPTION

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
described in I<probes::basevars>(3pm).

The number of concurrent processes is determined by the probe-specific 
variable `forks' and is 5 by default. If there are more 
targets than this value, another round of forks is done after the first 
processes are finished. This continues until all the targets have been
tested.

The timeout in which each child has to finish is set to 5 seconds
multiplied by the maximum number of 'pings' of the targets. You can set
the base timeout differently if you want to, using the timeout property
of the probe in the master config file (this again will be multiplied
by the maximum number of pings). The probe itself can also override the
default by providing a TimeOut method which returns an integer.

If the child isn't finished when the timeout occurs, it 
will be killed along with any processes it has started.

The number of pings sent can be specified in the probe-specific variable
'pings', and it can be overridden by each target in the 'PROBE_CONF'
section.

=head1 AUTHOR

Niko Tyni E<lt>ntyni@iki.fiE<gt>

=head1 BUGS

The timeout code has only been tested on Linux.

=head1 SEE ALSO

probes::basevars(3pm), probes::EchoPing(3pm)

=cut

use strict;
use base qw(probes::basevars);
use Symbol;
use Carp;
use IO::Select;
use POSIX; # for ceil() and floor()
use Config; # for signal names

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

sub TimeOut {
	# probes which require more time may want to provide their own implementation.
	return 5;
}

sub ping {
	my $self = shift;

	my @targets = @{$self->targets};
	return unless @targets;

	my $forks = $self->{properties}{forks} || $DEFAULTFORKS;

	my $timeout = $self->{properties}{timeout};
	unless (defined $timeout and $timeout > 0) {
		my $maxpings = 0;
		for (@targets) {
			my $p = $self->pings($_);
			$maxpings = $p if $p > $maxpings;
		}
		$timeout = $maxpings * $self->TimeOut();
	}

        $self->{rtts}={};
	$self->do_debug("forks $forks, timeout per target $timeout");

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

1;
