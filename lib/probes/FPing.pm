package probes::FPing;

=head1 NAME

probes::FPing - FPing Probe for SmokePing

=head1 SYNOPSIS

 *** Probes ***
 + FPing
 binary = /usr/sepp/bin/fping
 packetsize = 1024

=head1 DESCRIPTION

Integrates FPing as a probe into smokeping. The variable B<binary> must
point to your copy of the FPing program. If it is not installed on
your system yet, you can get it from http://www.fping.com/.

The (optional) packetsize option lets you configure the packetsize for the pings sent.
The FPing manpage has the following to say on this topic:

Number of bytes of ping data to send.  The minimum size (normally 12) allows
room for the data that fping needs to do its work (sequence number,
timestamp).  The reported received data size includes the IP header
(normally 20 bytes) and ICMP header (8 bytes), so the minimum total size is
40 bytes.  Default is 56, as in ping. Maximum is the theoretical maximum IP
datagram size (64K), though most systems limit this to a smaller,
system-dependent number.

=head1 AUTHOR

Tobias Oetiker <tobi@oetiker.ch>

=cut

use strict;
use base qw(probes::base);
use IPC::Open3;
use Symbol;
use Carp;

sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {
        croak "ERROR: FPing packetsize must be between 12 and 64000"
           if $self->{properties}{packetsize} and 
              ( $self->{properties}{packetsize} < 12 or $self->{properties}{packetsize} > 64000 ); 

        croak "ERROR: FPing 'binary' not defined in FPing probe definition"
            unless defined $self->{properties}{binary};

        croak "ERROR: FPing 'binary' does not point to an executable"
            unless -f $self->{properties}{binary} and -x $self->{properties}{binary};
    
        my $return = `$self->{properties}{binary} -C 1 localhost 2>&1`;
        croak "ERROR: FPing must be installed setuid root or it will not work\n" 
            if $return =~ m/only.+root/;

        if ($return =~ m/bytes, ([0-9.]+)\sms\s+.*\n.*\n.*:\s+([0-9.]+)/ and $1 > 0){
            $self->{pingfactor} = 1000 * $2/$1;
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
    my $bytes = $self->{properties}{packetsize} || 56;
    return "ICMP Echo Pings ($bytes Bytes)";
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
    my @bytes = () ;
    push @bytes, "-b$self->{properties}{packetsize}" if $self->{properties}{packetsize};
    my @cmd = (
                    $self->{properties}{binary}, @bytes,
                    '-C', $self->pings, '-q','-B1','-i10','-r1',
                    @{$self->addresses});
    $self->do_debug("Executing @cmd");
    my $pid = open3($inh,$outh,$errh, @cmd);
    $self->{rtts}={};
    while (<$errh>){
        chomp;
        next unless /^\S+\s+:\s+[\d\.]/; #filter out error messages from fping
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

1;
