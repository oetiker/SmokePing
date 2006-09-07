package Smokeping::probes::WebProxyFilter;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::WebProxyFilter>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::WebProxyFilter>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork);
use LWP::UserAgent;
use Time::HiRes qw(gettimeofday sleep);
use Carp;

my $DEFAULTINTERVAL = 1;

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::WebProxyFilter - tests webproxy filter performance and function.
DOC
		overview => <<DOC,
This probe tests if your filtering webproxy is working properly. Drawing from
a list of forbidden websites, it tries to establish a connection to
each one of them and registers a 'loss' when it suceeeds.

If you want to test availability of a website, use the EchoPingHttp probe.
DOC
		description => <<DOC,
The probe uses the LWP::UserAgent module to retreive a series of wepages. It
expects to get the firewalls 'site-prohibited' page. Any other response (or
a real loss) gets logged as a loss and can be used to trigger an alarm.

The probe tries to be nice to the firewall and waits at least X seconds
between starting filetransfers, where X is the value of the probe 
specific `min_interval' variable ($DEFAULTINTERVAL by default).

Many variables can be specified either in the probe or in the target definition,
the target-specific variable will override the prove-specific variable.
DOC
		authors => <<'DOC',
Tobias Oetiker <tobi@oetiker.ch> sponsored by Virtela
DOC
		bugs => <<DOC,
This probe is somewhat unortodox, since it regards the sucessful retrieval
of a banned webpage as a loss.
DOC
	}
}

sub ProbeDesc ($) {
        my $self = shift;  
	return sprintf("HTTP GETs");
}

sub new {
        my $proto = shift;
        my $class = ref($proto) || $proto;
        my $self = $class->SUPER::new(@_);
        return $self;
}

sub pingone {
	my $self = shift;
	my $target = shift;
	my $host = $target->{addr};
	my $vars = $target->{vars};
	my $mininterval = $self->{properties}{min_interval};
	my @times;
	my $elapsed;
	my $ua = LWP::UserAgent->new;
	$ua->agent($vars->{useragent});
	$ua->timeout($vars->{timeout});
	$ua->max_size($vars->{max_size});
	my @targets = ($host, split /\s*,\s*/, $vars->{more_hosts});
	my $targcount = scalar @targets;
	my $pingcount = $self->pings($target);
	my $deny_re = $vars->{deny_re};
	if ($targcount > $self->pings($target)) {
		$self->do_log("ERROR There are more host addresses ($targcount) than ping slots ($pingcount), either increasse the pings or reduce the targets.\n");
		return;
	}
	
	for (1..$pingcount) {
		if (defined $elapsed) {
			my $timeleft = $mininterval - $elapsed;
			sleep $timeleft if $timeleft > 0;
		}
		my $target = shift @targets;
		push @targets,$target;
		my $start = gettimeofday();
		my $response = $ua->get("http://$target");
		my $end = gettimeofday();
	        if ($response->is_success){
		    if ($response->content =~ /$deny_re/ism){
			    push @times,($end-$start);
		    } else {
			my $content = substr($response->content,0,80)." ...";
			$content =~ s/[\n\r]/ /g;
			$self->do_log("Warning: Problem with target $host: got unexpected content from $target: $content");
		    }
        	} else {
	            $self->do_log("Warning: Problem with target $host: got this error from $target: ".$response->status_line);
		}
        }
	return sort { $a <=> $b } @times;
}

sub probevars {
	my $class = shift;
	my $h = $class->SUPER::probevars;
	return $class->_makevars($h, {
		_mandatory => ['deny_re'],
		min_interval => {
                        _default => $DEFAULTINTERVAL,
                        _doc => "The minimum interval between each starting GETs in seconds.",
                        _re => '(\d*\.)?\d+',
			_example => '0.1'
		},
		useragent => {
			_default => "SmokePing/2.x (WebProxyFilter Probe)",
			_doc => "The web browser we claim to be, just in case the FW is interested"
		},
		maxsize => {
			_default => 2000,
			_doc => "How much of the webpage should be retreived."
		},			
			
	});	
}
		
sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		timeout => {
			_default => 2,
			_doc => "Timeout in seconds for the test complete.",
			_re => '\d+',
			_example => 2,
		},
		deny_re => {
			_doc => "Regular expression, matching the 'deny' response from the firewall",
			_example => 'Access Prohibited',
		},
		more_hosts => {
			_doc => <<DOC,
A comma separated list of banned websites to test in addition to the one
specified in the I<host> variable. The websites will be tested one after the
other in one round, this means that while normal probes do run the same test
serveral times in a row, this one will alter the webpage with each round.
The reason for this is, that eventhough we try to retreive remote webpages,
the answer will come from the firewall everytime, so we kill two birds in
one go. First we test the firewalls latency and second we make sure its
filter works properly.
DOC
			_re => '[^\s.]+(?:\.[^\s.]+)*(\s*,[^\s.]+(?:\.[^\s.]+)*)*',
			_example => 'www.playboy.com, www.our-competition.com',
		},
		
	});
}

1;
