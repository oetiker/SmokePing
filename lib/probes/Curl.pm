package probes::Curl;

my $DEFAULTBIN = "/usr/bin/curl";

=head1 NAME

probes::Curl - a curl(1) probe for SmokePing

=head1 OVERVIEW

Fetches an HTTP or HTTPS URL using curl(1).

=head1 SYNOPSYS

 *** Probes ***
 + Curl

 binary = /usr/bin/curl # default value

 *** Targets ***

 probe = Curl
 forks = 10

 menu = Top
 title = Top Menu
 remark = Top Menu Remark

 + PROBE_CONF

 + First
 menu = First
 title = First Target
 host = some.host

 # PROBE_CONF can be overridden here
 ++ PROBE_CONF
 agent = "User-Agent: Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.2.1) Gecko/20021130"
 url = https://some.host/some/where

=head1 DESCRIPTION

Supported probe-specific variables:

=over

=item binary

The location of your curl binary.

=item forks

The number of concurrent processes to be run. See probes::basefork(3pm)
for details.

=item url

The URL to fetch.  Can be any one that curl supports.

=back

Supported target-level probe variables 
(see curl(1) for details of the options):

=over

=item agent

The "-A" curl(1) option.  This is a full HTTP User-Agent header including
the words "User-Agent:".  It should be enclosed in quotes if it contains
shell metacharacters

=item ssl2

The "-2" curl(1) option.  Force SSL2.

=item timeout

The "-m" curl(1) option.  Maximum timeout in seconds.

=item interface

The "--interface" curl(1) option.  Bind to a specific interface, IP address or
host name.

=back

=head1 AUTHORS

Gerald Combs E<lt>gerald [AT] ethereal.comE<gt>
Niko Tyni E<lt>ntyni@iki.fiE<gt>

=head1 SEE ALSO

curl(1), probes::Curl(3pm) etc., http://curl.haxx.se/

=cut

use strict;
use base qw(probes::basefork);
use Carp;
#
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

	unless (defined $self->{properties}{binary}) {
		$self->{properties}{binary} = $DEFAULTBIN;
	}
	croak "ERROR: Curl 'binary' $self->{properties}{binary} does not point to an executable"
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
			$self->do_log("Note: your curl doesn't support the $feature feature (option $arghash{$feature}), disabling it");
		}
	}
	map { delete $arghashref->{$_} } @unsupported;

	return;
}

sub ProbeDesc($) {
	return "HTTP, HTTPS, and FTP URLs using curl(1)";
}

# This can be overridden to tag the port number to the address
# in derived classes (namely Curl)
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
	return @args;
}

# This is what derived classes will override
sub proto_args {
	my $self = shift;
	my $target = shift;
	# XXX - It would be neat if curl had a "time_transfer".  For now,
	# we take the total time minus the DNS lookup time.
	my @args = ("-o /dev/null", "-w 'Time: %{time_total} DNS time: %{time_namelookup}\\n'");
	my $ssl2 = $target->{vars}{ssl2};
	push (@args, "-2") if defined($ssl2);
	return(@args);

}

sub make_commandline {
	my $self = shift;
	my $target = shift;
	my $count = shift;

	my @args = $self->make_args($target);
	my $url = $target->{vars}{url};
	$url = "" unless defined $url;
	push @args, $self->proto_args($target);
	
	return ($self->{properties}{binary}, @args, $url);
}

sub pingone {
	my $self = shift;
	my $t = shift;

	my @cmd = $self->make_commandline($t);

	my $cmd = join(" ", @cmd);

	$self->do_debug("executing cmd $cmd");

	my @times;
	my $count = $self->pings($t);

	for (my $i = 0 ; $i < $count; $i++) {
		open(P, "$cmd 2>&1 |") or croak("fork: $!");

		# what should we do with error messages?
		while (<P>) {
			/^Time: (\d+\.\d+) DNS time: (\d+\.\d+)/ and push @times, $1 - $2;
		}
		close P;
	}
	
	# carp("Got @times") if $self->debug;
	return sort { $a <=> $b } @times;
}

1;
