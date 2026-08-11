package Smokeping::probes::GenericCommand;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command

C<smokeping -man Smokeping::probes::GenericCommand>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::GenericCommand>

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
Smokeping::probes::GenericCommand - Generic Command Probe for SmokePing
DOC
		description => <<DOC,
Runs a command given as a parameter n times, and records one of the following:
1. Exit status
2. Time
3. Stdout (should be a number)
If you are using this module to monitor hdd temperature, you might need
setcap 'CAP_SYS_RAWIO+eip CAP_DAC_OVERRIDE+eip CAP_SYS_ADMIN+eip' /usr/sbin/smartctl
DOC
		authors => <<'DOC',
Lockywolf <for_smokeping-generic-command_2024-08-27@lockywolf.net>
DOC
	}
}

sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    # no need for this if we run as a cgi

    return $self;
}

sub ProbeDesc($){
    my $self = shift;
    return "Generic Command";
}

sub pingone ($){
    my $self = shift;
    my $target = shift;

    my $inh = gensym; 
    my $outh = gensym;
    my $errh = gensym;

    my $host = $target->{addr};

    my $query = "$target->{vars}->{command}";
    my @times;
    my @values;

    # get the user and system times before and after the test
    $self->do_debug("query=$query\n");
    for (my $run = 0; $run < $self->pings; $run++) {
        my $t0 = [gettimeofday()];

        my $pid = open3($inh,$outh,$errh, $query);
        while (my $line = <$outh>) {
            my $num;
            chomp $line;
            $num = int($line);
            push (@values, $num);
            push @times, tv_interval($t0);
        }
	waitpid $pid,0;
	my $rc = $?;
	carp "$query returned with exit code $rc. run with debug enabled to get more information" unless $rc == 0;
	close $errh;
	close $inh;
	close $outh;

    }
    @times =  map {sprintf "%.10e", $_ } sort {$a <=> $b} @times;
    @values =  map {sprintf "%.10e", $_ } sort {$a <=> $b} @values;

    $self->do_debug("time=@times\n");
    return @values;
    return @times;
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {})
}

sub targetvars {
        my $class = shift;
        return $class->_makevars($class->SUPER::targetvars, {
            _mandatory => [ 'command' ],
           command => {
               _doc => "command to run",
	       _re => '.+',
               _example => q(/usr/sbin/smartctl -x /dev/nvme0 | grep -F 'Temperature:' | awk '{printf($2);}'),
           },
       })
}
1;
