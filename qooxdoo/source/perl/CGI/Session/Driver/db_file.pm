package CGI::Session::Driver::db_file;

# $Id: db_file.pm 351 2006-11-24 14:16:50Z markstos $

use strict;

use Carp;
use DB_File;
use File::Spec;
use File::Basename;
use CGI::Session::Driver;
use Fcntl qw( :DEFAULT :flock );
use vars qw( @ISA $VERSION $FILE_NAME $UMask $NO_FOLLOW );

@ISA         = ( "CGI::Session::Driver" );
$VERSION     = "4.20";
$FILE_NAME   = "cgisess.db";
$UMask       = 0660;
$NO_FOLLOW   = eval { O_NOFOLLOW } || 0;

sub init {
    my $self = shift;

    $self->{FileName}  ||= $CGI::Session::Driver::db_file::FILE_NAME;
    unless ( $self->{Directory} ) {
        $self->{Directory} = dirname( $self->{FileName} );
        $self->{Directory} = File::Spec->tmpdir() if $self->{Directory} eq '.' && substr($self->{FileName},0,1) ne '.';
        $self->{FileName}  = basename( $self->{FileName} );
    }
    unless ( -d $self->{Directory} ) {
        require File::Path;
        File::Path::mkpath($self->{Directory}) or return $self->set_error("init(): couldn't mkpath: $!");
    }
    
    $self->{UMask} = $CGI::Session::Driver::db_file::UMask unless exists $self->{UMask};
    
    return 1;
}


sub retrieve {
    my $self = shift;
    my ($sid) = @_;
    croak "retrieve(): usage error" unless $sid;

    return 0 unless -f $self->_db_file; 
    my ($dbhash, $unlock) = $self->_tie_db_file(O_RDONLY) or return;
    my $datastr =  $dbhash->{$sid};
    untie(%$dbhash);
    $unlock->();
    return $datastr || 0;
}


sub store {
    my $self = shift;
    my ($sid, $datastr) = @_;
    croak "store(): usage error" unless $sid && $datastr;

    my ($dbhash, $unlock) = $self->_tie_db_file(O_RDWR, LOCK_EX) or return;
    $dbhash->{$sid} = $datastr;
    untie(%$dbhash);
    $unlock->();
    return 1;
}



sub remove {
    my $self = shift;
    my ($sid) = @_;
    croak "remove(): usage error" unless $sid;

    
    my ($dbhash, $unlock) = $self->_tie_db_file(O_RDWR, LOCK_EX) or return;
    delete $dbhash->{$sid};
    untie(%$dbhash);
    $unlock->();
    return 1;
}


sub DESTROY {}


sub _lock {
    my $self = shift;
    my ($db_file, $lock_type) = @_;

    croak "_lock(): usage error" unless $db_file;
    $lock_type ||= LOCK_SH;

    my $lock_file = $db_file . '.lck';
    if ( -l $lock_file ) {
        unlink($lock_file) or 
          die $self->set_error("_lock(): '$lock_file' appears to be a symlink and I can't remove it: $!");
    }
    sysopen(LOCKFH, $lock_file, O_RDWR|O_CREAT|$NO_FOLLOW) or die "couldn't create lock file '$lock_file': $!";
    
        
    flock(LOCKFH, $lock_type)                   or die "couldn't lock '$lock_file': $!";
    return sub {
        close(LOCKFH); # && unlink($lock_file); # keep the lock file around
        1;
    };
}



sub _tie_db_file {
    my $self                 = shift;
    my ($o_mode, $lock_type) = @_;
    $o_mode     ||= O_RDWR|O_CREAT;
    
    # DB_File will not touch a file unless it recognizes the format
    # we can't detect the version of the underlying database without some very heavy checks so the easiest thing is
    # to disable this for opening of the database
    
    # # protect against symlinks
    # $o_mode     |= $NO_FOLLOW;

    my $db_file     = $self->_db_file;
    my $unlock = $self->_lock($db_file, $lock_type);
    my %db;
        
    my $create = ! -e $db_file;
    
    if ( -l $db_file ) {
        $create = 1;
        unlink($db_file) or 
          return $self->set_error("_tie_db_file(): '$db_file' appears to be a symlink and I can't remove it: $!");
    }
    
    $o_mode = O_RDWR|O_CREAT|O_EXCL if $create;
    
    unless( tie %db, "DB_File", $db_file, $o_mode, $self->{UMask} ){
        $unlock->();
        return $self->set_error("_tie_db_file(): couldn't tie '$db_file': $!");
    }

    return (\%db, $unlock);
}

sub _db_file {
    my $self = shift;
    return File::Spec->catfile( $self->{Directory}, $self->{FileName} );
}

sub traverse {
    my $self = shift;
    my ($coderef) = @_;

    unless ( $coderef && ref($coderef) && (ref $coderef eq 'CODE') ) {
        croak "traverse(): usage error";
    }

    my ($dbhash, $unlock) = $self->_tie_db_file(O_RDWR, LOCK_SH);
    unless ( $dbhash ) {
        return $self->set_error( "traverse(): couldn't get db handle, " . $self->errstr );
    }
    while ( my ($sid, undef) = each %$dbhash ) {
        $coderef->( $sid );
    }
    untie(%$dbhash);
    $unlock->();
    return 1;
}


1;

__END__;

=pod

=head1 NAME

CGI::Session::Driver::db_file - CGI::Session driver for BerkeleyDB using DB_File

=head1 SYNOPSIS

    $s = new CGI::Session("driver:db_file", $sid);
    $s = new CGI::Session("driver:db_file", $sid, {FileName=>'/tmp/cgisessions.db'});

=head1 DESCRIPTION

B<db_file> stores session data in BerkelyDB file using L<DB_File|DB_File> - Perl module. All sessions will be stored 
in a single file, specified in I<FileName> driver argument as in the above example. If I<FileName> isn't given, 
defaults to F</tmp/cgisess.db>, or its equivalent on a non-UNIX system.

If the directory hierarchy leading to the file does not exist, will be created for you.

This module takes a B<UMask> option which will be used if DB_File has to create the database file for you. By default
the umask is 0660.

=head1 LICENSING

For support and licensing information see L<CGI::Session|CGI::Session>

=cut

