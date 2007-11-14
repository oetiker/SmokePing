package Qooxdoo::JSONRPC;

# qooxdoo - the new era of web development
#
# http://qooxdoo.org
#
# Copyright:
#   2006-2007 Nick Glencross
#
# License:
#   LGPL: http://www.gnu.org/licenses/lgpl.html
#   EPL: http://www.eclipse.org/org/documents/epl-v10.php
#   See the LICENSE file in the project's top-level directory for details.
#
# Authors:
#  * Nick Glencross

# The JSON-RPC implementation.
# Use perldoc on this file to view documentation

use strict;

use JSON;

use CGI;
#use CGI::Session;

# Enabling debugging will log information in the apache logs, and in
# some cases provide more information in error responses
$Qooxdoo::JSONRPC::debug = 0;

##############################################################################

# JSON-RPC error origins

use constant JsonRpcError_Origin_Server      => 1;
use constant JsonRpcError_Origin_Application => 2;
use constant JsonRpcError_Origin_Transport   => 3;
use constant JsonRpcError_Origin_Client      => 4;


# JSON-RPC server-generated error codes

use constant JsonRpcError_Unknown            =>  0;
use constant JsonRpcError_IllegalService     =>  1;
use constant JsonRpcError_ServiceNotFound    =>  2;
use constant JsonRpcError_ClassNotFound      =>  3;
use constant JsonRpcError_MethodNotFound     =>  4;
use constant JsonRpcError_ParameterMismatch  =>  5;
use constant JsonRpcError_PermissionDenied   =>  6;

# Method Accessibility values

use constant Accessibility_Public            => "public";
use constant Accessibility_Domain            => "domain";
use constant Accessibility_Session           => "session";
use constant Accessibility_Fail              => "fail";

use constant defaultAccessibility            => Accessibility_Domain;

# Script transport not-in-use setting

use constant ScriptTransport_NotInUse        => -1;

##############################################################################

# This is the main entry point for handling requests

