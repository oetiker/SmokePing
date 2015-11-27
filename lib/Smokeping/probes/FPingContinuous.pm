package Smokeping::probes::FPingContinuous;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::FPingContinuous>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::FPingContinuous>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::base);
use IPC::Open3;
use IO::Pipe;
use IO::Select;
use Symbol;
use Carp;

sub pod_hash {
      return {
	      name => <<DOC,
Smokeping::probes::FPingContinuous - FPingContinuous Probe for SmokePing
DOC
	      description => <<DOC,
Integrates FPingContinuous as a probe into smokeping. The variable B<binary> must 
point to your copy of the FPing program.  If it is not installed on 
your system yet, you can get a slightly enhanced version from L<www.smokeping.org/pub>.
  
The (optional) B<packetsize> option lets you configure the packetsize for the pings sent.

Continuous output is normally sent to stdout, but you can set B<usestdout> to 'false'
to make smokeping read stderr instead of stdout.

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
Steven Wilton <swilton@fluentit.com.au>
Tobias Oetiker <tobi@oetiker.ch>
DOC
	}
}

my $pinger_request=undef;
my $pinger_reply=undef;
# Do 5% more pings than required to make sure we have enough results for each poll
my $error_pct=5;

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
	$self->{enable}{O} = (`$binary -h 2>&1` =~ /\s-O\s/);
	croak "ERROR: fping ('$binary -C 1 $testhost') could not be run: $return"
	    if $return =~ m/not found/;
	croak "ERROR: FPing must be installed setuid root or it will not work\n" 
	    if $return =~ m/only.+root/;
	croak "ERROR: We can only do one ping every 21ms. Either reduce the number of pings or increase the step to fix the issue\n"
	    if($self->interval() < 20);

	if ($return =~ m/bytes, ([0-9.]+)\sms\s+.*\n.*\n.*:\s+([0-9.]+)/ and $1 > 0){
	    $self->{pingfactor} = 1000 * $2/$1;
	    if ($1 != $2){
	        warn "### fping seems to report in ", $2/$1, " milliseconds (old version?)";
	    }
	} else {
	    $self->{pingfactor} = 1000; # Gives us a good-guess default
	    warn "### assuming you are using an fping copy reporting in milliseconds\n";
	}
    };

    return $self;
}

sub interval {
  my $self=shift;
  return (($self->step/$self->pings) * (1-($error_pct/100)) * 1000);
}

sub ProbeDesc($){
    my $self = shift;
    my $bytes = $self->{properties}{packetsize}||56;
    return "ICMP Echo Pings ($bytes Bytes)";
}

# derived class (ie. RemoteFPingContinuous) can override this
sub binary {
	my $self = shift;
	return $self->{properties}{binary};
}

# derived class (ie. FPingContinuous6) can override this
sub testhost {
	return "localhost";
}

