package probes::AnotherSSH;

=head1 NAME

probes::AnotherSSH - Another SSH probe

=head1 SYNOPSIS

 *** Probes ***
 + AnotherSSH

 *** Targets *** 
 probe = AnotherSSH 
 forks = 10

 + First
 menu = First
 title = First Target
 # .... 

 ++ PROBE_CONF
 greeting = SSH-Latecy-Measurement-Sorry-for-the-logfile-entry
 sleeptime = 500000
 interval = established
 timeout = 5

=head1 DESCRIPTION

Latency measurement using SSH. This generates Logfile messages on the other 
Host, so get permission from the owner first! 

=over

=item forks

The number of concurrent processes to be run. See probes::basefork(3pm)
for details.

=back

Supported target-level probe variables:

=over

=item greeting

Greeting string to send to the SSH Server. This will appear in the Logfile. 
Use this to make clear, who you are and what you are doing to avoid confusion.

Also, don't use something that is a valid version string. This probe assumes
that the connection gets terminated because of protocol mismatch.

=item sleeptime

Time to sleep between two measurements in microsends. Default is 500000.

=item interval

The interval to measure

=over

=item connect

Interval between connect() and the greeting string from the host.

=item established

Interval between our greeting message and the end of the connection 
because of Protocol mismatch. This is the default.

=item complete

From connect() to the end of the connection.

=back

=item timeout 

Timeout for the connection. Default is 5.

=item port

Connect to this port. Default is 22.

=back


=head1 AUTHOR

Christoph Heine E<lt>Christoph.Heine@HaDiKo.DEE<gt>

=cut

use strict;
use base qw(probes::basefork);
use Carp;
use Time::HiRes qw(usleep ualarm gettimeofday tv_interval);
use IO::Select;
use Socket;
use Fcntl;


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
    my $sleeptime  = $target->{vars}{sleeptime};
    $sleeptime  = 500000 unless defined $sleeptime;
    
    # Our greeting string.
    my $greeting  = $target->{vars}{greeting};
    $greeting  = "SSH-Latency-Measurement-Sorry-for-this-logmessage" 
    	unless defined $greeting;
    
    # Interval to measure
    my $interval = $target->{vars}{interval};
    $interval  = "established" unless defined $interval;
    if(not ( $interval eq "connect" or $interval eq "established" or $interval eq "complete")) {
   	$self->do_debug("Invalid interval parameter");
	return undef;
   }

   # Connect to this port.
    my $port = $target->{vars}{port};
    $port  = 22 unless defined $port;

    #Timeout for the select() calls.
    my $timeout = $target->{vars}{timeout};
    $timeout  = 5 unless defined $timeout;
    
    my @times; # Result times
        
    for ( my $run = 0 ; $run < $self->pings($target) ; $run++ ) {
    	my ($t0,$t1,$t2,$t3); # Timestamps.
	
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
	$t0 = [gettimeofday];
	connect( Socket_Handle, $sin );
	($ready) = $sel->can_read($timeout);
	$t1 = [gettimeofday];
	
	if(not defined $ready) {
		$self->do_debug("Timeout!");
		close(Socket_Handle); next;
	 }
	$nbytes = sysread( Socket_Handle, $buf, 1500 );	
	if ($nbytes <= 0) {
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
	$t2 = [gettimeofday];
	syswrite( Socket_Handle, $greeting . "\n" );
	($ready) = $sel->can_read($timeout);
	$t3 = [gettimeofday];
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

	
	usleep($sleeptime);
    }
    @times =
      map { sprintf "%.10e", $_ } sort { $a <=> $b } grep { $_ ne "-" } @times;

    return @times;
}

1;

