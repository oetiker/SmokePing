package Smokeping::probes::Curl;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::Curl>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::Curl>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork);
use Carp;

my $DEFAULTBIN = "/usr/bin/curl";

sub pod_hash {
    return {
	name => "Smokeping::probes::Curl - a curl(1) probe for SmokePing",
	overview => "Fetches an HTTP or HTTPS URL using curl(1).",
	description => "(see curl(1) for details of the options below)",
	authors => <<'DOC',
 Gerald Combs <gerald [AT] ethereal.com>
 Niko Tyni <ntyni@iki.fi>
DOC
	notes => <<DOC,
The URL to be tested used to be specified by the variable 'url' in earlier
versions of Smokeping, and the 'host' setting did not influence it in any
way. The variable name has now been changed to 'urlformat', and it can
(and in most cases should) contain a placeholder for the 'host' variable.
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
the words "User-Agent:".  It should be enclosed in quotes if it contains
shell metacharacters.
DOC
			_example => '"User-Agent: Lynx/2.8.4rel.1 libwww-FM/2.14 SSL-MM/1.4.1 OpenSSL/0.9.6c"',
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
	my $url = $target->{vars}{urlformat};
	my $host = $target->{addr};
	$url =~ s/%host%/$host/g;
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
