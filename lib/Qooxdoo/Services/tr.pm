package Qooxdoo::Services::tr;
use strict;
use POSIX qw(setsid);
use Time::HiRes qw(usleep);
use Socket;

my $variant = 'butskoy';
my $config = {
    # Modern traceroute for Linux, version 2.0.9, Nov 19 2007
    # Copyright (c) 2006  Dmitry Butskoy,   License: GPL
    butskoy => [
            {
                arg => '-q',
                type => 'static',
            },
            {
                arg => '1',
                type => 'static',
            },
            {
                key  => 'host',
                type => 'intern',
            },
            {
                key   => 'pkglen',
                label => 'Packetlength',
                type => 'spinner',
                min => 0,
                max => 1024,
                default => 53,
            },
            {
                key     => 'method',
                arg     => '-M',
                label   => 'Traceroute Method',
                type    => 'select',
                pick    => [
                    default => 'Classic UDP',
                    icmp    => 'ICMP ECHO',
                    tcp     => 'TCP Syn',
                    udp     => 'UDP to port 53',
                    udplite => 'UDPLITE Datagram',
                ],
                default => 'icmp',
            },
            {
              key     => 'nofrag',
              arg     => '-F',
              label     => 'Do not Fragment',
              type      => 'boolean',
              default   => 0,
            },
    ],
    # Version 1.4a12
    lbl => [
            {
                arg => '-q',
                type => 'static',
            },
            {
                arg => '1',
                type => 'static',
            },
            {
                key  => 'host',
                type => 'intern',
            },
            {
                key => 'pkglen',
                label => 'Packetlength',
                type => 'spinner',
                min => 0,
                max => 1024,
                default => 53,
            },
            {   
              key     => 'icmpecho',
              arg     => '-I',
              label   => 'Use ICMP ECHO',
              type    => 'boolean',
              default => 1,
            }
    ]
};

sub GetAccessibility {
     my $method = shift;
     my $access = shift;
     my $session = shift;
#     if ($method eq 'auth' or $session->param('authenticated') eq 'yes'){
        return 'public';
#     }
#     else {
#         return 'fail';
#     }
}

sub launch {
    my $error = shift;
    my $task = shift;
    my $cfg = $config->{$variant};
    my @exec;
    for (my $i = 0;$i < @{$cfg};$i++){
        my $ch = $cfg->[$i];
        if ($ch->{key}){
            if ($task->{$ch->{key}}){
                if ($ch->{arg}){        
                    push @exec, $ch->{arg};
                }
                push @exec, $task->{$ch->{key}} 
            }
        }
        elsif ($ch->{arg}){
            push @exec, $ch->{arg};
        };
    }
    use Data::Dumper;
    my $rounds = $task->{rounds};
    my $delay = $task->{delay};
#    warn Dumper '### task: '.$task;
    defined(my $pid = fork) or do { $error->set_error(101,"Can't fork: $!");return $error};
    if ($pid){
       open my $x, ">/tmp/tr_session.$pid" or do {
           $error->set_error(199,"Opening /tmp/tr_session.$$: $!");
           return $error;
       };
       close ($x);
       return $pid;
    }
    local $SIG{CHLD};
    chdir '/'               or die "Can't chdir to /: $!";

#   $|++; # unbuffer
    open STDOUT, ">>/tmp/tr_session.$$"
                             or die "Can't write to /tmp/tr_session.$$: $!";
    open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
    setsid                  or die "Can't start a new session: $!";
    open STDERR, '>&STDOUT' or die "Can't dup stdout: $!";
    for (my $i = 0; $i<$rounds;$i++){
        my $start = time;
        system "traceroute",@exec;
        if ($? == -1) {
            print "ERROR: failed to execute traceroute: $? $!\n";
            exit 1;
        }
        elsif ($? & 127) {
            printf "ERROR: traceroute died with signal %d, %s coredump\n",
                 ($? & 127),  ($? & 128) ? 'with' : 'without';
            exit 1;
        }
        elsif ($? != 0) {
            printf "ERROR: traceroute exited with value %d\n", $? >> 8;
            exit 1;
        }
        my $wait = $delay - (time - $start);
        if ($wait > 0 and $i+1< $rounds){
            print "SLEEP $wait\n";
            sleep $wait;
        }
    }
    exit 0;
}

