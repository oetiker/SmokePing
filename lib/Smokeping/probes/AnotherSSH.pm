package Smokeping::probes::AnotherSSH;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::AnotherSSH>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::AnotherSSH>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork);
use Carp;
use Time::HiRes qw(sleep ualarm gettimeofday tv_interval);
use IO::Select;
use Socket;
use Fcntl;

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::AnotherSSH - Another SSH probe
DOC
		description => <<DOC,
Latency measurement using SSH. This generates Logfile messages on the other 
Host, so get permission from the owner first! 
DOC
		authors => <<'DOC',
Christoph Heine <Christoph.Heine@HaDiKo.DE>
DOC
	}
}

sub new($$$) {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new(@_);
    return $self;
}

sub ProbeDesc($) {
    my $self = shift;
    return "SSH connections";
}

sub pingone ($) {
    my $self   = shift;
    my $target = shift;

    my $host       = $target->{addr};
    
    # Time 
    my $mininterval = $target->{vars}{mininterval};
    
    # Our greeting string.
    my $greeting  = $target->{vars}{greeting};
    
    # Interval to measure
    my $interval = $target->{vars}{interval};

   # Connect to this port.
    my $port = $target->{vars}{port};

    #Timeout for the select() calls.
    my $timeout = $target->{vars}{timeout};
    
    my @times; # Result times
        
    my $t0;
    for ( my $run = 0 ; $run < $self->pings($target) ; $run++ ) {
    	if (defined $t0) {
		my $elapsed = tv_interval($t0, [gettimeofday()]);
		my $timeleft = $mininterval - $elapsed;
		sleep $timeleft if $timeleft > 0;
	}
    	my ($t1,$t2,$t3); # Timestamps.
	
	#Temporary variables to play with.
	my $ready;
	my $buf;
	my $nbytes;
	
    	my $proto = getprotobyname('tcp');
	my $iaddr = gethostbyname($host);
	my $sin = sockaddr_in( $port, $iaddr );
	socket( Socket_Handle, PF_INET, SOCK_STREAM, $proto );
	
	# Make the Socket non-blocking
    	my $flags = fcntl( Socket_Handle, F_GETFL, 0 ) or do {
		$self->do_debug("Can't get flags for socket: $!");
		close(Socket_Handle);
		next;
	 };
	
	fcntl( Socket_Handle, F_SETFL, $flags | O_NONBLOCK ) or do {
		$self->do_debug("Can't make socket nonblocking: $!");
		close(Socket_Handle); next;
	};
	
	my $sel = IO::Select->new( \*Socket_Handle );

	# connect () and measure the Time.
	$t0 = [gettimeofday()];
	connect( Socket_Handle, $sin );
	($ready) = $sel->can_read($timeout);
	$t1 = [gettimeofday()];
	
	if(not defined $ready) {
		$self->do_debug("Timeout!");
		close(Socket_Handle); next;
	 }
	$nbytes = sysread( Socket_Handle, $buf, 1500 );	
	if (not defined $nbytes or $nbytes <= 0) {
		$self->do_debug("Read nothing and Connection closed!");
		close(Socket_Handle); next;
	}
	# $self->do_debug("Got '$buf' from remote Server");
	if (not $buf =~ m/^SSH/) {
		$self->do_debug("Not an SSH Server");
		close(Socket_Handle); next;
	}
	
	($ready) = $sel->can_write($timeout);
	if (not defined($ready)) {
		$self->do_debug("Huh? Can't write.");
		close(Socket_Handle); next;
	}
	$t2 = [gettimeofday()];
	syswrite( Socket_Handle, $greeting . "\n" );
	($ready) = $sel->can_read($timeout);
	$t3 = [gettimeofday()];
	if(not defined $ready) {
		$self->do_debug("Timeout!");
		close(Socket_Handle); next;
	 }
	 close(Socket_Handle);

	 # We made it! Yeah!

	 if( $interval eq "connect") {
	 	push @times, tv_interval( $t0, $t1 );
	 } elsif ( $interval eq "established") {
	 	push @times, tv_interval($t2,$t3);
	} elsif ($interval eq "complete") {
	 	push @times, tv_interval($t0,$t3);
	} else {
		$self->do_debug("You should never see this message.\n The universe will now collapse. Goodbye!\n");
	}

	
    }
    @times =
      map { sprintf "%.10e", $_ } sort { $a <=> $b } grep { $_ ne "-" } @times;

    return @times;
}

sub probevars {
	my $class = shift;
	my $h = $class->SUPER::probevars;
	delete $h->{timeout};
	return $h;
}

sub targetvars {
	my $class = shift;
	my $e = "=";
	return $class->_makevars($class->SUPER::targetvars, {
		greeting => {
			_doc => <<DOC,
Greeting string to send to the SSH Server. This will appear in the Logfile. 
Use this to make clear, who you are and what you are doing to avoid confusion.

Also, don't use something that is a valid version string. This probe assumes
that the connection gets terminated because of protocol mismatch.
DOC
			_default => "SSH-Latency-Measurement-Sorry-for-this-logmessage" ,
		},
		mininterval => {
			_doc => "Minimum interval between the start of two connection attempts in (possibly fractional) seconds.",
			_default => 0.5,
			_re => '(\d*\.)?\d+',
		},
		interval => {
			_doc => <<DOC,
The interval to be measured. One of:

${e}over

${e}item connect

Interval between connect() and the greeting string from the host.

${e}item established

Interval between our greeting message and the end of the connection 
because of Protocol mismatch. This is the default.

${e}item complete

From connect() to the end of the connection.

${e}back

DOC

			_sub => sub {
				my $interval = shift;
    				if(not ( $interval eq "connect" 
				      or $interval eq "established" 
				      or $interval eq "complete")) {
   					return "ERROR: Invalid interval parameter";
				}
				return undef;
			},
			_default => 'established',
		},
		timeout => {
			_doc => 'Timeout for the connection.',
			_re => '\d+',
			_default => 5,
		},
		port => {
			_doc => 'Connect to this port.',
			_re => '\d+',
			_default => 22,
		},
	});
}

1;

