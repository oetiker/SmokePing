package CGI::Session::Driver::sqlite;

# $Id: sqlite.pm 351 2006-11-24 14:16:50Z markstos $

use strict;

use File::Spec;
use base 'CGI::Session::Driver::DBI';
use DBI qw(SQL_BLOB);
use Fcntl;

$CGI::Session::Driver::sqlite::VERSION    = "4.20";

sub init {
    my $self = shift;

    unless ( $self->{Handle}) {
       $self->{DataSource} = "dbi:SQLite:dbname=" . $self->{DataSource} unless ( $self->{DataSource} =~ /^dbi:sqlite/i );
    }

    $self->SUPER::init() or return;
    
    $self->{Handle}->{sqlite_handle_binary_nulls} = 1;
    return 1;
}

sub store {
    my $self = shift;
    my ($sid, $datastr) = @_;
    return $self->set_error("store(): usage error") unless $sid && $datastr;

    my $dbh = $self->{Handle};

    my $sth = $dbh->prepare("SELECT id FROM " . $self->table_name . " WHERE id=?");
    unless ( defined $sth ) {
        return $self->set_error( "store(): \$sth->prepare failed with message " . $dbh->errstr );
    }

    $sth->execute( $sid ) or return $self->set_error( "store(): \$sth->execute failed with message " . $dbh->errstr );
    if ( $sth->fetchrow_array ) {
        __ex_and_ret($dbh,"UPDATE " . $self->table_name . " SET a_session=? WHERE id=?",$datastr,$sid)
            or return $self->set_error( "store(): serialize to db failed " . $dbh->errstr );
    } else {
        __ex_and_ret($dbh,"INSERT INTO " . $self->table_name . " (a_session,id) VALUES(?, ?)",$datastr, $sid)
            or return $self->set_error( "store(): serialize to db failed " . $dbh->errstr );
    }
    return 1;
}

sub __ex_and_ret {
    my ($dbh,$sql,$datastr,$sid) = @_;
    # fix rt #18183
    local $@;
    eval {
        my $sth = $dbh->prepare($sql) or return 0;
        $sth->bind_param(1,$datastr,SQL_BLOB) or return 0;
        $sth->bind_param(2,$sid) or return 0;
        $sth->execute() or return 0;
    };
    return ! $@;
}

1;

__END__;

=pod

=head1 NAME

CGI::Session::Driver::sqlite - CGI::Session driver for SQLite

=head1 SYNOPSIS

    $s = new CGI::Session("driver:sqlite", $sid, {DataSource=>'/my/folder/sessions.sqlt'});
    $s = new CGI::Session("driver:sqlite", $sid, {Handle=>$dbh});

=head1 DESCRIPTION

B<sqlite> driver stores session data in SQLite files using L<DBD::SQLite|DBD::SQLite> DBI driver. More details see L<CGI::Session::Driver::DBI|CGI::Session::Driver::DBI>, its parent class.

=head1 DRIVER ARGUMENTS

Supported driver arguments are I<DataSource> and I<Handle>. B<At most> only one of these arguments can be set while creating session object.

I<DataSource> should be in the form of C<dbi:SQLite:dbname=/path/to/db.sqlt>. If C<dbi:SQLite:> is missing it will be prepended for you. If I<Handle> is present it should be database handle (C<$dbh>) returned by L<DBI::connect()|DBI/connect()>.

As of version 1.7 of this driver, the third argument is B<NOT> optional. Using a default database in the temporary directory is a security risk since anyone on the machine can create and/or read your session data. If you understand these risks and still want the old behavior, you can set the C<DataSource> option to I<'/tmp/sessions.sqlt'>.

=head1 BUGS AND LIMITATIONS

None known.

=head1 LICENSING

For support and licensing see L<CGI::Session|CGI::Session>

=cut

