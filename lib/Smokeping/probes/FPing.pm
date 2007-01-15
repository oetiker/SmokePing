package Smokeping::probes::FPing;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::FPing>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::FPing>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::base);
use IPC::Open3;
use Symbol;
use Carp;

sub pod_hash {
      return {
              name => <<DOC,
Smokeping::probes::FPing - FPing Probe for SmokePing
DOC
              description => <<DOC,
Integrates FPing as a probe into smokeping. The variable B<binary> must 
point to your copy of the FPing program.  If it is not installed on 
your system yet, you can get it from L<http://www.fping.com/>.
  
The (optional) B<packetsize> option lets you configure the packetsize for the pings sent.

The FPing manpage has the following to say on this topic:

Number of bytes of ping data to send.  The minimum size (normally 12) allows
room for the data that fping needs to do its work (sequence number,
timestamp).  The reported received data size includes the IP header
(normally 20 bytes) and ICMP header (8 bytes), so the minimum total size is
40 bytes.  Default is 56, as in ping. Maximum is the theoretical maximum IP
datagram size (64K), though most systems limit this to a smaller,
system-dependent number.
DOC
		authors => <<'DOC',
Tobias Oetiker <tobi@oetiker.ch>
DOC
	}
}

sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {
    	my $binary = join(" ", $self->binary);
	my $testhost = $self->testhost;
        my $return = `$binary -C 1 $testhost 2>&1`;
        $self->{enable}{S} = (`$binary -h 2>&1` =~ /\s-S\s/);
	warn  "NOTE: your fping binary doesn't support source address setting (-S), I will ignore any sourceaddress configurations - see  http://bugs.debian.org/198486.\n" if !$self->{enable}{S};
        croak "ERROR: fping ('$binary -C 1 $testhost') could not be run: $return"
            if $return =~ m/not found/;
        croak "ERROR: FPing must be installed setuid root or it will not work\n" 
            if $return =~ m/only.+root/;

        if ($return =~ m/bytes, ([0-9.]+)\sms\s+.*\n.*\n.*:\s+([0-9.]+)/ and $1 > 0){
            $self->{pingfactor} = 1000 * $1/$2;
            print "### fping seems to report in ", $1/$2, " milliseconds\n";
        } else {
            $self->{pingfactor} = 1000; # Gives us a good-guess default
            print "### assuming you are using an fping copy reporting in milliseconds\n";
        }
    };

    return $self;
}

sub ProbeDesc($){
    my $self = shift;
    my $bytes = $self->{properties}{packetsize}||56;
    return "ICMP Echo Pings ($bytes Bytes)";
}

# derived class (ie. RemoteFPing) can override this
sub binary {
	my $self = shift;
	return $self->{properties}{binary};
}

# derived class (ie. FPing6) can override this
sub testhost {
	return "localhost";
}

sub ping ($){
    my $self = shift;
    # do NOT call superclass ... the ping method MUST be overwriten
    my %upd;
    my $inh = gensym;
    my $outh = gensym;
    my $errh = gensym;
    # pinging nothing is pointless
    return unless @{$self->addresses};
    my @params = () ;
    push @params, "-b$self->{properties}{packetsize}" if $self->{properties}{packetsize};
    push @params, "-t" . int(1000 * $self->{properties}{timeout}) if $self->{properties}{timeout};
    push @params, "-i" . int(1000 * $self->{properties}{mininterval});
    push @params, "-p" . int(1000 * $self->{properties}{hostinterval}) if $self->{properties}{hostinterval};
    push @params, "-S$self->{properties}{sourceaddress}" if $self->{properties}{sourceaddress} and $self->{enable}{S};
            
    my @cmd = (
                    $self->binary,
                    '-C', $self->pings, '-q','-B1','-r1',
		    @params,
                    @{$self->addresses});
    $self->do_debug("Executing @cmd");
    my $pid = open3($inh,$outh,$errh, @cmd);
    $self->{rtts}={};
    while (<$errh>){
        chomp;
	$self->do_debug("Got fping output: '$_'");
        next unless /^\S+\s+:\s+[-\d\.]/; #filter out error messages from fping
        my @times = split /\s+/;
        my $ip = shift @times;
        next unless ':' eq shift @times; #drop the colon
        
        @times = map {sprintf "%.10e", $_ / $self->{pingfactor}} sort {$a <=> $b} grep /^\d/, @times;
        map { $self->{rtts}{$_} = [@times] } @{$self->{addrlookup}{$ip}} ;
    }
    waitpid $pid,0;
    close $inh;
    close $outh;
    close $errh;
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		_mandatory => [ 'binary' ],
		binary => {
			_sub => sub {
				my ($val) = @_;
        			return undef if $ENV{SERVER_SOFTWARE}; # don't check for fping presence in cgi mode
				return "ERROR: FPing 'binary' does not point to an executable"
            				unless -f $val and -x _;
				return undef;
			},
			_doc => "The location of your fping binary.",
			_example => '/usr/bin/fping',
		},
		packetsize => {
			_re => '\d+',
			_example => 5000,
			_sub => sub {
				my ($val) = @_;
        			return "ERROR: FPing packetsize must be between 12 and 64000"
              				if ( $val < 12 or $val > 64000 ); 
				return undef;
			},
			_doc => "The ping packet size (in the range of 12-64000 bytes).",

		},
		timeout => {
			_re => '(\d*\.)?\d+',
			_example => 1.5,
			_doc => <<DOC,
The fping "-t" parameter, but in (possibly fractional) seconds rather than
milliseconds, for consistency with other Smokeping probes. Note that as
Smokeping uses the fping 'counting' mode (-C), this apparently only affects
the last ping.
DOC
		},
		hostinterval => {
			_re => '(\d*\.)?\d+',
			_example => 1.5,
			_doc => <<DOC,
The fping "-p" parameter, but in (possibly fractional) seconds rather than
milliseconds, for consistency with other Smokeping probes. From fping(1):

This parameter sets the time that fping  waits between successive packets
to an individual target.
DOC
		},
		mininterval => {
			_re => '(\d*\.)?\d+',
			_example => .001,
			_default => .01,
			_doc => <<DOC,
The fping "-i" parameter, but in (probably fractional) seconds rather than
milliseconds, for consistency with other Smokeping probes. From fping(1):

The minimum amount of time between sending a ping packet to any target.
DOC
		},
		sourceaddress => {
			_re => '\d+(\.\d+){3}',
			_example => '192.168.0.1',
			_doc => <<DOC,
The fping "-S" parameter . From fping(1):

Set source address.
DOC
		},
	});
}

1;