sub run_pinger {
  my $self=shift;
  my $input=shift;
  my $output=shift;

  my $select = IO::Select->new();
  $select->add($input);
  my ($fping_stdin, $fping_stdout, $fping_stderr, $fping_pid)=$self->run_fping($select);
  my %results=();
  foreach my $address(@{$self->addresses}) {
    $results{$address}{results}=[];
    $results{$address}{assumed_drops}=0;
    $results{$address}{reply_seq}=0;
  }

  while(1) {
    my @ready=$select->can_read(1);
    foreach my $fh(@ready) {
      if($fh->fileno == $input->fileno) {
	if($fh->eof) {
	  $self->do_log("Input pipe has been closed - exiting");
	  exit(0);
	}
	my $input_cmd=<$input>;
	#$self->do_log($input_cmd);

	if($input_cmd =~ /^FETCH (.+)$/) {
	  my $address=$1;
	  chomp($address);
	  if(!exists($results{$address})) {
	    $self->do_log("We are not gathering results for $address");
	    print $output "\n";
	  } else {
	    my @ret;
	    if(scalar(@{$results{$address}{results}}) < $self->pings) {
	      my $fakeloss=$self->pings-scalar(@{$results{$address}{results}});
	      $self->do_log("Adding $fakeloss lost pings to $address due to insufficient data");
	      @ret=@{$results{$address}{results}};

	      # Record the number of assumed drops, adding the error margin to ensure we do not over-report packet loss
	      $results{$address}{assumed_drops}+=($fakeloss / (1-($error_pct/100)));
	      while($fakeloss-- > 0) {
	        push @ret,"-";
	      }

	      # Reset the results array
	      $results{$address}{results}=[];
	    } else {
	      # Return the correct number of items from the beginning of the result array
	      @ret=splice(@{$results{$address}{results}}, 0, $self->pings);

	      # Leave 2* the error percent of items in the array, but remove extra items
	      my $extra=scalar(@{$results{$address}{results}}) - ($self->pings * ($error_pct*2/100));
	      if($extra > 0) {
	        $self->do_debug("Removing $extra of ". scalar(@{$results{$address}{results}}) ." ping results from array for $address");
	        splice(@{$results{$address}{results}}, 0, $extra);
	      } else {
	        $self->do_debug(scalar(@{$results{$address}{results}}) ." ping results remaining for $address ($extra)");
	      }
	    }
	    $self->do_debug("Data for $address: ". join(" ", @ret));
	    print $output join(" ", @ret) ."\n";
	  }
	}
      } else {
	if($fh->eof) {
	  $self->do_log("fping process exited - restarting");
	  waitpid $fping_pid,0;
	  close($fping_stdin);
	  close($fping_stdout);
	  close($fping_stderr);
	  $select->remove($fh);
	  %results=();
	  foreach my $address(@{$self->addresses}) {
	    $results{$address}{results}=[];
	    $results{$address}{assumed_drops}=0;
	    $results{$address}{reply_seq}=0;
	  }
	  ($fping_stdin, $fping_stdout, $fping_stderr, $fping_pid)=$self->run_fping($select);
	}
	  
	while(my $data=<$fh>) {
	  if($data =~ /(\S+)\s+:\s+\[(\d+)\],.+bytes,\s+([0-9\.]+)\s+ms\s+\(/) {
	    my $address=$1;
	    my $this_seq=$2;
	    my $pingtime=$3;

	    # See if we missed any sequence numbers since the last reply.
	    # Also reduce the detected drop count by any assumed loss so we do not over-report packet loss
	    my $drops=($results{$address}{reply_seq} && $this_seq > $results{$address}{reply_seq})?($this_seq - $results{$address}{reply_seq} - 1 - $results{$address}{assumed_drops}):0;

	    # Add records for dropped packets
	    if($drops) {
	      $self->do_debug("Detected $drops packets dropped in sequence numbers");
	      while($drops-- > 0) {
		push @{$results{$address}{results}}, "-";
	      }
	    }

	    # Record this packet
	    push @{$results{$address}{results}}, $pingtime;

	    # Update the sequence number
	    $results{$address}{reply_seq}=$this_seq;

	    # We can forget about any assumed drops since we have handles actual packet loss above
	    $results{$address}{assumed_drops}=0;
	  } else {
	    $self->do_log("Unknown input data: $data");
	  }
	}
      }
    }

    # See if any pipes have been closed
    my @gone=$select->has_exception(0);
    foreach my $fh(@gone) {
      if($fh->fileno == $input->fileno) {
	$self->do_log("Input pipe has been closed - exiting");
	exit(0);
      } else {
	$self->do_log("fping process exited - restarting");
	waitpid $fping_pid,0;
	close($fping_stdin);
	close($fping_stdout);
	close($fping_stderr);
	$select->remove($fh);
	%results=();
	foreach my $address(@{$self->addresses}) {
	  $results{$address}{results}=[];
	  $results{$address}{assumed_drops}=0;
	  $results{$address}{reply_seq}=0;
	}
	($fping_stdin, $fping_stdout, $fping_stderr, $fping_pid)=$self->run_fping($select);
      }
    }
  }
}

sub run_fping {
    my $self = shift;
    my $select = shift;

    my $inh = gensym;
    my $outh = gensym;
    my $errh = gensym;
    my @params = () ;
    push @params, "-b$self->{properties}{packetsize}" if $self->{properties}{packetsize};
    push @params, "-t" . int(1000 * $self->{properties}{timeout}) if $self->{properties}{timeout};
    push @params, "-p" . int(1000 * $self->{properties}{hostinterval}) if $self->{properties}{hostinterval};
    if ($self->rounds_count == 1 and $self->{properties}{sourceaddress} and not $self->{enable}{S}){
       $self->do_log("WARNING: your fping binary doesn't support source address setting (-S), I will ignore any sourceaddress configurations - see  http://bugs.debian.org/198486.");
    }
    push @params, "-S$self->{properties}{sourceaddress}" if $self->{properties}{sourceaddress} and $self->{enable}{S};

    if ($self->rounds_count == 1 and $self->{properties}{tos} and not $self->{enable}{O}){
       $self->do_log("WARNING: your fping binary doesn't support type of service setting (-O), I will ignore any tos configurations.");
    }
    push @params, "-O$self->{properties}{tos}" if $self->{properties}{tos} and $self->{enable}{O};

    my @cmd = (
	            $self->binary,
	            '-l','-B1','-r1','-p',$self->interval(),
		    @params,
		    @{$self->addresses}
	            );
    $self->do_debug("Executing @cmd");
    my $pid = open3($inh,$outh,$errh, @cmd);
    my $fh = ( $self->{properties}{usestdout} || '') ne 'false' ? $outh : $errh;
    $fh->blocking(0);
    $inh->autoflush(1);
    $select->add($fh);

    return ($inh,$outh,$errh,$pid);
}

sub ping ($){
    my $self = shift;
    # do NOT call superclass ... the ping method MUST be overwriten

    # pinging nothing is pointless
    return unless @{$self->addresses};

    # Fork off our worker if needed
    if(!$pinger_request) {
      $pinger_request=IO::Pipe->new();
      $pinger_reply=IO::Pipe->new();
      my $pid;
      if($pid = fork()) { # Parent
	$pinger_request->writer();
	$pinger_request->autoflush(1);

	$pinger_reply->reader();
        foreach my $address(@{$self->addresses}) {
	  map { $self->{rtts}{$_} = undef } @{$self->{addrlookup}{$address}};
	}
      } elsif(defined($pid)) {
	$pinger_request->reader();

	$pinger_reply->writer();
	$pinger_reply->autoflush(1);

	$self->run_pinger($pinger_request, $pinger_reply);
	exit(0);
      }
    } else {
      foreach my $address(@{$self->addresses}) {
	print $pinger_request "FETCH $address\n";
	my $reply=<$pinger_reply>;
	chomp($reply);

	# Send back the results
	my @times = split /\s+/, $reply;
	@times = map {sprintf "%.10e", $_ / $self->{pingfactor}} sort {$a <=> $b} grep /^\d/, @times;
	map { $self->{rtts}{$_} = [@times] } @{$self->{addrlookup}{$address}};
      }
    }
}

# If we explicitly set the rtts to undef, we want to record UNDEF for packet loss, which is different from the base module
sub rrdupdate_string($$) {
    my $self = shift;
    my $tree = shift;

    my $pings = $self->pings;
    if(exists($self->{rtts}{$tree}) && !defined($self->{rtts}{$tree})) {
        $self->do_debug("No data exists - returning undef");
        my $age='U';
        my $loss='U';
        my $median='U';
        my @times=map {"U"} 1..($pings);

        # Return all values as "U"
        return "${age}:${loss}:${median}:".(join ":", @times);
    } else {
        &Smokeping::probes::base::rrdupdate_string($self, $tree);
    }
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
		usestdout => {
			_re => '(true|false)',
			_example => 'false',
			_doc => "Listen for FPing output on stdout instead of stderr ... (continuous output is normally sent to stdout).",

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
		sourceaddress => {
			_re => '\d+(\.\d+){3}',
			_example => '192.168.0.1',
			_doc => <<DOC,
The fping "-S" parameter . From fping(1):

Set source address.
DOC
		},
		tos => {
			_re => '\d+|0x[0-9a-zA-Z]+',
			_example => '0x20',
			_doc => <<DOC,
Set the type of service (TOS) of outgoing ICMP packets.
You need at laeast fping-2.4b2_to3-ipv6 for this to work. Find
a copy on www.smokeping.org/pub.
DOC
		},
	});
}

1;
