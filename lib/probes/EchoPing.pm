package probes::EchoPing;

my $DEFAULTBIN = "/usr/bin/echoping";

=head1 NAME

probes::EchoPing - an echoping(1) probe for SmokePing

=head1 OVERVIEW

Measures TCP or UDP echo (port 7) roundtrip times for SmokePing. Can also be 
used as a base class for other echoping(1) probes.

=head1 SYNOPSYS

 *** Probes ***
 + EchoPing

 binary = /usr/bin/echoping # default value

 *** Targets ***

 probe = EchoPing
 forks = 10

 menu = Top
 title = Top Menu
 remark = Top Menu Remark

 + PROBE_CONF

 # none of these are mandatory
 timeout = 1
 waittime = 1
 udp = no
 size = 510
 tos = 0xa0
 priority = 6
 
 + First
 menu = First
 title = First Target
 host = router.example.com

 # PROBE_CONF can be overridden here
 ++ PROBE_CONF
 size = 300

=head1 DESCRIPTION

Supported probe-specific variables:

=over

=item binary

The location of your echoping binary.

=item forks

The number of concurrent processes to be run. See probes::basefork(3pm) 
for details.

=back

Supported target-level probe variables 
(see echoping(1) for details of the options):

=over

=item timeout

The "-t" echoping(1) option. 

=item waittime

The "-w" echoping(1) option. 

=item size

The "-s" echoping(1) option. 

=item udp

The "-u" echoping(1) option. Values other than '0' and 'no' enable UDP.

=item fill

The "-f" echoping(1) option. 

=item priority

The "-p" echoping(1) option.

=item tos

The "-P" echoping(1) option.

=item ipversion

The IP protocol used. Possible values are "4" and "6". 
Passed to echoping(1) as the "-4" or "-6" options.

=item extraopts

Any extra options specified here will be passed unmodified to echoping(1).

=back

=head1 BUGS

Should we test the availability of the service at startup? After that it's
too late to complain.

The location of the echoping binary should probably be a global variable
instead of a probe-specific one. As things are, every EchoPing -derived probe 
has to declare it if the default (/usr/bin/echoping) isn't correct.

=head1 AUTHOR

Niko Tyni E<lt>ntyni@iki.fiE<gt>

=head1 SEE ALSO

echoping(1), probes::EchoPingHttp(3pm) etc., http://echoping.sourceforge.net/

=cut

use strict;
use base qw(probes::basefork);
use Carp;
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

	unless (defined $self->{properties}{binary}) {
		$self->{properties}{binary} = $DEFAULTBIN;
	}
	croak "ERROR: EchoPing 'binary' $self->{properties}{binary} does not point to an executable"
		unless -f $self->{properties}{binary} and -x $self->{properties}{binary};

	$self->test_usage;

	return $self;
}

# warn about unsupported features
sub test_usage {
	my $self = shift;
	my $bin = $self->{properties}{binary};
	my @unsupported;

	my $arghashref = $self->features;
	my %arghash = %$arghashref;

	for my $feature (keys %arghash) {
		if (`$bin $arghash{$feature} 1 127.0.0.1 2>&1` =~ /invalid option|usage/i) {
			push @unsupported, $feature;
			$self->do_log("Note: your echoping doesn't support the $feature feature (option $arghash{$feature}), disabling it");
		}
	}
	map { delete $arghashref->{$_} } @unsupported;

	return;
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


# other than host, count and protocol-specific args come from here
sub make_args {
	my $self = shift;
	my $target = shift;
	my @args;
	my %arghash = %{$self->features};

	for (keys %arghash) {
		my $val = $target->{vars}{$_};
		$val = $self->{properties}{$_} unless defined $val;
		push @args, ($arghash{$_}, $val) if defined $val;
	}
	push @args, $self->ipversion_arg($target);
	push @args, $self->{properties}{extraopts} if exists $self->{properties}{extraopts};
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
	$udp = $self->{properties}{udp} unless defined $udp;
	push @args, "-u" if (defined $udp and $udp ne "no" and $udp ne "0");

	return @args;
}

sub ipversion_arg {
	my $self = shift;
	my $target = shift;
	my $vers = $target->{vars}{ipversion};
	$vers = $self->{properties}{ipversion} unless defined $vers;
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
	my $host = $self->make_host($target);
	push @args, $self->proto_args($target);
	push @args, $self->count_args($count);
	
	return ($self->{properties}{binary}, @args, $host);
}

sub pingone {
	my $self = shift;
	my $t = shift;

	my @cmd = $self->make_commandline($t);

	my $cmd = join(" ", @cmd);

	$self->do_debug("executing cmd $cmd");

	my @times;

	open(P, "$cmd 2>&1 |") or carp("fork: $!");
	
	# what should we do with error messages?
	my $echoret;
	while (<P>) {
		$echoret .= $_;
		/^Elapsed time: (\d+\.\d+) seconds/ and push @times, $1;
	}
	close P;
	carp "WARNING: $cmd was not happy: $echoret\n" if $?;
	# carp("Got @times") if $self->debug;
	return sort { $a <=> $b } @times;
}

1;
