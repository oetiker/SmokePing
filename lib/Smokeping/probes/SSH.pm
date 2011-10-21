package Smokeping::probes::SSH;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::SSH>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::SSH>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork);
use IPC::Open3;
use Symbol;
use Carp;
use Time::HiRes qw(gettimeofday tv_interval);

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::SSH - Secure Shell Probe for SmokePing
DOC
		description => <<DOC,
Integrates ssh-keyscan as a probe into smokeping. The variable B<binary> must
point to your copy of the ssh-keyscan program. If it is not installed on
your system yet, you should install openssh >= 3.8p1

The Probe asks the given host n-times for it's public key, where n is
the amount specified in the config File.

As part of the initialization, the probe asks 127.0.0.1 for it's public key
and tries to parse the output. Make sure you have SSH running on the
localhost as well.
DOC
		authors => <<'DOC',
Christian Recktenwald <smokeping-contact@citecs.de>
DOC
	}
}

my $ssh_re=qr/^# \S+ SSH-/i;

sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {
        
        my $call = "$self->{properties}{binary} -t dsa,rsa,rsa1 127.0.0.1";
        my $return = `$call 2>&1`;
        if ($return =~ m/$ssh_re/s){
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

    my $query = "$self->{properties}{binary} -t $target->{vars}->{keytype}  -p $target->{vars}->{port} $host";
    my @times;

    # get the user and system times before and after the test
    $self->do_debug("query=$query\n");
    for (my $run = 0; $run < $self->pings; $run++) {
       my $t0 = [gettimeofday()];

	my $pid = open3($inh,$outh,$errh, $query);
       while (<$errh>) {
            if (/$ssh_re/i) {
                push @times, tv_interval($t0);
                last;
            }
        }
	waitpid $pid,0;
	close $errh;
	close $inh;
	close $outh;

    }
    @times =  map {sprintf "%.10e", $_ } sort {$a <=> $b} @times;

#    $self->do_debug("time=@times\n");
    return @times;
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		_mandatory => [ 'binary' ],
		binary => {
			_doc => "The location of your ssh-keyscan binary.",
			_example => '/usr/bin/ssh-keyscan',
			_sub => sub {
				my $val = shift;
				-x $val or return "ERROR: binary '$val' is not executable";
				return undef;
			},
		},
	})
}

sub targetvars {
        my $class = shift;
        return $class->_makevars($class->SUPER::targetvars, {
           keytype => {
               _doc => "Type of key, used in ssh-keyscan -t I<keytype>",
	       _re => "[dr]sa1*",
               _example => 'dsa',
               _default => 'rsa',
           },
           port => {
               _doc => "Port to use when testing the ssh connection -p I<port>",
	       _re => '\d+',
               _example => '5000',
               _default => '22',
           },
       })
}
1;
