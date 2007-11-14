package CGI::Session::ErrorHandler;

# $Id: ErrorHandler.pm 351 2006-11-24 14:16:50Z markstos $

use strict;
$CGI::Session::ErrorHandler::VERSION = "4.20";

=pod

=head1 NAME

CGI::Session::ErrorHandler - error handling routines for CGI::Session

=head1 SYNOPSIS

    require CGI::Session::ErrorHandler
    @ISA = qw( CGI::Session::ErrorHandler );

    sub some_method {
        my $self = shift;
        unless (  $some_condition ) {
            return $self->set_error("some_method(): \$some_condition isn't met");
        }
    }

=head1 DESCRIPTION

CGI::Session::ErrorHandler provides set_error() and errstr() methods for setting and accessing error messages from within CGI::Session's components. This method should be used by driver developers for providing CGI::Session-standard error handling routines for their code

=head2 METHODS

=over 4

=item set_error($message)

Implicitly defines $pkg_name::errstr and sets its value to $message. Return value is B<always> undef.

=cut

sub set_error {
    my $class   = shift;
    my $message = shift;
    $class = ref($class) || $class;
    no strict 'refs';
    ${ "$class\::errstr" } = sprintf($message || "", @_);
    return;
}

=item errstr()

Returns whatever value was set by the most recent call to set_error(). If no message as has been set yet, the empty string is returned so the message can still concatenate without a warning. 

=back

=cut 

*error = \&errstr;
sub errstr {
    my $class = shift;
    $class = ref( $class ) || $class;

    no strict 'refs';
    return ${ "$class\::errstr" } || '';
}

=head1 LICENSING

For support and licensing information see L<CGI::Session|CGI::Session>.

=cut

1;

