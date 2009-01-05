package Qooxdoo::Services::Tr;
use strict;
use POSIX qw(setsid);
use Time::HiRes qw(usleep);
use Socket;

my $variant = 'butskoy';
my $config = {
    # Modern traceroute for Linux, version 2.0.9, Nov 19 2007
    # Copyright (c) 2006  Dmitry Butskoy,   License: GPL
    butskoy => [
            -q => {
                arg => 1,
                type => 'static',
            },
            0  => {
                arg => 'HOST',
                type => 'intern',
            },
            1  => {
                label => 'Packetlength',
                type => 'spinner',
                min => 0,
                max => 1024,
                def => 53,
            },
            -M => {
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
            -F => {
              label     => 'Do not Fragment',
              type      => 'boolean',
              default   => 0,
            },
    ],
    # Version 1.4a12
    lbl => [
            -q => {
                arg => 1,
                type => 'static',
            },
            0  => {
                arg => 'HOST',
                type => 'intern',
            },
            1  => {
                label => 'Packetlength',
                type => 'spinner',
                min => 0,
                max => 1024,
                def => 53,
            },
            -I => {
              label   => 'Use ICMP ECHO',
              widget  => 'boolean',
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
     my $host = shift;
     my $cfg = shift;
     my $delay = $cfg->{delay} || 1;
     my $rounds = $cfg->{rounds} || 1;

     defined(my $pid = fork) or do { $error->set_error(101,"Can't fork: $!");return $error};
     if ($pid){
        open my $x, ">/tmp/tr_session.$pid" or do {
            $error->set_error(199,"Opening /tmp/tr_session.$$: $!");
            return $error;
        };
        close ($x);
        return $pid;
     }
     chdir '/'               or die "Can't chdir to /: $!";

#     $|++; # unbuffer
     open STDOUT, ">>/tmp/tr_session.$$"
                             or die "Can't write to /tmp/tr_session.$$: $!";
     open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
     setsid                  or die "Can't start a new session: $!";
     open STDERR, '>&STDOUT' or die "Can't dup stdout: $!";
     for (my $i = 0; $i<$rounds;$i++){
         my $start = time;
         system "traceroute",@{$config->{$variant}{arguments}},$host;        
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

sub method_run_tr
{
    my $error = shift;
    my $arg = shift;
    my $handle = get_number($error,$arg->{handle});
    my $point = get_number($error,$arg->{point});
    my @array;
    if ($arg->{host}){
        my $host = $arg->{host};
        if ( my @addresses = gethostbyname($host) ){
             @addresses = map { inet_ntoa($_) } @addresses[4 .. $#addresses];        
             if ($#addresses > 1){                
                 $host = $addresses[rand($#addresses)];
                 push @array, ['INFO',"Found $#addresses addresses for $arg->{host}. Using $host."];
             }
        }
        my $delay = get_number($error,$arg->{delay});
        return $delay if ref $delay;
        my $rounds = get_number($error,$arg->{rounds});
        return $rounds if ref $rounds;
        $handle = launch ($error,$rounds,$delay,$host);
        $point = 0;
    }
    return $point if ref $point;
    return $handle if ref $handle;
    my $data = "/tmp/tr_session.".$handle;
    if (open my $fh,$data){
        my $again;
        my $size;
        my $rounds = 0;
        do {
            $size = -s $fh;
            # make sure we reap any zombi instances of tr
            # this is especially important when running with speedy of fastcgi
            # 1 = WNOHANG
            waitpid($handle,1);
            $again = kill(0, $handle);
            usleep(1000*300) if $rounds;
#           print STDERR "$again, $handle, $size, $point\n";
            $rounds ++;
        } while ($again and $point >= $size);
	# print STDERR "$point > $size\n";
        if (seek $fh, $point,0){
            while (<$fh>){
                #print STDERR ">$_<";
		next if /^\s*$/ or /traceroute to/;
                if (/^\s*(\d+)\s+(\S+)\s+\((\S+?)\)\s+(\S+)\s+ms/){
                    my ($hop,$host,$ip,$value) = ($1,$2,$3,$4);
                    $value = undef unless $value =~ /^\d+(\.\d+)?$/;
                    push @array, [$hop,$host,$ip,$value];
                }
                elsif (/^\s*(\d+)\s+\*/){
                    push @array, [$1,undef,undef,undef];
                }
                elsif (/^SLEEP\s+(\d+)/){
                    push @array, ['SLEEP',$1];
                }
                elsif (s/traceroute:\s*//g or /\n$/){
                    push @array, ['INFO',$_];
                }
		else {
	            last;
                }
                $point = tell($fh);
            };
            close $fh;
            unlink $data unless $again;
            return {
                handle=>$handle,
                point=>$point,
                output=>\@array,
                again=> $again,
            }
        }
        else {
            $error->set_error(102,"Seeking in traceroute output to $point: $!");
            return $error;
        }            
    }
    else {
        $error->set_error(103,"Opening $data: $!");
        return $error;
    }
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

