package probes::DNS;

=head1 NAME

probes::DNS - Name Service Probe for SmokePing

=head1 SYNOPSIS

 *** Probes ***
 + DNS
 binary = /usr/bin/dig

 *** Targets *** 
 probe = DNS
 forks = 10

 + First
 menu = First
 title = First Target
 # .... 

 ++ PROBE_CONF
 lookup=www.mozilla.org

=head1 DESCRIPTION

Integrates dig as a probe into smokeping. The variable B<binary> must
point to your copy of the dig program. If it is not installed on
your system yet, you should install bind-utils >= 9.0.0.

The Probe asks the given host n-times for it's name. Where n is
the amount specified in the config File.

Supported probe-specific variables:

=over

=item binary

The location of your dig binary.

=item forks

The number of concurrent processes to be run. See probes::basefork(3pm)
for details.

=back

Supported target-level probe variables:

=over

=item lookup

Name of the host to look up in the dns.

=back


=head1 AUTHOR

Igor Petrovski E<lt>pigor@myrealbox.comE<gt>,
Carl Elkins E<lt>carl@celkins.org.ukE<gt>,
Andre Stolze E<lt>stolze@uni-muenster.deE<gt>,
Niko Tyni E<lt>ntyni@iki.fiE<gt>,
Chris Poetzel<lt>cpoetzel@anl.gov<gt>


=cut

use strict;
use base qw(probes::basefork);
use IPC::Open3;
use Symbol;
use Carp;

my $dig_re=qr/query time:\s+([0-9.]+)\smsec.*/i;

sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {
        
        croak "ERROR: DNS 'binary' not defined in FPing probe definition"
            unless defined $self->{properties}{binary};

        croak "ERROR: DNS 'binary' does not point to an executable"
            unless -f $self->{properties}{binary} and -x $self->{properties}{binary};
        my $call = "$self->{properties}{binary} localhost";
        my $return = `$call 2>&1`;
        if ($return =~ m/$dig_re/s){
            $self->{pingfactor} = 1000;
            print "### parsing dig output...OK\n";
        } else {
            croak "ERROR: output of '$call' does not match $dig_re\n";
        }
    };

    return $self;
}

sub ProbeDesc($){
    my $self = shift;
    return "DNS requests";
}

sub pingone ($){
    my $self = shift;
    my $target = shift;

    my $inh = gensym;
    my $outh = gensym;
    my $errh = gensym;

    my $host = $target->{addr};
    my $lookuphost = $target->{vars}{lookup};
    $lookuphost = $target->{addr} unless defined $lookuphost;

    #my $host = $target->{addr};
    my $query = "$self->{properties}{binary} \@$host $lookuphost";
    my @times;

    $self->do_debug("query=$query\n");
    for (my $run = 0; $run < $self->pings($target); $run++) {
	my $pid = open3($inh,$outh,$errh, $query);
	while (<$outh>) {
	    if (/$dig_re/i) {
		push @times, $1;
		last;
	    }
	}
	waitpid $pid,0;
	close $errh;
	close $inh;
	close $outh;
    }
    @times = map {sprintf "%.10e", $_ / $self->{pingfactor}} sort {$a <=> $b} grep {$_ ne "-"} @times;

#    $self->do_debug("time=@times\n");
    return @times;
}

1;
