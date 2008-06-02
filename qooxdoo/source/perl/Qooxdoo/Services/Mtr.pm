package Qooxdoo::Services::Mtr;
use strict;
use POSIX qw(setsid :sys_wait_h);
use Time::HiRes qw(usleep);

sub GetAccessibility {
        return "public";
}

sub launch {
     my $error = shift;
     $SIG{CHLD} = \&REAPER;
     defined(my $pid = fork) or do { $error->set_error(101,"Can't fork: $!");return $error};
     if ($pid){
        open my $x, ">/tmp/mtr_session.$pid" or do {
            $error->set_error(199,"Opening /tmp/mtr_session.$$: $!");
            return $error;
        };
        close ($x);
        return $pid;
     }
     chdir '/'               or die "Can't chdir to /: $!";
     open STDOUT, ">>/tmp/mtr_session.$$"
                             or die "Can't write to /tmp/mtr_session.$$: $!";
     open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
     setsid                  or die "Can't start a new session: $!";
     open STDERR, '>&STDOUT' or die "Can't dup stdout: $!";
     exec @_;
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

sub method_stop_mtr {
    my $error = shift;
    my $arg = shift; 
    my $handle = get_number($error,$arg);
    return $handle if ref $handle;
    my $data = "/tmp/mtr_session.".$handle;
    if (-r $data){
           warn "Sending kill $handle";
           kill('KILL',$handle);
    }            
}

sub method_run_mtr
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
        $handle = launch ($error,"mtr","-4","--raw","--report-cycles=$rounds","--interval=$delay",$arg->{host});
        $point = 0;
    }
    return $point if ref $point;
    return $handle if ref $handle;
    my $data = "/tmp/mtr_session.".$handle;
    if (open my $fh,$data){
        my $again;
        my $size;
        my $rounds = 0;
        do {
            $size = -s $fh;
            # make sure we reap any zombi instances of mtr
            # this is especially important when running with speedy of fastcgi
            waitpid($handle,WNOHANG);
            $again = kill(0, $handle);
            usleep(1000*200) if $rounds;
#           print STDERR "$again, $handle, $size, $point\n";
            $rounds ++;
        } while ($again and $point >= $size);
        if (seek $fh, $point,0){
            my @array;
            while (<$fh>){
                if (not /^[a-z]\s/){
                    waitpid($handle,WNOHANG);
                    if (/Name or service not known/){
                        $error->set_error(108,"Unknown hostname.");
                        return $error;
                    }
                    else {
                        $error->set_error(107,"ERROR: $_. See $data for more information.");
                        return $error;
                    }
                }                        
                last unless /\n$/; # stop when we find an incomplete line
                $point = tell($fh);
                chomp;
                my @line = split (/\s+/,$_);
                push @array,\@line;
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
            $error->set_error(102,"Seeking in mtr output to $point: $!");
            return $error;
        }            
    }
    else {
        $error->set_error(103,"Opening $data: $!");
        return $error;
    }
}

1;

