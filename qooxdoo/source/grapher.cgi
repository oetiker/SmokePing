#!/usr/sepp/bin/perl-5.8.8 -w

require 5.008;
use strict;
use Getopt::Long 2.25 qw(:config posix_default no_ignore_case);
use Pod::Usage 1.14;
#use CGI::Fast;
use CGI;
use lib qw(/home/oetiker/scratch/rrd-13dev/lib/perl);
use lib qw(/usr/pack/rrdtool-1.2.23-mo/lib/perl/);
use RRDs;

'$Revision: 3879 $ ' =~ /Revision: (\S*)/;
my $Revision = $1;

# main loop
sub main()
{
    # parse options
    my %opt = ();
    GetOptions(\%opt, 'help|h', 'man', 'version', 'noaction|no-action|n',
       'verbose|v') or exit(1);
    if($opt{help})     { pod2usage(1) }
    if($opt{man})      { pod2usage(-exitstatus => 0, -verbose => 2) }
    if($opt{version})  { print "template_tool $Revision\n"; exit(0) }
    if($opt{noaction}) { die "ERROR: don't know how to \"no-action\".\n" }

#    while (my $q = new CGI::Fast) {
	my $q = new CGI;
	my $graph = $q->param('g');
	my $width = $q->param('w') || 300;
	my $height = $q->param('h') || 150;	
	warn "groesse: $width $height\n";
	RRDs::graph("/tmp/$$.tmpgraph",
		    '--title'		=> "Demo ".$graph,
	            '--vertical-label'	=> "Bytes/s",
		    '--start'		=> '20071101',
		    '--end' 		=> '20071112',
#		    '--zoom' 		=> '0.75',
		    '--width' 		=> $width,
		    '--height' 		=> $height,
		    '--color'		=> 'BACK#ffffff00',
		    '--color'		=> 'SHADEA#ffffff00',
		    '--color'		=> 'SHADEB#ffffff00',		
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
#    }
};

main;

__END__

=head1 NAME

template_tool - ISGTC tool template

=head1 SYNOPSIS

B<template_tool> [I<options>...]

     --man           show man-page and exit
 -h, --help          display this help and exit
     --version       output version information and exit

=head1 DESCRIPTION

Very useful hello-world application... With a magic marker
##ISGTC_MAGIC_SYSCONFDIR##.

=head1 COPYRIGHT

Copyright (c) 2006 by ETH Zurich. All rights reserved.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

=head1 AUTHOR

S<David Schweikert E<lt>dws@ee.ethz.chE<gt>>

=head1 HISTORY

 2006-XX-XX ds Initial Version

=cut

# Emacs Configuration
#
# Local Variables:
# mode: cperl
# eval: (cperl-set-style "PerlStyle")
# mode: flyspell
# mode: flyspell-prog
# End:
#
# vi: sw=4 et
