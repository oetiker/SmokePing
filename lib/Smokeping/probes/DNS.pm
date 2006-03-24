package Smokeping::probes::DNS;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::DNS>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::DNS>

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
Smokeping::probes::DNS - Name Service Probe for SmokePing
DOC
		description => <<DOC,
Integrates dig as a probe into smokeping. The variable B<binary> must
point to your copy of the dig program. If it is not installed on
your system yet, you should install bind-utils >= 9.0.0.

The Probe asks the given host n-times for it's name. Where n is
the amount specified in the config File.
DOC
		authors => <<'DOC',
 Igor Petrovski <pigor@myrealbox.com>,
 Carl Elkins <carl@celkins.org.uk>,
 Andre Stolze <stolze@uni-muenster.de>,
 Niko Tyni <ntyni@iki.fi>,
 Chris Poetzel<cpoetzel@anl.gov>
DOC
	};
}

my $dig_re=qr/query time:\s+([0-9.]+)\smsec.*/i;

sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {
        
        my $call = "$self->{properties}{binary} localhost";
        my $return = `$call 2>&1`;
        if ($return =~ m/$dig_re/s){
            $self->{pingfactor} = 1000;
            print "### parsing dig output...OK\n";
        } else {
            croak "ERROR: output of '$call' does not match $dig_re\n";
        }
    };

    return $self;
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		_mandatory => [ 'binary' ],
		binary => { 
			_doc => "The location of your dig binary.",
			_example => '/usr/bin/dig',
			_sub => sub { 
				my $val = shift;
        			return "ERROR: DNS 'binary' does not point to an executable"
            				unless -f $val and -x _;
				return undef;
			},
		},
	});
}

sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		lookup => { _doc => "Name of the host to look up in the dns.",
			    _example => "www.example.org",
		},
                server => { _doc => "Name of the dns server to use.",
                            _example => "ns1.someisp.net",
                },
	});
}

sub ProbeDesc($){
    my $self = shift;
    return "DNS requests";
}

sub pingone ($){
    my $self = shift;
    my $target = shift;

    my $inh = gensym;
    my $outh = gensym;
    my $errh = gensym;

    my $host = $target->{addr};
    my $lookuphost = $target->{vars}{lookup};
    $lookuphost = $target->{addr} unless defined $lookuphost;
    my $dnsserver = $target->{vars}{server} || $host;
    my $query = "$self->{properties}{binary} \@$dnsserver $lookuphost";

    my @times;

    $self->do_debug("query=$query\n");
    for (my $run = 0; $run < $self->pings($target); $run++) {
	my $pid = open3($inh,$outh,$errh, $query);
	while (<$outh>) {
	    if (/$dig_re/i) {
		push @times, $1;
		last;
	    }
	}
	waitpid $pid,0;
	close $errh;
	close $inh;
	close $outh;
    }
    @times = map {sprintf "%.10e", $_ / $self->{pingfactor}} sort {$a <=> $b} grep {$_ ne "-"} @times;

#    $self->do_debug("time=@times\n");
    return @times;
}

1;
