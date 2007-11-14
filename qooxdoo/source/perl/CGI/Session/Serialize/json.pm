package CGI::Session::Serialize::json;

use strict;
use CGI::Session::ErrorHandler;

$CGI::Session::Serialize::json::VERSION = '4.20';
@CGI::Session::Serialize::json::ISA     = ( "CGI::Session::ErrorHandler" );
our $Flavour;

unless($Flavour) {
    my $package = (grep { eval("use $_ (); 1;") } qw(JSON::Syck))[0]
        or die "JSON::Syck is required to use ", __PACKAGE__;
    $Flavour = $package;
}

sub freeze {
    my ($self, $data) = @_;
    return $Flavour->can('Dump')->($data);
}


sub thaw {
    my ($self, $string) = @_;
    return ($Flavour->can('Load')->($string))[0];
}

1;

__END__;

=pod

=head1 NAME

CGI::Session::Serialize::json - serializer for CGI::Session

=head1 DESCRIPTION

This library can be used by CGI::Session to serialize session data. Requires
L<JSON::Syck|JSON::Syck>. JSON is a type of L<YAML|CGI::Session::Serialize::yaml>,
with one extension: serialized JSON strings are actually valid JavaScript
code that a browser can execute. Any langauge that has a YAML parser
(Perl, PHP, Python, Ruby, C, etc) can also read data that has been serialized
with JSON.

=head1 METHODS

=over 4

=item freeze($class, \%hash)

Receives two arguments. First is the class name, the second is the data to be serialized. Should return serialized string on success, undef on failure. Error message should be set using C<set_error()|CGI::Session::ErrorHandler/"set_error()">

=item thaw($class, $string)

Received two arguments. First is the class name, second is the I<JSON> data string. Should return thawed data structure on success, undef on failure. Error message should be set using C<set_error()|CGI::Session::ErrorHandler/"set_error()">

=back

=head1 SEE ALSO

L<CGI::Session>, L<JSON::Syck>.

=cut
