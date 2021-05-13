package Smokeping::probes::speedtestcli;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::speedtestcli>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::speedtestcli>

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
Smokeping::probes::speedtestcli - Execute tests via Speedtest.net (official ookla speedtest client)
DOC
		description => <<DOC,
Integrates L<speedtest|https://www.speedtest.net/apps/cli> as a probe into smokeping. The variable B<binary> must
point to your copy of the speedtest program. If it is not installed on
your system yet, you should install the latest version from L<https://www.speedtest.net/apps/cli>.

The Probe asks for the given resource one time, ignoring the pings config variable (because pings can't be lower than 3).

You can ask for a specific server (via the server parameter) 
DOC
		authors => <<'DOC',
 Florian Jensen <https://github.com/flosoft>
 Adrian Popa <mad_ady@yahoo.com>
DOC
	};
}

#Set up syslog to write to local0
openlog("speedtestcli", "nofatal, pid", "local0");
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
        #speedtest crashes if there is no HOME environment set, so force it to /tmp in case there is none
        if(!defined $ENV{'HOME'}){
            $ENV{'HOME'} = '/tmp';
        }
    
        my $call = "$self->{properties}{binary} --version";
        my $return = `$call 2>&1 | head -n 1`;
        if ($return =~ / ([0-9\.]+) /){
            print "### parsing $self->{properties}{binary} output... OK (version $1)\n";
            syslog("debug", "[Speedtestcli] Init: version $1");
        } else {
            croak "ERROR: output of '$call' does not return a meaningful version number. Is speedtest installed?\n";
        }
    };

    return $self;
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		_mandatory => [ 'binary' ],
		binary => { 
			_doc => "The location of your speedtest binary.",
			_example => '/usr/bin/speedtest',
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
		server => { _doc => "The server id you want to test against (optional). If unspecified, speedtest.net will select the closest server to you. The value has to be an id reported by the command speedtest -L",
			    _example => "1234",
		},
        measurement => { _doc => "What output do you want graphed? Supported values are: download, upload",
                    _example => "download",
        },
	extraargs => { _doc => "Append extra arguments to the speedtest comand line",
                    _example => "--foo --bar",
        },
	});
}

sub ProbeDesc($){
    my $self = shift;
    return "Ookla speedtest.net download/upload speeds";
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
    my $query = "$self->{properties}{binary} ".((defined($server))?"--server-id $server":"")." -f json --accept-license --accept-gdpr 2>&1 | tail -1";

    my @times;

    $self->do_debug("[Speedtestcli] query=$query\n");
    syslog("debug", "[Speedtestcli] query=$query");
#    for (my $run = 0; $run < $self->pings($target); $run++) {
	my $pid = open3($inh,$outh,$errh, $query);
	while (<$outh>) {
        $self->do_debug("[Speedtestcli] output: ".$_);
        syslog("debug", "[Speedtestcli] output: ".$_);
        my ($value) = /"$measurement":\{"bandwidth":([0-9]+)/;
        my $normalizedvalue = $value * 8;
        $self->do_debug("[Speedtestcli] Got value: $value, unit: 8 -> $normalizedvalue\n");
        syslog("debug","[Speedtestcli] Got value: $value, unit: 8 -> $normalizedvalue\n");

        push @times, $normalizedvalue;
        last;
      
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

    $self->do_debug("[Speedtestcli] time=@times\n");
    syslog("debug", "[Speedtestcli] time=@times");
    return @times;
}
1;
