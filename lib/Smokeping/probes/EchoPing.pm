package Smokeping::probes::EchoPing;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::EchoPing>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::EchoPing>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork);
use Carp;

my $DEFAULTBIN = "/usr/bin/echoping";

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::EchoPing - an echoping(1) probe for SmokePing
DOC
		overview => <<DOC,
Measures TCP or UDP echo (port 7) roundtrip times for SmokePing. Can also be 
used as a base class for other echoping(1) probes.
DOC
		description => <<DOC,
See echoping(1) for details of the options below.
DOC
		bugs => <<DOC,
Should we test the availability of the service at startup? After that it's
too late to complain.

The location of the echoping binary should probably be a global variable
instead of a probe-specific one. As things are, every EchoPing -derived probe 
has to declare it if the default ($DEFAULTBIN) isn't correct.
DOC
		authors => <<'DOC',
Niko Tyni <ntyni@iki.fi>
DOC
		see_also => <<DOC,
echoping(1), L<Smokeping::probes::EchoPingHttp> etc., L<http://echoping.sourceforge.net/>
DOC
	}
}

#
# derived class will mess with this through the 'features' method below
my $featurehash = {
	waittime => "-w",
	timeout => "-t",
	size => "-s",
	tos => "-P",
	priority => "-p",
	fill => "-f",
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

	return $self;
}

sub ProbeDesc($) {
	return "TCP or UDP Echo pings using echoping(1)";
}

# This can be overridden to tag the port number to the address
# in derived classes (namely EchoPingHttp)
sub make_host {
	my $self = shift;
	my $target = shift;
	return $target->{addr};
}

# This will be overridden by the EchoPingPlugin-derived probes
sub post_args {
    return ();
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
	push @args, $self->ipversion_arg($target);
	push @args, $target->{vars}{extraopts} if exists $target->{vars}{extraopts};

	return @args;
}

# this is separated to make it possible to test the service
# at startup, although we don't do it at the moment.
sub count_args {
	my $self = shift;
	my $count = shift;

	$count = $self->pings() unless defined $count;
	return ("-n", $count);
}

# This is what derived classes will override
sub proto_args {
	my $self = shift;
	return $self->udp_arg(@_);
}

# UDP is defined only for echo and discard
sub udp_arg {
	my $self = shift;
	my $target = shift;
	my @args;

	my $udp = $target->{vars}{udp};
	push @args, "-u" if (defined $udp and $udp ne "no" and $udp ne "0");

	return @args;
}

sub ipversion_arg {
	my $self = shift;
	my $target = shift;
	my $vers = $target->{vars}{ipversion};
	if (defined $vers and $vers =~ /^([46])$/) {
		return ("-" . $1);
	} else {
		$self->do_log("Invalid `ipversion' value: $vers") if defined $vers;
		return ();
	}
}

sub make_commandline {
	my $self = shift;
	my $target = shift;
	my $count = shift;

	$count |= $self->pings($target);

	my @args = $self->make_args($target);
	my @post_args = $self->post_args($target);
	my $host = $self->make_host($target);
	push @args, $self->proto_args($target);
	push @args, $self->count_args($count);
	
	return ($self->{properties}{binary}, @args, $host, @post_args);
}

sub pingone {
	my $self = shift;
	my $t = shift;

	my @cmd = $self->make_commandline($t);

	my $cmd = join(" ", @cmd);

	$self->do_debug("executing cmd $cmd");

	my @times;

	open(P, "$cmd 2>&1 |") or carp("fork: $!");
	
	my @output;
	while (<P>) {
		chomp;
		push @output, $_;
		/^Elapsed time: (\d+\.\d+) seconds/ and push @times, $1;
	}
	close P;
	if ($?) {
		my $status = $? >> 8;
		my $signal = $? & 127;
		my $why = "with status $status";
		$why .= " [signal $signal]" if $signal;

		# only log warnings on the first ping round
		my $function = ($self->rounds_count == 1 ? "do_log" : "do_debug");

		$self->$function(qq(WARNING: "$cmd" exited $why - output follows));
		$self->$function(qq(         $_)) for @output;
	}
	# carp("Got @times") if $self->debug;
	return sort { $a <=> $b } @times;
}

sub probevars {
	my $class = shift;
	my $h = $class->SUPER::probevars;
	delete $h->{timeout};
	return $class->_makevars($h, {
		binary => {
			_doc => "The location of your echoping binary.",
			_default => $DEFAULTBIN,
			_sub => sub {
				my $val = shift;
				-x $val or return "ERROR: binary '$val' is not executable";
				return undef;
			},
		},
	});
}

sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		timeout => {
			_doc => 'The "-t" echoping(1) option.',
			_example => 1,
			_default => 5,
			_re => '(\d*\.)?\d+',
		},
		waittime => {
			_doc => 'The "-w" echoping(1) option.',
			_example => 1,
			_re => '\d+',
		},
		size => {
			_doc => 'The "-s" echoping(1) option.',
			_example => 510,
			_re => '\d+',
		},
		udp => {
			_doc => q{The "-u" echoping(1) option. Values other than '0' and 'no' enable UDP.},
			_example => 'no',
		},
		fill => {
			_doc => 'The "-f" echoping(1) option.',
			_example => 'A',
			_re => '.',
		},
		priority => {
			_doc => 'The "-p" echoping(1) option.',
			_example => 6,
			_re => '\d+',
		},
		tos => {
			_doc => 'The "-P" echoping(1) option.',
			_example => '0xa0',
		},
		ipversion => {
			_doc => <<DOC,
The IP protocol used. Possible values are "4" and "6". 
Passed to echoping(1) as the "-4" or "-6" options.
DOC
			_example => 4,
			_re => '[46]'
		},
		extraopts => {
			_doc => 'Any extra options specified here will be passed unmodified to echoping(1).',
			_example => '-some-letter-the-author-did-not-think-of',
		},
	});
}

1;