sub handle_request
{
    my ($cgi, $session) = @_;

    my $session_id = $session->id ();

    print STDERR "Session id: $session_id\n" 
	if $Qooxdoo::JSONRPC::debug;

    print $session->header;

    # 'selfconvert' is enabled for date conversion. Ideally we also want
    # 'convblessed', but this then disabled 'selfconvert'.
    my $json = new JSON (selfconvert => 1);

    # Create the RPC error state

    my $error = new Qooxdoo::JSONRPC::error ($json);

    my $script_transport_id = ScriptTransport_NotInUse;

    #----------------------------------------------------------------------

    # Deal with various types of HTTP request and extract the JSON
    # body

    my $input;

    my $request_method = $cgi->request_method || '';

    if ($request_method eq 'POST')
    {
        my $content_type = $cgi->content_type;

        print STDERR "POST Content type is '$content_type'\n"
            if $Qooxdoo::JSONRPC::debug;

        if ($content_type eq 'application/json')
        {
            $input = $cgi->param('POSTDATA');
        }
        else
        {
            print "JSON-RPC request expected -- unexpected data received\n";
            exit;
        }
    }
    elsif ($request_method eq 'GET' &&
           defined $cgi->param ('_ScriptTransport_id') &&
           $cgi->param ('_ScriptTransport_id') != ScriptTransport_NotInUse &&
           defined $cgi->param ('_ScriptTransport_data'))
    {
        print STDERR "GET request\n" if $Qooxdoo::JSONRPC::debug;

        # We have what looks like a valid ScriptTransport request
        $script_transport_id = $cgi->param ('_ScriptTransport_id');
        $error->set_script_transport_id ($script_transport_id);

        $input = $cgi->param ('_ScriptTransport_data');
            
    }
    else
    {
        print "Your HTTP Client is not using the JSON-RPC protocol\n";
        exit;
    }

    #----------------------------------------------------------------------

    # Transform dates into JSON which the parser can handle
    Qooxdoo::JSONRPC::Date::transform_date (\$input);

    print STDERR "JSON received: $input\n" if $Qooxdoo::JSONRPC::debug;

    #----------------------------------------------------------------------

    # Convert the JSON string to a Perl datastructure

    $@ = '';
    my $json_input;
    eval
    {
        $json_input = $json->jsonToObj ($input);
    };

    if ($@)
    {
        print"A bad JSON-RPC request was received which could not be parsed\n";
        exit;
    }

    unless ($json_input && 
            exists $json_input->{service} &&
            exists $json_input->{method} &&
            exists $json_input->{params})
    {
        print "A bad JSON-RPC request was received\n";
        exit;
    }

    $error->set_id ($json_input->{id});

    #----------------------------------------------------------------------

    # Perform various sanity checks on the received request

    unless ($json_input->{service} =~ /^[_.a-zA-Z0-9]+$/)
    {
        $error->set_error (JsonRpcError_IllegalService,
                           "Illegal character found in service name");
        $error->send_and_exit;
    }

    if ($json_input->{service} =~ /\.\./)
    {
        $error->set_error (JsonRpcError_IllegalService,
                           "Illegal use of two consecutive dots " .
                           "in service name");
        $error->send_and_exit;
    }

    my @service_components = split (/\./, $json_input->{service});

    # Surely this can't actually happen after earlier checks?
    foreach (@service_components)
    {
        unless (/^[_.a-zA-Z0-9]+$/)
        {
            $error->set_error (JsonRpcError_IllegalService,
                               "A service name component does not begin " .
                               "with a letter");
            $error->send_and_exit;
        }
    }

    #----------------------------------------------------------------------

    # Generate the name of the module corresponding to the Service

    my $module = join ('::', ('Qooxdoo', 'Services', @service_components));

    # Attempt to load the module

    $@ = '';
    eval "require $module";

    if ($@)
    {
        print STDERR "$@\n" if $Qooxdoo::JSONRPC::debug;

        # The error description used here provides more information when
        # debugging, but probably reveals too much on a live stable
        # server

        if ($Qooxdoo::JSONRPC::debug)
        {
            $error->set_error (JsonRpcError_ServiceNotFound,
                               "Service '$module' could not be loaded ($@)");
        }
        else
        {
            $error->set_error (JsonRpcError_ServiceNotFound,
                               "Service '$module' not found");
        }
        $error->send_and_exit;
        
    }

    #----------------------------------------------------------------------

    # Determine the accessibility of the requested method

    my $method = $json_input->{method};

    my $accessibility = defaultAccessibility;

    my $accessibility_method = "${module}::GetAccessibility";
    
    if (defined &$accessibility_method)
    {
        print STDERR "Module $module has GetAccessibility\n"
            if $Qooxdoo::JSONRPC::debug;

        $@ = '';
        $accessibility = eval $accessibility_method . 
            '($method, $accessibility)';

        if ($@)
        {
            print STDERR "$@\n" if $Qooxdoo::JSONRPC::debug;
            
            $error->set_error (JsonRpcError_Unknown,
                               $@);
            $error->send_and_exit;
        }

        print STDERR "GetAccessibility for $method returns $accessibility\n"
            if $Qooxdoo::JSONRPC::debug;

    }

    #----------------------------------------------------------------------

    # Do referer checking based on accessibility

    if ($accessibility eq Accessibility_Public)
    {
        # Nothing to do as the method is always accessible
    }
    elsif ($accessibility eq Accessibility_Domain)
    {
        my $requestUriDomain;

        my $server_protocol = $cgi->server_protocol;

        my $is_https = $cgi->https ? 1 : 0;

        $requestUriDomain = $is_https ? 'https://' : 'http://';

        $requestUriDomain .= $cgi->server_name;

        $requestUriDomain .= ":" . $cgi->server_port 
            if $cgi->server_port != ($is_https ? 443 : 80);

        if ($cgi->referer !~ m|^(https?://[^/]*)|)
        {
            $error->set_error (JsonRpcError_PermissionDenied,
                               "Permission denied");
            $error->send_and_exit;
        }

        my $refererDomain = $1;

        if ($refererDomain ne $requestUriDomain)
        {
            $error->set_error (JsonRpcError_PermissionDenied,
                               "Permission denied");
            $error->send_and_exit;
        }
        
        if (!defined $session->param ('session_referer_domain'))
        {
            $session->param ('session_referer_domain', $refererDomain);
        }
            
    }
    elsif ($accessibility eq Accessibility_Session)
    {
        if ($cgi->referer !~ m|^(https?://[^/]*)|)
        {
            $error->set_error (JsonRpcError_PermissionDenied,
                               "Permission denied");
            $error->send_and_exit;
        }

        my $refererDomain = $1; 

        if (defined $session->param ('session_referer_domain') &&
            $session->param ('session_referer_domain') ne $refererDomain)
        {
            $error->set_error (JsonRpcError_PermissionDenied,
                               "Permission denied");
            $error->send_and_exit;
        }
        else
        {
            $session->param ('session_referer_domain', $refererDomain);
        }
    }
    elsif ($accessibility eq Accessibility_Fail)
    {
        $error->set_error (JsonRpcError_PermissionDenied,
                           "Permission denied");
        $error->send_and_exit;

    }
    else
    {
        $error->set_error (JsonRpcError_PermissionDenied,
                           "Service error: unknown accessibility");
        $error->send_and_exit;
    }

    #----------------------------------------------------------------------

    # Generate the name of the function to call and check it exists

    my $package_method = "${module}::method_${method}";
    
    unless (defined &$package_method)
    {
        $error->set_error (JsonRpcError_MethodNotFound,
                           "Method '$method' not found " .
                           "in service class '$module'");
        $error->send_and_exit;
    }

    #----------------------------------------------------------------------

    # Errors from here come from the Application

    $error->set_origin (JsonRpcError_Origin_Application);

    # Retrieve the arguments

    my $params = $json_input->{params};

    unless (ref $params eq 'ARRAY')
    {
        $error->set_error (JsonRpcError_ParameterMismatch,
                           "Arguments were not received in an array");
        $error->send_and_exit;
    }

    my @params = @{$params};

    # Do a shallow scan of parameters, and promote hashes which are
    # dates
    foreach (@params)
    {
        if (ref eq 'HASH' &&
            exists $_->{Qooxdoo_date})
        {
            bless $_, 'Qooxdoo::JSONRPC::Date';
        }
    }

    # Invoke the method dynamically using eval

    $@ = '';
    my @result = eval $package_method .  '($error, @params)';

    if ($@)
    {
        print STDERR "$@\n" if $Qooxdoo::JSONRPC::debug;

        $error->set_error (JsonRpcError_Unknown,
                           $@);
        $error->send_and_exit;
        
    }

    # (I've had to assume this behaviour based on the test results)

    my $result;

    if ($#result == 0)
    {
        $result = shift @result;
    }
    else
    {
        $result = \@result;
    }

    # Either send an error, or the application response

    if (ref $result eq 'Qooxdoo::JSONRPC::error')
    {
        $error->send_and_exit ();
    }

    $result = {id     => $json_input->{id},
               result => $result};

    send_reply ($json->objToJson ($result), $script_transport_id);
}


##############################################################################

# Send the application response

sub send_reply
{
    my ($reply, $script_transport_id) = @_;

    if ($script_transport_id == ScriptTransport_NotInUse)
    {
        print STDERR "Send $reply\n" if $Qooxdoo::JSONRPC::debug;
        print $reply;
    }
    else
    {
        $reply = "qx.io.remote.ScriptTransport._requestFinished" .
            "($script_transport_id, $reply);";

        print STDERR "Send $reply\n" if $Qooxdoo::JSONRPC::debug;
        print $reply;
    }
}


##############################################################################

# These two routines are useful to the Services themselves

sub json_bool
{
    my $value = shift;

    return $value ? JSON::True : JSON::False;
}


sub json_istrue
{
    my $value = shift;

    my $is_true = ref $value eq 'JSON::NotString'
        && defined $value->{value} && $value->{value} eq 'true';

    return $is_true;
}

##############################################################################

package Qooxdoo::JSONRPC::error;

use strict;

# The error object enumerates various types of error

sub new
{
    my $self          = shift ;
    my $class         = ref ($self) || $self ;

    my $json          = shift ;
    my $origin        = shift || Qooxdoo::JSONRPC::JsonRpcError_Origin_Server;
    my $code          = shift || Qooxdoo::JSONRPC::JsonRpcError_Unknown;
    my $message       = shift || "Unknown error";

    $self = bless
    {
        json                => $json,
        origin              => $origin,
        code                => $code,
        message             => $message,
        script_transport_id => Qooxdoo::JSONRPC::ScriptTransport_NotInUse

    }, $class ;

    return $self ;
}

sub set_origin
{
    my $self   = shift;
    my $origin = shift;

    $self->{origin} = $origin;
}

sub set_error
{
    my $self    = shift;
    my $code    = shift;
    my $message = shift;

    $self->{code}    = $code;
    $self->{message} = $message;
}

sub set_id
{
    my $self   = shift;
    my $id     = shift;

    $self->{id} = $id;
}

sub set_script_transport_id
{
    my $self                = shift;
    my $script_transport_id = shift;

    $self->{script_transport_id} = $script_transport_id;
}


sub send_and_exit
{
    my $self                = shift;

    my $result = {'id'    => $self->{id},
                  'error' => {origin  => $self->{origin},
                              code    => $self->{code},
                              message => $self->{message}}};

    my $script_transport_id =  $self->{script_transport_id};

    Qooxdoo::JSONRPC::send_reply ($self->{json}->objToJson ($result),
                                  $script_transport_id);
    exit;
}

##############################################################################

# Implementation of a Date class with set/get methods

package Qooxdoo::JSONRPC::Date;

use strict;

sub new
{
    my $self   = shift ;
    my $class  = ref ($self) || $self ;

    my $time   = shift;
    $self = bless {}, $class ;

    $self->set_epoch_time ($time);

    return $self ;
}


sub set_epoch_time
{
    my $self = shift;
    my $time = shift;

    $time = time () unless defined $time;

    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
        gmtime ($time);

    $self->{year}        = 1900+$year;
    $self->{month}       = $mon; # Starts from 0
    $self->{day}         = $mday;
    $self->{hour}        = $hour;
    $self->{minute}      = $min;
    $self->{second}      = $sec;
    $self->{millisecond} = 0;

    return $self;
}


# Month is passed in 1..12, but stored 0..11

sub set
{
    my $self = shift;
    my ($year, $month, $day, $hour, $minute, $second, $millisecond) = @_;

    $hour        ||= 0;
    $minute      ||= 0;
    $second      ||= 0;
    $millisecond ||= 0;

    $self->{year}        = $year;
    $self->{month}       = $month-1;
    $self->{day}         = $day;
    $self->{hour}        = $hour;
    $self->{minute}      = $minute;
    $self->{second}      = $second;
    $self->{millisecond} = $millisecond;
}

sub set_year
{
    my $self = shift;
    my $year = shift;

    $self->{year} = $year;
}

sub set_month
{
    my $self  = shift;
    my $month = shift;

    $self->{month} = $month-1;
}


sub set_day
{
    my $self = shift;
    my $day = shift;

    $self->{day} = $day;
}


sub set_hour
{
    my $self = shift;
    my $hour = shift;

    $self->{hour} = $hour;
}


sub set_minute
{
    my $self   = shift;
    my $minute = shift;

    $self->{minute} = $minute;
}

sub set_second
{
    my $self   = shift;
    my $second = shift;

    $self->{second} = $second;
}

sub set_millisecond
{
    my $self        = shift;
    my $millisecond = shift;

    $self->{millisecond} = $millisecond;
}




sub get_year
{
    my $self = shift;

    return $self->{year};
}

sub get_month
{
    my $self  = shift;

    return $self->{month}+1;
}


sub get_day
{
    my $self = shift;

    return $self->{day};
}


sub get_hour
{
    my $self = shift;

    return $self->{hour};
}


sub get_minute
{
    my $self   = shift;

    return $self->{minute};
}

sub get_second
{
    my $self   = shift;

    return $self->{second};
}

sub get_millisecond
{
    my $self        = shift;

    return $self->{millisecond};
}


# This is the special method used by the JSON module to serialise a class.
# The feature is enabled with the 'selfconvert' parameter

sub toJson
{
    my $self = shift;

    my $time = $self->{time};

    my $year        = $self->{year};
    my $month       = $self->{month};
    my $day         = $self->{day};
    my $hour        = $self->{hour};
    my $minute      = $self->{minute};
    my $second      = $self->{second};
    my $millisecond = $self->{millisecond};

    return sprintf 'new Date(Date.UTC(%d,%d,%d,%d,%d,%d,%d))',
    $year,
    $month,
    $day,
    $hour,
    $minute,
    $second,
    $millisecond;
}

# Routine to convert the date embedded in the JSON string to something
# that can be parsed

sub transform_date
{
    my $input_ref = shift;

    ${$input_ref} =~ 
        s/new\s+Date\s*\(Date.UTC\(
           (\d+),(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)\)/
        blessed_date($1,$2,$3,$4,$5,$6,$7)/gxe;
}

# This function is called by the regexp in transform_date

sub blessed_date
{
    my ($year, $month, $day, $hour, $minute, $second, $millisecond) = @_;

    return sprintf('{"Qooxdoo_date":1,"year":%d,"month":%d,"day":%d,"hour":%d,"minute":%d,"second":%d,"millisecond":%d}',
                   $year,
                   $month,
                   $day,
                   $hour,
                   $minute,
                   $second,
                   $millisecond);
}



##############################################################################

=head1 NAME

Qooxdoo::JSONRPC.pm - A Perl implementation of JSON-RPC for Qooxdoo

=head1 SYNOPSIS

RPC-JSON is a straightforward Remote Procedure Call mechanism, primarily
targeted at Javascript clients, and hence ideal for Qooxdoo.

Services may be implemented in any language provided they provide a
conformant implementation. This module uses the CGI module to parse
HTTP headers, and the JSON module to manipulate the JSON body.

A simple, but typical exchange might be:

client->server:

   {"service":"qooxdoo.test","method":"echo","id":1,"params":["Hello"],"server_data":null}

server->client:

   {"id":1,"result":"Client said: [Hello]"}

Here the service 'qooxdoo.test' is requested to run a method called
'echo' with an argument 'Hello'. This Perl implementation will locate
a module called Qooxdoo::Services::qooxdoo::test (corresponding to
Qooxoo/Services/qooxdoo/test.pm in Perl's library path). It will
then execute the function Qooxdoo::Services::qooxdoo::test::echo
with the supplied arguments.

The function will receive the error object as the first argument, and
subsequent arguments are supplied by the remote call. Your method call
would therefore start with something equivalent to:

    my $error  = shift;
    my @params = @_;

See test.pm for how to deal with errors and return responses.

The response is sent back with the corresponding id (essential for
asynchronous calls).

The protocol also provides an exception handling mechanism, where a
response is formatted something like:

    {"error":{"origin":2,"code":23,"message":"This is an application-provided error"},"id":21}

There are 4 error origins:

=over 4

=item * JsonRpcError_Origin_Server 1

The error occurred within the server.

=item * JsonRpcError_Origin_Application 2

The error occurred within the application.

=item * JsonRpcError_Origin_Transport 3

The error occurred somewhere in the communication (not raised in this module).

=item * JsonRpcError_Origin_Client 4

The error occurred in the client (not raised in this module).

=back

For Server errors, there are also some predefined error codes.

=over 4

=item * JsonRpcError_Unknown 0

The cause of the error was not known.

=item * JsonRpcError_IllegalService 1

The Service name was not valid, typically due to a bad character in the name.

=item * JsonRpcError_ServiceNotFound 2

The Service was not found. In this implementation this means that the
module containing the Service could not be found in the library path.

=item * JsonRpcError_ClassNotFound 3

This means the class could not be found with, is not actually raised
by this implementation.

=item * JsonRpcError_MethodNotFound 4

The method could not be found. This is raised if a function cannot be
found with the method name in the requested package namespace.

Note: In Perl, modules (files containing functionality) and packages
(namespaces) are closely knitted together, but there need not be a
one-for-one correspondence -- packages can be shared across multiple
modules, or a module can use multiple packages. This module assumes a
one-for-one correspondence by looking for the method in the same
namespace as the module name.

=item * JsonRpcError_ParameterMismatch 5

This is typically raised by individual methods when they do not
receive the parameters they are expecting.

=item * JsonRpcError_PermissionDenied 6

Again, this error is raised by individual methods. Remember that RPC
calls need to be as secure as the rest of your application!

=back

There is also some infrastructure to allow access control on methods
depending on the relationship of the referer. Have a look at test.pm
to see how this can be done by defining C<GetAccessibility> which
returns one of the following for a supplied method name:

=over 4

=item * Accessibility_Public ("public")

The method may be called from any session, and without any checking of
who the Referer is.

=item * Accessibility_Domain ("domain")

The method may only be called by a script obtained via a web page
loaded from this server.  The Referer must match the request URI,
through the domain part.

=item * Accessibility_Session ("session")

The Referer must match the Referer of the very first RPC request
issued during the session.

=item * Accessibility_Fail ("fail")

Access is denied

=back

=head1 AUTHOR

Nick Glencross E<lt>nick.glencross@gmail.comE<gt>

=cut


1;
