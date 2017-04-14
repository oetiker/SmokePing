package Smokeping::RRDtools;

=head1 NAME

Smokeping::RRDtools - Tools for RRD file handling

=head1 SYNOPSIS

 use Smokeping::RRDtools;
 use RRDs;

 my $file = '/path/to/file.rrd';

 # get the create arguments that $file was created with
 my $create = Smokeping::RRDtools::info2create($file);

 # use them to create a new file
 RRDs::create('/path/to/file2.rrd', @$create);

 # or compare them against another create list
 my @create = ('--step', 60, 'DS:ds0:GAUGE:120:0:U', 'RRA:AVERAGE:0.5:1:1008');
 my ($fatal, $comparison) = Smokeping::RRDtools::compare($file, \@create);
 print "Fatal: " if $fatal;
 print "Create arguments didn't match: $comparison\n" if $comparison;

 Smokeping::RRDtools::tuneds($file, \@create);
 
=head1 DESCRIPTION

This module offers three functions, C<info2create>, C<compare> and
C<tuneds>. The first can be used to recreate the arguments that an RRD file
was created with. The second checks if an RRD file was created with the
given arguments. The thirds tunes the DS parameters according to the
supplied create string.

The function C<info2create> must be called with one argument:
the path to the interesting RRD file. It will return an array
reference of the argument list that can be fed to C<RRDs::create>.
Note that this list will never contain the C<start> parameter,
but it B<will> contain the C<step> parameter.

The function C<compare> must be called with two arguments: the path to the
interesting RRD file, and a reference to an argument list that could be fed
to C<RRDs::create>. The function will then simply compare the result of
C<info2create> with this argument list. It will return an array of two values:
C<(fatal, text)> where  C<fatal> is 1 if it found a fatal difference, and 0 if not.
The C<text> will contain an error message if C<fatal == 1> and a possible warning 
message if C<fatal == 0>. If C<fatal == 0> and C<text> is C<undef>, all the
arguments matched.

Note that if there is a C<start> parameter in the argument list,
C<compare> disregards it. If C<step> isn't specified, C<compare> will use
the C<rrdtool> default of 300 seconds. C<compare> ignores non-matching DS
parameters since C<tuneds> will fix them.

C<tuneds> talks on stderr about the parameters it fixes.

=head1 NOTES

This module is not particularly specific to Smokeping, it is just
distributed with it.

=head1 BUGS

Probably.

=head1 COPYRIGHT

Copyright (c) 2005 by Niko Tyni.

=head1 AUTHOR

Niko Tyni <ntyni@iki.fi>

=head1 LICENSE

This program is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.  See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public
License along with this program; if not, write to the Free
Software Foundation, Inc., 675 Mass Ave, Cambridge, MA
02139, USA.

=head1 SEE ALSO

RRDs(3)

=cut

use strict;
use RRDs;

# take an RRD file and make a create list out of it
sub info2create {
	my $file = shift;
	my @create;
	# check for Perl version 5.8.0, it's buggy
	# no more v-strings 
        my $buggy_perl_version = 1 if abs($] - 5.008000) < .0000005;

	my $info = RRDs::info($file);
	my $error = RRDs::error;
	die("RRDs::info $file: ERROR: $error") if $error;
	die("$file: unknown RRD version: $info->{rrd_version}")
		unless $info->{rrd_version} eq '0001'
		or     $info->{rrd_version} eq '0003';
	my $cf = $info->{"rra[0].cf"};
	die("$file: no RRAs found?") 
		unless defined $cf;
	my @fetch = RRDs::fetch($file, $cf, "-s 0", "-e 0");
	$error = RRDs::error;
	die("RRDs::fetch $file $cf: ERROR: $error") if $error;
	my @ds = @{$fetch[2]};

	push @create, '--step', $info->{step};
	for my $ds (@ds) {
		my @s = ("DS", $ds);
		for (qw(type minimal_heartbeat min max)) {
			die("$file: missing $_ for DS $ds?")
				unless exists $info->{"ds[$ds].$_"}
                or $buggy_perl_version;
			my $val = $info->{"ds[$ds].$_"};
			push @s, defined $val ? $val : "U";
		}
		push @create, join(":", @s);
	}
	for (my $i=0; exists $info->{"rra[$i].cf"}; $i++) {
		my @s = ("RRA", $info->{"rra[$i].cf"});
		for (qw(xff pdp_per_row rows)) {
			die("$file: missing $_ for RRA $i")
				unless exists $info->{"rra[$i].$_"}
                or $buggy_perl_version;
			push @s, $info->{"rra[$i].$_"};
		}
		push @create, join(":", @s);
	}
	return \@create;
}

