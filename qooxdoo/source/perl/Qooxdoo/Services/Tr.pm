package Qooxdoo::Services::Tr;
use strict;
use POSIX qw(setsid :sys_wait_h);
use Time::HiRes qw(usleep);

sub GetAccessibility {
        return "public";
}

sub launch {
     my $error = shift;
     my $rounds = shift;
     my $delay = shift;
     my $host = shift;
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
     open STDOUT, ">>/tmp/tr_session.$$"
                             or die "Can't write to /tmp/tr_session.$$: $!";
     open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
     setsid                  or die "Can't start a new session: $!";
     open STDERR, '>&STDOUT' or die "Can't dup stdout: $!";
     for (my $i = 0; $i<$rounds;$i++){
        system "traceroute","-I","-q","1",$host;        
#        print "SLEEPING\n";
        sleep $delay;
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
           kill('KILL',$handle);
    }            
}

sub method_run_tr
{
    my $error = shift;
    my $arg = shift;
    my $handle = get_number($error,$arg->{handle});
    my $point = get_number($error,$arg->{point});
    if ($arg->{host}){
        my $delay = get_number($error,$arg->{delay});
        return $delay if ref $delay;
        my $rounds = get_number($error,$arg->{rounds});
        return $rounds if ref $rounds;
        $handle = launch ($error,$rounds,$delay,$arg->{host});
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
            waitpid($handle,WNOHANG);
            $again = kill(0, $handle);
            usleep(1000*300) if $rounds;
#           print STDERR "$again, $handle, $size, $point\n";
            $rounds ++;
        } while ($again and $point >= $size);
        if (seek $fh, $point,0){
            my @array;
            while (<$fh>){
                waitpid($handle,WNOHANG);
                /^traceroute to/ && next;
                if (/unknown host/){
                    $error->set_error(108,"Unknown hostname.");
                    return $error;
                }
                last unless /\n$/; # stop when we find an incomplete line
                if (/^\s*(\d+)\s+(\S+)\s+\((\S+?)\)\s+(\S+)\s+ms/){
                    my ($hop,$host,$ip,$value) = ($1,$2,$3,$4);
                    $value = undef unless $value =~ /^\d+(\.\d+)?$/;
                    push @array, [$hop,$host,$ip,$value];
                    $point = tell($fh);
                }
                elsif (/^\s*(\d+)\s+\*/){
                    push @array, [$1,undef,undef,undef];
                    $point = tell($fh);
                }
                elsif (/^SLEEPING/){
                    push @array, ['SLEEPING'];
                    $point = tell($fh);
                }
                else {
                    $error->set_error(107,"ERROR: $_. See $data for more information.");
                    return $error;
                }
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

1;