sub get_number {
    my $error = shift;
    my $data = shift;
    $data = 'Undefined' unless defined $data;
    if ($data =~ /^(\d+)$/){
        return $1;
    }
    else {
        $error->set_error(104,"Expected a number but got: $data");
        return $error;
    }
}

sub method_stop_tr {
    my $error = shift;
    my $arg = shift; 
    my $handle = get_number($error,$arg);
    
    return $handle if ref $handle;
    my $data = "/tmp/tr_session.".$handle;
    if (-r $data){
        warn "Sending kill $handle";
        if (kill('KILL',$handle)){
            waitpid($handle,0);
        }
    }            
    return 'ok';
}


sub method_start
{
    my $error = shift;
    my $arg = shift;
    my $session = $error->{session};
    if ($arg->{host}){
        my $delay = get_number($error,$arg->{delay});
        return $delay if ref $delay;
        my $rounds = get_number($error,$arg->{rounds});
        return $rounds if ref $rounds;
        return launch ($error,$arg);
    }
    $error->set_error(103,"No host set");
    return $error;
}


sub method_poll
{
    my $error = shift;
    my $arg = shift;
    my $session = $error->{session};
    my %return;
    for my $pid (sort keys %$arg){
        my $point = $arg->{$pid};
        my $data = "/tmp/tr_session.".$pid;
        my $problem = '';
        if (open my $fh,$data){
            my $again;
            my @array;
            my $rounds = 0;
            waitpid($pid,1);
            $again = kill(0, $pid);
            my $size = -s $fh;
            if ($point < $size and seek $fh, $point,0){
                while (<$fh>){
            		next if /^\s*$/ or /^traceroute to/;
                    if (/^\s*(\d+)\s+(\S+)\s+\((\S+?)\)\s+(\S+)\s+ms/){
                        my ($hop,$host,$ip,$value) = ($1,$2,$3,$4);
                        $value = undef unless $value =~ /^\d+(\.\d+)?$/;
                        push @array, [$hop,$host,$ip,$value];
                    }
                    elsif (/^\s*(\d+)\s+\*/){
                        push @array, [$1,undef,undef,undef];
                    }
                    else {
                        s/ERROR:\s*//;
                        $problem .= $_;
                    }
                }
                $arg->{$pid} = tell($fh);
                $return{$pid}{data} = \@array;
            };
            close $fh;
            warn 'problem: '.$problem;
            if ($problem){
                $return{$pid}{type} = 'error';
                $return{$pid}{msg} = $problem;
                delete $arg->{$pid};
                unlink $data;
            }
            elsif (not $again) {
                $return{$pid}{type} = 'state';
                $return{$pid}{msg} = 'idle';
                delete $arg->{$pid};
                unlink $data;
            }
        }
        else {
            $return{$pid}{type} = 'error';
            $return{$pid}{msg} = "Opening $data: $!";
            delete $arg->{$pid};
        }            
    }
    $return{handles} = $arg;
    return \%return;
}

sub method_auth {
    my $error = shift;
    my $user = shift;
    my $password = shift;
    my $session = $error->{session};
    if ($user eq 'tobi' and $password eq 'robi'){
        $session->param('authenticated','yes');
    }    
}   

sub method_get_config {
    my $error = shift;
    my @list;
    for (my $i=0;defined $config->{$variant}[$i]; $i+=2){
        next if not defined $config->{$variant}[$i+1]{label};
        push @list, $config->{$variant}[$i],$config->{$variant}[$i+1];
    };
    return \@list;
}
 
                

1;

