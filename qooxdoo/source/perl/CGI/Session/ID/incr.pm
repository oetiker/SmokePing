package CGI::Session::ID::incr;

# $Id: incr.pm 351 2006-11-24 14:16:50Z markstos $

use strict;
use File::Spec;
use Carp "croak";
use Fcntl qw( :DEFAULT :flock );
use CGI::Session::ErrorHandler;

$CGI::Session::ID::incr::VERSION = '4.20';
@CGI::Session::ID::incr::ISA     = qw( CGI::Session::ErrorHandler );


sub generate_id {
    my ($self, $args) = @_;

    my $IDFile = $args->{IDFile} or croak "Don't know where to store the id";
    my $IDIncr = $args->{IDIncr} || 1;
    my $IDInit = $args->{IDInit} || 0;

    sysopen(FH, $IDFile, O_RDWR|O_CREAT, 0666) or return $self->set_error("Couldn't open IDFile=>$IDFile: $!");
    flock(FH, LOCK_EX) or return $self->set_error("Couldn't lock IDFile=>$IDFile: $!");
    my $ID = <FH> || $IDInit;
    seek(FH, 0, 0) or return $self->set_error("Couldn't seek IDFile=>$IDFile: $!");
    truncate(FH, 0) or return $self->set_error("Couldn't truncate IDFile=>$IDFile: $!");
    $ID += $IDIncr;
    print FH $ID;
    close(FH) or return $self->set_error("Couldn't close IDFile=>$IDFile: $!");
    return $ID;
}


1;

__END__;

=pod

=head1 NAME

CGI::Session::ID::incr - CGI::Session ID driver

=head1 SYNOPSIS

    use CGI::Session;
    $session = new CGI::Session("id:Incr", undef, {
                                Directory   => '/tmp',
                                IDFile      => '/tmp/cgisession.id',
                                IDInit      => 1000,
                                IDIncr      => 2 });

=head1 DESCRIPTION

CGI::Session::ID::incr is to generate auto incrementing Session IDs. Compare it with L<CGI::Session::ID::md5|CGI::Session::ID::md5>, where session ids are truly random 32 character long strings. CGI::Session::ID::incr expects the following arguments passed to CGI::Session->new() as the third argument.

=over 4

=item IDFile

Location where auto incremented IDs are stored. This attribute is required.

=item IDInit

Initial value of the ID if it's the first ID to be generated. For example, if you want the ID numbers to start with 1000 as opposed to 0, that's where you should set your value. Default is C<0>.

=item IDIncr

How many digits each number should increment by. For example, if you want the first generated id to start with 1000, and each subsequent id to increment by 10, set I<IDIncr> to 10 and I<IDInit> to 1000. Default is C<1>.

=back

=head1 LICENSING

For support and licensing information see L<CGI::Session|CGI::Session>

=cut
