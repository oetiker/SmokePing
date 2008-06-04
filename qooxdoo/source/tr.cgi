#!/usr/sepp/bin/speedy-5.8.8 -w
use strict;
use lib qw(/home/oposs/smokeping/software/lib);
use lib qw(perl);

use CGI;
use CGI::Util qw(expires);
use CGI::Session;
use Qooxdoo::JSONRPC;

#$Qooxdoo::JSONRPC::debug=1;

# Change this space-separated list of directories to include
# Qooxdoo::JSONRPC.pm and co-located Services

# If this module can't be found, the previous line is incorrect

# Instantiating the CGI module which parses the HTTP request

my $cgi     = new CGI;
my $session = new CGI::Session;

# You can customise this harness here to handle cases before treating
# the request as being JSON-RPC
Qooxdoo::JSONRPC::handle_request ($cgi, $session);

