package Smokeping::probes::WifiParam;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::WifiParam>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::WifiParam>

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
Smokeping::probes::YoutubeParam - Extract wifi parameters for SmokePing
DOC
		description => <<DOC,
Integrates L<youtube-dl|https://github.com/rg3/youtube-dl/blob/master/README.md> as a probe into smokeping. The variable B<binary> must
point to your copy of the youtube-dl program. If it is not installed on
your system yet, you should install the latest version from L<https://rg3.github.io/youtube-dl/download.html>.

The Probe asks for the given resource one time, ignoring the pings config variable (because pings can't be lower than 3).

Timing the download is done via the /usr/bin/time command (not the shell builtin time!), output is written to /dev/null. By default the best available video quality is requested.

Note: Some services might ban your IP if you do too many queries too often!

DOC
		authors => <<'DOC',
 Adrian Popa <mad_ady@yahoo.com>
DOC
	};
}

#Set up syslog to write to local0
openlog("WifiParam", "nofatal, pid", "local0");
#set to LOG_ERR to disable debugging, LOG_DEBUG to enable it
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
            syslog("debug", "Init: version $1");
        } else {
            croak "ERROR: output of '$call' does not return a meaningful version number. Is iw installed?\n";
        }
    };

    return $self;
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		_mandatory => [ 'binary' ],
		binary => { 
			_doc => "The location of your iw binary.",
			_example => '/sbin/iw',
			_sub => sub { 
				my $val = shift;
        			return "ERROR: iw 'binary' does not point to an executable"
            				unless -f $val and -x _;
				return undef;
			},
		},
	});
}

sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		interface => { _doc => "The name of the wireless interface to monitor",
			    _example => "wlan0",
		},
        parameter => { _doc => "The parameter you want to monitor. One of: freq, signal, bitrate",
                    _example => "freq",
        },
	});
}

sub ProbeDesc($){
    my $self = shift;
    return "Wifi";
}

sub pingone ($){
    my $self = shift;
    my $target = shift;

    my $inh = gensym;
    my $outh = gensym;
    my $errh = gensym;

    my $interface = $target->{vars}{interface} || "wlan0"; #add a generic interface if none specified
    my $parameter = $target->{vars}{parameter} || "freq"; #generic parameter if none specified
    my $query = "$self->{properties}{binary} dev $interface link 2>&1";

    my @params;

    $self->do_debug("query=$query\n");
    syslog("debug", "query=$query");
    for (my $run = 0; $run < $self->pings($target); $run++) {
        my $pid = open3($inh,$outh,$errh, $query);
        while (<$outh>) {
            $self->do_debug("output: ".$_);
            syslog("debug", "output: ".$_);
            if($parameter eq 'freq' && /freq: ([0-9]+)/){
                my $freq = $1;
                $freq=$freq/1000;
                syslog("debug", "Freq: $freq\n");
                push @params, $freq;
                last;
            }
            if($parameter eq 'signal' && /signal: -([0-9]+) dBm/){
                my $signal = $1;
                syslog("debug", "Signal: $signal\n");
                push @params, $signal;
                last;
            }
            if($parameter eq 'bitrate' && /bitrate: ([0-9\.]+) /){
                my $bitrate = $1;
                syslog("debug", "Bitrate: $bitrate\n");
                push @params, $bitrate;
                last;
            }
            
        }
        waitpid $pid,0;
        close $errh;
        close $inh;
        close $outh;
    }
    
    
    my @times = ();
    for(my $run = 0; $run < $self->pings($target); $run++) {
        push @times, $params[$run];
    }
    
    @times = map {sprintf "%.10e", $_ } sort {$a <=> $b} grep {$_ ne "-"} @times;

    $self->do_debug("time=@times\n");
    syslog("debug", "time=@times");
    return @times;
}
1;
