package Smokeping::probes::YoutubeDL;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::YoutubeDL>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::YoutubeDL>

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
Smokeping::probes::YoutubeDL - Video content downloader for SmokePing
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

my $time_re=qr/^([0-9:\.]+) elapsed$/;
#Set up syslog to write to local0
openlog("YoutubeDL", "nofatal, pid", "local0");
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
            croak "ERROR: output of '$call' does not return a meaningful version number. Is youtube-dl installed?\n";
        }
    };

    return $self;
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		_mandatory => [ 'binary' ],
		binary => { 
			_doc => "The location of your youtube-dl binary.",
			_example => '/usr/local/bin/youtube-dl',
			_sub => sub { 
				my $val = shift;
        			return "ERROR: YoutubeDL 'binary' does not point to an executable"
            				unless -f $val and -x _;
				return undef;
			},
		},
	});
}

sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		url => { _doc => "The URL you want to download. See youtube-dl's list of supported sites (youtube-dl --list-extractor)",
			    _example => "https://www.youtube.com/watch?v=-CmadmM5cOk",
		},
        options => { _doc => "Extra options you wish to pass to youtube-dl. See 'youtube-dl -h' for reference. Default options sent are '-o /dev/null'",
                    _example => "-R 0 --buffer-size 16k --no-continue --print-json",
        },
	});
}

sub ProbeDesc($){
    my $self = shift;
    return "Video downloads";
}

sub pingone ($){
    my $self = shift;
    my $target = shift;

    my $inh = gensym;
    my $outh = gensym;
    my $errh = gensym;

    my $url = $target->{vars}{url} || "https://www.youtube.com/watch?v=-CmadmM5cOk"; #specify a generic URL if none is provided
    my $options = $target->{vars}{options} || " ";
    my $query = "/usr/bin/time -f '%E elapsed' $self->{properties}{binary} $url $options -o /dev/null 2>&1";

    my @times;

    $self->do_debug("query=$query\n");
    syslog("debug", "query=$query");
#    for (my $run = 0; $run < $self->pings($target); $run++) {
	my $pid = open3($inh,$outh,$errh, $query);
    my $time_matched = 0;
    my $error_found = 0;
	while (<$outh>) {
        $self->do_debug("output: ".$_);
        syslog("debug", "output: ".$_);
        if (/(ERROR:.*)/){
            $error_found = 1;
            $self->do_debug("Error while downloading video:$_\n");
            syslog("error", "Error while downloading video:$_\n");
        }
	    if (/$time_re/i) {
            #time is returned like 0:02.13
            $time_matched = 1;
            my $timestamp = $1;
            my $time = 0;
            #convert it to seconds
            if($timestamp=~/([0-9]+):([0-9]+):([0-9\.]+)/){
               my $hours = $1;
               my $minutes = $2;
               my $seconds = $3; #fractional
               $time = $hours * 3600 + $minutes *60 + $seconds;
               $self->do_debug("Timestamp: $timestamp -> $time\n");
               syslog("debug","Timestamp: $timestamp -> $time\n");
            }
            elsif($timestamp=~/([0-9]+):([0-9\.]+)/){
               my $minutes = $1;
               my $seconds = $2; #fractional
               $time = $minutes *60 + $seconds;
               $self->do_debug("Timestamp: $timestamp -> $time\n");
               syslog("debug", "Timestamp: $timestamp -> $time\n");
            }
            else{
                #shouldn't get here
                $self->do_debug("Unsuported format");
            }
            if(! $error_found){
                #record times only when there is no error, otherwise we are measuring script execution time without data download
                push @times, $time;
            }
            else{
                #in case of error, return 0
                push @times, 0;
            }
            last;
	    }
	}
    if(! $time_matched){
        $self->do_debug("Error while parsing command output - couldn't find the time. Is /usr/bin/time installed?\n");
        syslog("error", "Error while parsing command output - couldn't find the time. Is /usr/bin/time installed?\n");
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
    syslog("debug", "time=@times");
    return @times;
}
1;
