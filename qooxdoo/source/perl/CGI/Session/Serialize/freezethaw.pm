package CGI::Session::Serialize::freezethaw;

# $Id: freezethaw.pm 351 2006-11-24 14:16:50Z markstos $ 

use strict;
use FreezeThaw;
use CGI::Session::ErrorHandler;

$CGI::Session::Serialize::freezethaw::VERSION = 4.2;
@CGI::Session::Serialize::freezethaw::ISA     = ( "CGI::Session::ErrorHandler" );

sub freeze {
    my ($self, $data) = @_;
    return FreezeThaw::freeze($data);
}


sub thaw {
    my ($self, $string) = @_;
    return (FreezeThaw::thaw($string))[0];
}

1;

__END__;

=pod

=head1 NAME

CGI::Session::Serialize::freezethaw - serializer for CGI::Session

=head1 DESCRIPTION

This library can be used by CGI::Session to serialize session data. Uses L<FreezeThaw|FreezeThaw>.

=head1 METHODS

=over 4

=item freeze($class, \%hash)

Receives two arguments. First is the class name, the second is the data to be serialized. Should return serialized string on success, undef on failure. Error message should be set using C<set_error()|CGI::Session::ErrorHandler/"set_error()">

=item thaw($class, $string)

Received two arguments. First is the class name, second is the I<frozen> data string. Should return thawed data structure on success, undef on failure. Error message should be set using C<set_error()|CGI::Session::ErrorHandler/"set_error()">

=back

=head1 LICENSING

For support and licensing see L<CGI::Session|CGI::Session>

=cut
