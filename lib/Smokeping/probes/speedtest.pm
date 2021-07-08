package Smokeping::probes::speedtest;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::speedtest>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::speedtest>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork);
use IPC::Open3;
use Symbol;
use Carp;
use Sys::Syslog qw(:standard :macros);;

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::speedtest - Execute tests via Speedtest.net
DOC
		description => <<DOC,
Integrates L<speedtest-cli|https://github.com/sivel/speedtest-cli> as a probe into smokeping. The variable B<binary> must
point to your copy of the speedtest-cli program. If it is not installed on
your system yet, you should install the latest version from L<https://github.com/sivel/speedtest-cli>.

The Probe asks for the given resource one time, ignoring the pings config variable (because pings can't be lower than 3).

You can ask for a specific server (via the server parameter) and record a specific output (via the measurement parameter).

DOC
		authors => <<'DOC',
 Adrian Popa <mad_ady@yahoo.com>
DOC
	};
}

#Set up syslog to write to local0
openlog("speedtest", "nofatal, pid", "local0");
#set to LOG_ERR to disable debugging, LOG_DEBUG to enable debugging
setlogmask(LOG_MASK(LOG_ERR));
 
sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {
        
        #check for dependencies
        my $call = "$self->{properties}{binary} --version";
        my $return = `$call 2>&1`;
        if ($return =~ /([0-9\.]+)/){
            print "### parsing $self->{properties}{binary} output... OK (version $1)\n";
            syslog("debug", "[Speedtest] Init: version $1");
        } else {
            croak "ERROR: output of '$call' does not return a meaningful version number. Is speedtest-cli installed?\n";
        }
    };

    return $self;
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		_mandatory => [ 'binary' ],
		binary => { 
			_doc => "The location of your speedtest-cli binary.",
			_example => '/usr/local/bin/speedtest-cli',
			_sub => sub { 
				my $val = shift;
        			return "ERROR: speedtest 'binary' does not point to an executable"
            				unless -f $val and -x _;
				return undef;
			},
		},
	});
}

sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		server => { _doc => "The server id you want to test against (optional). If unspecified, speedtest.net will select the closest server to you. The value has to be an id reported by the command speedtest-cli --list",
			    _example => "1234",
		},
        measurement => { _doc => "What output do you want graphed? Supported values are: ping, download, upload",
                    _example => "download",
        },
	extraargs => { _doc => "Append extra arguments to the speedtest-cli comand line",
                    _example => "--secure",
        },
	});
}

sub ProbeDesc($){
    my $self = shift;
    return "speedtest.net download/upload speeds";
}

sub ProbeUnit($){
    my $self = shift;
    #TODO: We need to know if we are measuring bps or seconds - depending on measurement (or maybe on probe name).
    return "bps";
}

sub pingone ($){
    my $self = shift;
    my $target = shift;

    my $inh = gensym;
    my $outh = gensym;
    my $errh = gensym;

    my $server = $target->{vars}{server} || undef; #if server is not provided, use the default one recommended by speedtest.
    my $measurement = $target->{vars}{measurement} || "download"; #record download speeds if nothing is returned
    my $extra = $target->{vars}{extraargs} || ""; #append extra arguments if neded
    my $query = "$self->{properties}{binary} ".((defined($server))?"--server $server":"")." ".(($measurement eq "download")?"--no-upload":"--no-download")." --simple $extra 2>&1";

    my @times;

    $self->do_debug("query=$query\n");
    syslog("debug", "[Speedtest] query=$query");
#    for (my $run = 0; $run < $self->pings($target); $run++) {
	my $pid = open3($inh,$outh,$errh, $query);
	while (<$outh>) {
        $self->do_debug("output: ".$_);
        syslog("debug", "[Speedtest] output: ".$_);
	    if (/$measurement/i) {
            #sample output:
            #Ping: 2.826 ms
            #Download: 898.13 Mbit/s
            #Upload: 420.01 Mbit/s
            
            my ($value, $unit) = /([0-9\.]+) ([A-Za-z\/]+)/;
            #we're not always measuring seconds, but ProbeUnit() should provide the correct unit for the Y Axis
            
            #normalize the units to be in the same base.
            my $factor = 1; 
            $factor = 0.001 if($unit eq 'ms');
            $factor = 1_000 if($unit eq 'Kbit/s' || $unit eq 'kbit/s');
            $factor = 1_000_000 if($unit eq 'Mbit/s' || $unit eq 'mbit/s');
            $factor = 1_000_000_000 if($unit eq 'Gbit/s' || $unit eq 'gbit/s');
            
            my $normalizedvalue = $value * $factor;
            $self->do_debug("Got value: $value, unit: $unit -> $normalizedvalue\n");
            syslog("debug","[Speedtest] Got value: $value, unit: $unit -> $normalizedvalue\n");
            
            push @times, $normalizedvalue;
            last;
	    }
	}
	waitpid $pid,0;
	close $errh;
	close $inh;
	close $outh;
#    }
    #we run only one test (in order not to get banned too soon), so we ignore pings and have to return the correct number of values. Uncomment the above for loop if you want the actual testing to be done $ping times.
    my $value = $times[0];
    @times = ();
    for(my $run = 0; $run < $self->pings($target); $run++) {
        push @times, $value;
    }
    
    @times = map {sprintf "%.10e", $_ } sort {$a <=> $b} grep {$_ ne "-"} @times;

    $self->do_debug("time=@times\n");
    syslog("debug", "[Speedtest] time=@times");
    return @times;
}
1;
