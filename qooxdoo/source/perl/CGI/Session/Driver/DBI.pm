package CGI::Session::Driver::DBI;

# $Id: DBI.pm 351 2006-11-24 14:16:50Z markstos $

use strict;

use DBI;
use Carp;
use CGI::Session::Driver;

@CGI::Session::Driver::DBI::ISA = ( "CGI::Session::Driver" );
$CGI::Session::Driver::DBI::VERSION = "4.20";


sub init {
    my $self = shift;
    if ( defined $self->{Handle} )  {
        if (ref $self->{Handle} eq 'CODE') {
            $self->{Handle} = $self->{Handle}->();
        }
        else {
            # We assume the handle is working, and there is nothing to do. 
        }
    }
    else {
        $self->{Handle} = DBI->connect( 
            $self->{DataSource}, $self->{User}, $self->{Password}, 
            { RaiseError=>1, PrintError=>1, AutoCommit=>1 }
        );
        unless ( $self->{Handle} ) {
            return $self->set_error( "init(): couldn't connect to database: " . DBI->errstr );
        }
        $self->{_disconnect} = 1;
    }
    return 1;
}

# A setter/accessor method for the table name, defaulting to 'sessions'

sub table_name {
    my $self = shift;
    my $class = ref( $self ) || $self;

    if ( (@_ == 0) && ref($self) && ($self->{TableName}) ) {
        return $self->{TableName};
    }

    no strict 'refs';
    if ( @_ ) {
        my $new_name = shift;
        $self->{TableName}           = $new_name;
        ${ $class . "::TABLE_NAME" } = $new_name;
    }

    unless (defined $self->{TableName}) {
        $self->{TableName} = "sessions";
    }

    return $self->{TableName};
}


sub retrieve {
    my $self = shift;
    my ($sid) = @_;
    croak "retrieve(): usage error" unless $sid;


    my $dbh = $self->{Handle};
    my $sth = $dbh->prepare_cached("SELECT a_session FROM " . $self->table_name . " WHERE id=?", undef, 3);
    unless ( $sth ) {
        return $self->set_error( "retrieve(): DBI->prepare failed with error message " . $dbh->errstr );
    }
    $sth->execute( $sid ) or return $self->set_error( "retrieve(): \$sth->execute failed with error message " . $sth->errstr);

    my ($row) = $sth->fetchrow_array();
    return 0 unless $row;
    return $row;
}


sub store {
#    die;
    my $self = shift;
    my ($sid, $datastr) = @_;
    croak "store(): usage error" unless $sid && $datastr;


    my $dbh = $self->{Handle};
    my $sth = $dbh->prepare_cached("SELECT id FROM " . $self->table_name . " WHERE id=?", undef, 3);
    unless ( defined $sth ) {
        return $self->set_error( "store(): \$dbh->prepare failed with message " . $sth->errstr );
    }

    $sth->execute( $sid ) or return $self->set_error( "store(): \$sth->execute failed with message " . $sth->errstr );
    my $action_sth;
    if ( $sth->fetchrow_array ) {
        $action_sth = $dbh->prepare_cached("UPDATE " . $self->table_name . " SET a_session=? WHERE id=?", undef, 3);
    } else {
        $action_sth = $dbh->prepare_cached("INSERT INTO " . $self->table_name . " (a_session, id) VALUES(?, ?)", undef, 3);
    }
    
    unless ( defined $action_sth ) {
        return $self->set_error( "store(): \$dbh->prepare failed with message " . $dbh->errstr );
    }
    $action_sth->execute($datastr, $sid)
        or return $self->set_error( "store(): \$action_sth->execute failed " . $action_sth->errstr );
    return 1;
}


sub remove {
    my $self = shift;
    my ($sid) = @_;
    croak "remove(): usage error" unless $sid;

   my $rc = $self->{Handle}->do( 'DELETE FROM '. $self->table_name .' WHERE id= ?',{},$sid );
    unless ( $rc ) {
        croak "remove(): \$dbh->do failed!";
    }
    
    return 1;
}