sub compare {
	my $file = shift;
	my $create = shift;
	my @create2 = @{info2create($file)};
	my @create = @$create; # copy because we change it
	# we don't compare the '--start' param
	if ($create[0] eq '--start') {
		shift @create;
		shift @create;
	}
	# special check for the optional 'step' parameter
	die("Internal error: didn't get the step parameter from info2create?")
		unless ("--step" eq shift @create2);
	my $step = shift @create2;
	my $step2;
	if ($create[0] eq '--step') {
		shift @create;
		$step2 = shift @create;
	} else {
		$step2 = 300; # default value
	}
	return (1, "Wrong value of step: $file has $step, create string has $step2")
		unless $step == $step2;
	
	my $dscount = grep /^DS/, @create;
	my $dscount2 = grep /^DS/, @create2;
	return (1, "Different number of data sources: $file has $dscount2, create string has $dscount")
		unless $dscount == $dscount2;
	my $rracount = grep /^RRA/, @create;
	my $rracount2 = grep /^RRA/, @create2;
	return (1, "Different number of RRAs: $file has $rracount2, create string has $rracount")
		unless $rracount == $rracount2;

	my $warning;
	while (my $arg = shift @create) {
		my $arg2 = shift @create2;
		my @ds = split /:/, $arg;
		my @ds2 = split /:/, $arg2;
		next if $ds[0] eq 'DS' and $ds[0] eq $ds2[0] and $ds[1] eq $ds2[1] and $ds[2] eq $ds2[2];
		if ($arg ne $arg2) {
			if ($ds[0] eq 'RRA' and $ds[0] eq $ds2[0] and $ds[1] eq $ds2[1]) {
				# non-fatal: CF is the same, but xff/steps/rows differ
				$warning .= "Different RRA parameters: $file has $arg2, create string has $arg";
			} else {
				return (1, "Different arguments: $file has $arg2, create string has $arg");
			}
		}
	}
	return (0, $warning);
}

sub tuneds {
        my $file = shift;
        my $create = shift;
        my @create2 = sort grep /^DS/, @{info2create($file)};
	my @create = sort grep /^DS/,  @$create;
	while (@create){
	       my @ds = split /:/, shift @create;
	       my @ds2 = split /:/, shift @create2;
	       next unless $ds[1] eq $ds2[1] and $ds[2] eq $ds[2];
	       if ($ds[3] ne $ds2[3]){
	       		warn "## Updating $file DS:$ds[1] heartbeat $ds2[3] -> $ds[3]\n";
	  	        RRDs::tune $file,"--hearbeat","$ds[1]:$ds[3]" unless $ds[3] eq $ds2[3];
	       }
	       if ($ds[4] ne $ds2[4]){
	       		warn "## Updating $file DS:$ds[1] minimum $ds2[4] -> $ds[4]\n";
	 	        RRDs::tune $file,"--minimum","$ds[1]:$ds[4]" unless $ds[4] eq $ds2[4];
	       }
	       if ($ds[5] ne $ds2[5]){
	       		warn "## Updating $file DS:$ds[1] maximum $ds2[5] -> $ds[5]\n";
	                RRDs::tune $file,"--maximum","$ds[1]:$ds[5]" unless $ds[5] eq $ds2[5];
	       }
	}
}	
		                        
1;
