package probes::SSH;

=head1 NAME

probes::SSH - Secure Shell Probe for SmokePing

=head1 SYNOPSIS

 *** Probes ***
 + SSH
 binary = /usr/bin/ssh-keyscan

 *** Targets *** 
 probe = SSH
 forks = 10

 + First
 menu = First
 title = First Target
 # .... 

=head1 DESCRIPTION

Integrates ssh-keyscan as a probe into smokeping. The variable B<binary> must
point to your copy of the ssh-keyscan program. If it is not installed on
your system yet, you should install openssh >= 3.8p1

The Probe asks the given host n-times for it's public key. Where n is
the amount specified in the config File.

Supported probe-specific variables:

=over

=item binary

The location of your ssh-keyscan binary.

=item forks

The number of concurrent processes to be run. See probes::basefork(3pm)
for details.

=back

Supported target-level probe variables:

=over

=back


=head1 AUTHOR

Christian Recktenwald<lt>smokeping-contact@citecs.de<gt>


=cut

use strict;
use base qw(probes::basefork);
use IPC::Open3;
use Symbol;
use Carp;
use POSIX;

my $ssh_re=qr/^# \S+ SSH-/i;

sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {
        
        croak "ERROR: SSH 'binary' not defined in SSH probe definition"
            unless defined $self->{properties}{binary};

        croak "ERROR: SSH 'binary' does not point to an executable"
            unless -f $self->{properties}{binary} and -x $self->{properties}{binary};
        my $call = "$self->{properties}{binary} -t rsa localhost";
        my $return = `$call 2>&1`;
        if ($return =~ m/$ssh_re/s){
            $self->{pingfactor} = 10;
            print "### parsing ssh-keyscan output...OK\n";
        } else {
            croak "ERROR: output of '$call' does not match $ssh_re\n";
        }
    };

    return $self;
}

sub ProbeDesc($){
    my $self = shift;
    return "SSH requests";
}

sub pingone ($){
    my $self = shift;
    my $target = shift;

    my $inh = gensym;
    my $outh = gensym;
    my $errh = gensym;

    my $host = $target->{addr};

    my $query = "$self->{properties}{binary} -t rsa $host";
    my @times;

    # get the user and system times before and after the test
    $self->do_debug("query=$query\n");
    for (my $run = 0; $run < $self->pings; $run++) {
    	my @times1 = POSIX::times;
	my $pid = open3($inh,$outh,$errh, $query);
	while (<$outh>) {
	    if (/$ssh_re/i) {
		last;
	    }
	}
	waitpid $pid,0;
	close $errh;
	close $inh;
	close $outh;
    	my @times2 = POSIX::times;
	push @times, $times2[0]-$times1[0];
    }
    @times = map {sprintf "%.10e", $_ / $self->{pingfactor}} sort {$a <=> $b} grep {$_ ne "-"} @times;

#    $self->do_debug("time=@times\n");
    return @times;
}

1;