sub DESTROY {
    my $self = shift;

    unless ( $self->{Handle}->{AutoCommit} ) {
        $self->{Handle}->commit;
    }
    if ( $self->{_disconnect} ) {
        $self->{Handle}->disconnect;
    }
}


sub traverse {
    my $self = shift;
    my ($coderef) = @_;

    unless ( $coderef && ref( $coderef ) && (ref $coderef eq 'CODE') ) {
        croak "traverse(): usage error";
    }

    my $tablename = $self->table_name();
    my $sth = $self->{Handle}->prepare_cached("SELECT id FROM $tablename", undef, 3) 
        or return $self->set_error("traverse(): couldn't prepare SQL statement. " . $self->{Handle}->errstr);
    $sth->execute() or return $self->set_error("traverse(): couldn't execute statement $sth->{Statement}. " . $sth->errstr);

    while ( my ($sid) = $sth->fetchrow_array ) {
        $coderef->($sid);
    }
    return 1;
}


1;

=pod

=head1 NAME

CGI::Session::Driver::DBI - Base class for native DBI-related CGI::Session drivers

=head1 SYNOPSIS

    require CGI::Session::Driver::DBI;
    @ISA = qw( CGI::Session::Driver::DBI );

=head1 DESCRIPTION

In most cases you can create a new DBI-driven CGI::Session driver by simply creating an empty driver file that inherits from CGI::Session::Driver::DBI. That's exactly what L<sqlite|CGI::Session::Driver::sqlite> does. The only reason why this class doesn't suit for a valid driver is its name isn't in lowercase. I'm serious!

=head2 NOTES

CGI::Session::Driver::DBI defines init() method, which makes DBI handle available for drivers in I<Handle> - object attribute regardless of what C<\%dsn_args> were used in creating session object. Should your driver require non-standard initialization you have to re-define init() method in your F<.pm> file, but make sure to set 'Handle' - object attribute to database handle (returned by DBI->connect(...)) if you wish to inherit any of the methods from CGI::Session::Driver::DBI.

=head1 STORAGE

Before you can use any DBI-based session drivers you need to make sure compatible database table is created for CGI::Session to work with. Following command will produce minimal requirements in most SQL databases:

    CREATE TABLE sessions (
        id CHAR(32) NOT NULL PRIMARY KEY,
        a_session TEXT NOT NULL
    );

Your session table can define additional columns, but the above two are required. Name of the session table is expected to be I<sessions> by default. You may use a different name if you wish. To do this you have to pass I<TableName> as part of your C< \%dsn_args >:

    $s = new CGI::Session("driver:sqlite", undef, {TableName=>'my_sessions'});
    $s = new CGI::Session("driver:mysql", undef, {
                                        TableName=>'my_sessions', 
                                        DataSource=>'dbi:mysql:shopping_cart'});

=head1 DRIVER ARGUMENTS

Following driver arguments are supported:

=over 4

=item DataSource

First argument to be passed to L<DBI|DBI>->L<connect()|DBI/connect()>. If the driver makes
the database connection itself, it will also explicitly disconnect from the database when 
the driver object is DESTROYed.

=item User

User privileged to connect to the database defined in C<DataSource>.

=item Password

Password of the I<User> privileged to connect to the database defined in C<DataSource>

=item Handle

An existing L<DBI> database handle object. The handle can be created on demand
by providing a code reference as a argument, such as C<<sub{DBI->connect}>>.
This way, the database connection is only created if it actually needed. This can be useful
when combined with a framework plugin like L<CGI::Application::Plugin::Session>, which creates
a CGI::Session object on demand as well. 

C<Handle> will override all the above arguments, if any present.

=item TableName

Name of the table session data will be stored in.

=back

=head1 LICENSING

For support and licensing information see L<CGI::Session|CGI::Session>

=cut

