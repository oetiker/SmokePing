package probes::RemoteFPing;

=head1 NAME

probes::RemoteFPing - Remote FPing Probe for SmokePing

=head1 SYNOPSIS

 *** Probes ***
 + RemoteFPing
 binary = /usr/bin/ssh
 packetsize = 1024
 rhost = HostA.foobar.com
 ruser = foo
 rbinary = /usr/local/sbin/fping

 *** Targets ***
 + Targetname
 Probe = RemoteFPing
 Menu = menuname
 Title = Remote Fping from HostA to HostB
 Host = HostB.barfoo.com


=head1 DESCRIPTION

Integrates the remote execution of FPing via ssh/rsh into smokeping.
The variable B<binary> must point to your copy of the ssh/rsh program.

=head1 OPTIONS

The B<binary> and B<rhost> are mandatory. The B<binary> option
specifies the path of the remote shell program (usually ssh,
rsh or remsh). Any other script or binary that can be called as

 binary [ -l ruser ] rhost rbinary

may be used.

The (optional) B<packetsize> option lets you configure the packetsize
for the pings sent.

The B<rhost> option specifies the remote device from where fping will
be launched.

The (optional) B<ruser> option allows you to specify the remote user,
if different from the one running the smokeping daemon.

The (optional) B<rbinary> option allows you to specify the location of
the remote fping binary. If not specified the probe will assume that
fping is in the remote host's path.

=head1 NOTES

It is important to make sure that you can access the remote machine
without a password prompt, otherwise this probe will not work properly.
To test just try something like this:

    $ ssh foo@HostA.foobar.com fping HostB.barfoo.com 

The next thing you see must be fping's output.

The B<rhost>, B<ruser> and B<rbinary> variables used to be configured in
the PROBE_CONF section of the first target or its parents They were moved
to the Probes section, because the variables aren't really target-specific
(all the targets are measured with the same parameters). The PROBE_CONF
sections aren't recognized anymore.

=head1 AUTHOR

Luis F Balbinot <hades@inf.ufrgs.br>

based on probes::FPing by

Tobias Oetiker <tobi@oetiker.ch>

=cut

use strict;
use base qw(probes::base);
use IPC::Open3;
use Symbol;
use Carp;

sub new($$$) {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {
        croak "ERROR: RemoteFPing packetsize must be between 12 and 64000"
           if $self->{properties}{packetsize} and 
              ( $self->{properties}{packetsize} < 12 or $self->{properties}{packetsize} > 64000 ); 

        croak "ERROR: RemoteFPing 'binary' not defined in RemoteFPing probe definition"
            unless defined $self->{properties}{binary};

        croak "ERROR: RemoteFPing 'binary' does not point to an executable"
            unless -f $self->{properties}{binary} and -x $self->{properties}{binary};

        croak "ERROR: RemoteFPing 'rhost' not defined in RemoteFPing probe definition. This might be because the configuration syntax has changed. See the RemoteFPing manual for details."
            unless defined $self->{properties}{rhost};
    
        $self->{pingfactor} = 1000; # Gives us a good-guess default
        print "### assuming you are using a remote fping copy reporting in milliseconds\n";
    };

    return $self;
}

sub ProbeDesc($) {
    my $self = shift;
    my $bytes = $self->{properties}{packetsize} || 56;
    return "Remote ICMP Echo Pings ($bytes Bytes)";
}

sub ping ($) {
    my $self = shift;

    # do NOT call superclass ... the ping method MUST be overwriten
    my %upd;
    my $inh = gensym;
    my $outh = gensym;
    my $errh = gensym;
    # pinging nothing is pointless
    return unless @{$self->addresses};
    my @bytes = ();

    push @bytes, "-b$self->{properties}{packetsize}" if $self->{properties}{packetsize};

    my @rargs;
    for my $what (qw(ruser rhost rbinary)) {
    	my $prefix = ($what eq 'ruser' ? "-l" : "");
    	if (defined $self->{properties}{$what}) {
    		push @rargs, $prefix . $self->{properties}{$what};
    	} 
    }

    my $query = "$self->{properties}{binary} @rargs @bytes -C " . $self->pings . " -q -B1 -i10 -r1 @{$self->addresses}";

      $self->do_debug("query=$query\n");
 
    my $pid = open3($inh,$outh,$errh,$query );
    my @times =() ;
    $self->{rtts}={};
    while (<$errh>) {
        chomp;
        next unless /^\S+\s+:\s+[\d\.]/; #filter out error messages from fping
        $self->do_debug("array element=$_ \n");
        @times = split /\s+/;
        my $ip = shift @times;
        next unless ':' eq shift @times; #drop the colon
        @times = map {sprintf "%.10e", $_ / $self->{pingfactor}} sort {$a <=> $b} grep {$_ ne "-"} @times;
        map { $self->{rtts}{$_} = [@times] } @{$self->{addrlookup}{$ip}} ;
    }
    waitpid $pid,0;
    close $inh;
    close $outh;
    close $errh;
    return @times;
}

1;
