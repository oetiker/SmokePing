package Smokeping::probes::NFSping;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::NFSping>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::NFSping>

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
Smokeping::probes::NFSping - NFSping Probe for SmokePing
DOC
              description => <<DOC,
Integrates NFSping as a probe into smokeping. The variable B<binary> must 
point to your copy of the NFSping program.

NFSping can be downloaded from:

L<https://github.com/mprovost/NFSping>

In B<blazemode>, NFSping sends one more ping than requested, and discards
the first RTT value returned as it's likely to be an outlier.

DOC
		authors => <<'DOC',
Tobias Oetiker <tobi@oetiker.ch>
Matt Provost <mprovost@termcap.net>
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
        croak "ERROR: nfsping ('$binary -C 1 $testhost') could not be run: $return"
            if $return =~ m/not found/;

        if ($return =~ m/([0-9.]+)\sms\s+.*\n.*\n.*:\s+([0-9.]+)/ and $1 > 0){
            $self->{pingfactor} = 1000 * $2/$1;
            if ($1 != $2){
                warn "### nfsping seems to report in ", $2/$1, " milliseconds (old version?)";
            }
        } else {
            $self->{pingfactor} = 1000; # Gives us a good-guess default
            warn "### assuming you are using an nfsping copy reporting in milliseconds\n";
        }
    };

    return $self;
}

sub ProbeDesc{
    return "NFSping";
}

# derived class (ie. RemoteNFSping) can override this
sub binary {
	my $self = shift;
	return $self->{properties}{binary};
}

# derived class (ie. NFSping6) can override this
sub testhost {
	return "localhost";
}

sub ping ($){
    my $self = shift;
    # do NOT call superclass ... the ping method MUST be overwriten

    # increment the internal 'rounds' counter
    $self->increment_rounds_count;

    my %upd;
    my $inh = gensym;
    my $outh = gensym;
    my $errh = gensym;
    # pinging nothing is pointless
    return unless @{$self->addresses};
    my @params = () ;
    push @params, "-t" . int(1000 * $self->{properties}{timeout}) if $self->{properties}{timeout};
    push @params, "-i" . int(1000 * $self->{properties}{mininterval});
    push @params, "-p" . int(1000 * $self->{properties}{hostinterval}) if $self->{properties}{hostinterval};

    my $pings =  $self->pings;
    if (($self->{properties}{blazemode} || '') eq 'true'){
        $pings++;
    }
    my @cmd = (
                    $self->binary,
                    #'-C', $pings, '-q','-B1','-r1',
                    '-C', $pings, '-q',
		    @params,
                    @{$self->addresses});
    $self->do_debug("Executing @cmd");
    my $pid = open3($inh,$outh,$errh, @cmd);
    $self->{rtts}={};
    while (<$errh>){
        chomp;
	$self->do_debug("Got nfsping output: '$_'");
        next unless /^\S+\s+:\s+[-\d\.]/; #filter out error messages from nfsping
        my @times = split /\s+/;
        my $ip = shift @times;
        next unless ':' eq shift @times; #drop the colon
        if (($self->{properties}{blazemode} || '') eq 'true'){     
             shift @times;
        }
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
        			return undef if $ENV{SERVER_SOFTWARE}; # don't check for nfsping presence in cgi mode
				return "ERROR: NFSping 'binary' does not point to an executable"
            				unless -f $val and -x _;
				return undef;
			},
			_doc => "The location of your nfsping binary.",
			_example => '/usr/local/bin/nfsping',
		},
		blazemode => {
			_re => '(true|false)',
			_example => 'true',
			_doc => "Send an extra ping and then discard the first answer since the first is bound to be an outlier.",

		},
		timeout => {
			_re => '(\d*\.)?\d+',
			_example => 1.5,
			_doc => <<DOC,
The nfsping "-t" parameter, but in (possibly fractional) seconds rather than
milliseconds, for consistency with other Smokeping probes.
DOC
		},
		hostinterval => {
			_re => '(\d*\.)?\d+',
			_example => 1.5,
			_doc => <<DOC,
The nfsping "-p" parameter, but in (possibly fractional) seconds rather than
milliseconds, for consistency with other Smokeping probes. This
parameter sets the time that nfsping  waits between successive packets
to an individual target.
DOC
		},
		mininterval => {
			_re => '(\d*\.)?\d+',
			_example => .001,
			_default => .01,
			_doc => <<DOC,
The nfsping "-i" parameter, but in (probably fractional) seconds rather than
milliseconds, for consistency with other Smokeping probes. This is the
interval between pings to successive targets. 
DOC
		},
	});
}

1;
