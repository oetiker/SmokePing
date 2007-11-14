package CGI::Session::Serialize::storable;

# $Id: storable.pm 351 2006-11-24 14:16:50Z markstos $

use strict;
use Storable;
require CGI::Session::ErrorHandler;

$CGI::Session::Serialize::storable::VERSION = "4.20";
@CGI::Session::Serialize::ISA               = ( "CGI::Session::ErrorHandler" );

=pod

=head1 NAME

CGI::Session::Serialize::storable - Serializer for CGI::Session

=head1 DESCRIPTION

This library can be used by CGI::Session to serialize session data. Uses L<Storable|Storable>.

=head1 METHODS

=over 4

=item freeze($class, \%hash)

Receives two arguments. First is the class name, the second is the data to be serialized.
Should return serialized string on success, undef on failure. Error message should be set using
C<set_error()|CGI::Session::ErrorHandler/"set_error()">

=cut

sub freeze {
    my ($self, $data) = @_;
    return Storable::freeze($data);
}

=item thaw($class, $string)

Receives two arguments. First is the class name, second is the I<frozen> data string. Should return
thawed data structure on success, undef on failure. Error message should be set
using C<set_error()|CGI::Session::ErrorHandler/"set_error()">

=back

=cut

sub thaw {
    my ($self, $string) = @_;
    return Storable::thaw($string);
}

=head1 LICENSING

For support and licensing see L<CGI::Session|CGI::Session>

=cut

1;
