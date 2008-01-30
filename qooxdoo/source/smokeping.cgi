#!/usr/sepp/bin/perl-5.8.8 -w
use strict;
use lib qw( perl );

use CGI;
use CGI::Session;
use Qooxdoo::JSONRPC;
use lib qw(/home/oetiker/scratch/rrd-13dev/lib/perl);
use lib qw(/usr/pack/rrdtool-1.2.23-mo/lib/perl/);
use RRDs;

$Qooxdoo::JSONRPC::debug=1;

# Change this space-separated list of directories to include
# Qooxdoo::JSONRPC.pm and co-located Services

# If this module can't be found, the previous line is incorrect

# Instantiating the CGI module which parses the HTTP request

my $cgi     = new CGI;
my $session = new CGI::Session;

# You can customise this harness here to handle cases before treating
# the request as being JSON-RPC
if ($cgi->param('g')){
	my $graph = $cgi->param('g');
	my $width = $cgi->param('w');
	my $height = $cgi->param('h');
	my $start = $cgi->param('s');
	my $end = $cgi->param('e');
	my $top = $cgi->param('t');	
	my $bottom = $cgi->param('b');
	warn "groesse: $width $height\n";
	RRDs::graph("/tmp/$$.tmpgraph",
		    '--title'		=> "Demo ".$graph,
	            '--vertical-label'	=> "Bytes/s",
		    '--start'		=> $start,			
		    '--end' 		=> $end,
		    '--upper-limit'	=> $top,
		    '--lower-limit'	=> $bottom,
		    '--rigid',
#		    '--zoom' 		=> '0.75',
		    '--width' 		=> $width,
		    '--height' 		=> $height,
		    '--color'		=> 'BACK#f0f0f0ff',
		    '--color'		=> 'SHADEA#f0f0f0ff',
		    '--color'		=> 'SHADEB#f0f0f0ff',		
		    'DEF:in=lan.rrd:out:AVERAGE',
		    'CDEF:green=in,100000,LT,in,100000,IF',
		    'AREA:green#00ff00',
		    'CDEF:red=in,50000,LT,in,50000,IF',
		    'AREA:red#ff0000',
		    'LINE1:in#2020ff:Input',
		    'CDEF:flip=LTIME,172800,%,86400,LT,in,UNKN,IF',
		    'AREA:flip#00000088');
	my $ERROR = RRDs::error();
        die $ERROR if $ERROR;
	if (open (my $fh,"</tmp/$$.tmpgraph")){
	    local $/=undef;
	    my $image = <$fh>;
	    unlink "/tmp/$$.tmpgraph";
	    close $fh;
            print "Content-Type: image/png\n";
	    print "Expires: Thu, 15 Apr 2010 20:00:00 GMT\n";
	    print "Length: ".length($image)."\n";
	    print "\n";
	    print $image;
	};
} else {
	Qooxdoo::JSONRPC::handle_request ($cgi, $session);
}

