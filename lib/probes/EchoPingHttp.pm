package probes::EchoPingHttp;

=head1 NAME

probes::EchoPingHttp - an echoping(1) probe for SmokePing

=head1 OVERVIEW

Measures HTTP roundtrip times (web servers and caches) for SmokePing.

=head1 SYNOPSYS

 *** Probes ***
 + EchoPingHttp

 binary = /usr/bin/echoping # mandatory
 

 *** Targets ***

 probe = EchoPingHttp

 + PROBE_CONF
 url = / 
 ignore_cache = yes
 revalidate_data = no
 port = 80 # default value anyway
 timeout = 50 # default is 10s

=head1 DESCRIPTION

Supported probe-specific variables: those specified in EchoPing(3pm) 
documentation.

Supported target-specific variables:

=over

=item those specified in EchoPing(3pm) documentation 

except I<fill>, I<size> and I<udp>.

=item url

The URL to be requested from the web server or cache. Can be either relative
(/...) for web servers or absolute (http://...) for caches.

=item port

The TCP port to use. The default is 80.

=item ignore_cache

The echoping(1) "-A" option: force the proxy to ignore the cache.
Enabled if the value is anything other than 'no' or '0'.

=item revalidate_data

The echoping(1) "-a" option: force the proxy to revalidate data with original 
server. Enabled if the value is anything other than 'no' or '0'.

=item timeout

The echoping(1) "-t" option: Number  of  seconds  to  wait a reply before giving up. For TCP,
this is the maximum number of seconds for the  whole  connection
(setup and data exchange).

=back

=head1 AUTHOR

Niko Tyni E<lt>ntyni@iki.fiE<gt>

=head1 SEE ALSO

EchoPing(3pm), EchoPingHttps(3pm)

=cut

use strict;
use base qw(probes::EchoPing);
use Carp;

sub _init {
	my $self = shift;
	# HTTP doesn't fit with filling or size
	my $arghashref = $self->features;
	delete $arghashref->{size};
	delete $arghashref->{fill};
}

# tag the port number after the hostname
sub make_host {
	my $self = shift;
	my $target = shift;

	my $host = $self->SUPER::make_host($target);
	my $port = $target->{vars}{port};
	$port = $self->{properties}{port} unless defined $port;

	$host .= ":$port" if defined $port;
	return $host;
}

sub proto_args {
	my $self = shift;
	my $target = shift;
	my $url = $target->{vars}{url};
	$url = $self->{properties}{url} unless defined $url;
	$url = "/" unless defined $url;

	my @args = ("-h", $url);

	# -t : timeout
	my $timeout = $target->{vars}{timeout};
	$timeout = $self->{properties}{timeout} 
		unless defined $timeout;
	push @args, "-t $timeout" if $timeout;

	# -A : ignore cache
	my $ignore = $target->{vars}{ignore_cache};
	$ignore = $self->{properties}{ignore_cache} 
		unless defined $ignore;
	$ignore = 1 
		if (defined $ignore and $ignore ne "no" 
			and $ignore ne "0");
	push @args, "-A" if $ignore and not exists $self->{_disabled}{A};

	# -a : force cache to revalidate the data
	my $revalidate = $target->{vars}{revalidate_data};
	$revalidate = $self->{properties}{revalidate_data} 
		unless defined $revalidate;
	$revalidate= 1 if (defined $revalidate and $revalidate ne "no" 
		and $revalidate ne "0");
	push @args, "-a" if $revalidate and not exists $self->{_disabled}{a};

	return @args;
}

sub test_usage {
	my $self = shift;
	my $bin = $self->{properties}{binary};
	croak("Your echoping binary doesn't support HTTP")
		if `$bin -h/ 127.0.0.1 2>&1` =~ /(invalid option|not compiled|usage)/i;
	if (`$bin -a -h/ 127.0.0.1 2>&1` =~ /(invalid option|not compiled|usage)/i) {
		carp("Note: your echoping binary doesn't support revalidating (-a), disabling it");
		$self->{_disabled}{a} = undef;
	}

	if (`$bin -A -h/ 127.0.0.1 2>&1` =~ /(invalid option|not compiled|usage)/i) {
		carp("Note: your echoping binary doesn't support ignoring cache (-A), disabling it");
		$self->{_disabled}{A} = undef;
	}

	$self->SUPER::test_usage;
	return;
}

sub ProbeDesc($) {
        return "HTTP pings using echoping(1)";
}


1;
