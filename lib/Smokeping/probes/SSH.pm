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
and tries to parse the output. This is to ensure that the specified ssh-keyscan
binary provides output in the expected formatm before relying on it.Make sure
you have SSH running on the localhost as well, or specify an alternative 
init_host target to test against, that is expected to be available during any 
smokeping restart.
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
        my $call = "$self->{properties}{binary} -t rsa,ecdsa,ed25519 $self->{properties}{init_host}";
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

    my $query = "$self->{properties}{binary} -t $target->{vars}->{keytype}  -p $target->{vars}->{port}";
    my @times;

    # if ipv4/ipv6 proto was specified in the target, add it unless it is "0"
    if ($target->{vars}->{ssh_af} && $target->{vars}->{ssh_af} ne "0") {
        $query .= " -$target->{vars}->{ssh_af}";
    }
    $query .= " $host";
    # get the user and system times before and after the test
    $self->do_debug("query=$query\n");
    for (my $run = 0; $run < $self->pings; $run++) {
       my $t0 = [gettimeofday()];

	my $pid = open3($inh,$outh,$errh, $query);
	# OpenSSH 9.8 compatibility - output is on stdout now
	while (<$outh>) {
            if (/$ssh_re/i) {
		push @times, tv_interval($t0);
		last;
            }
	}
	while (<$errh>) {
            if (/$ssh_re/i) {
                push @times, tv_interval($t0);
                last;
            }
	}
	waitpid $pid,0;
	my $rc = $?;
	carp "$query returned with exit code $rc. run with debug enabled to get more information" unless $rc == 0;
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
		init_host => {
			_doc => "Host to use for initialization, defaults to IPv4 localhost of 127.0.0.1",
			_example => '127.0.0.1',
			_default => '127.0.0.1',
		}
	})
}

sub targetvars {
        my $class = shift;
        return $class->_makevars($class->SUPER::targetvars, {
           keytype => {
               _doc => "Type of key, used in ssh-keyscan -t I<keytype>",
	             _re => "(rsa|ecdsa|ed25519)",
               _example => 'ecdsa',
               _default => 'rsa',
           },
           port => {
               _doc => "Port to use when testing the ssh connection -p I<port>",
	             _re => '\d+',
               _example => '5000',
               _default => '22',
           },
           ssh_af => {
               _doc => "Address family (IPv4/IPV6) to use when testing the ssh connection, specify 4 or 6.  Specify 0 to reset to default system preference, instead of inheriting the value from parent sections.",
	            _re => '\d+',
               _example => '4',
               _default => '0',
           },
       })
}
1;
