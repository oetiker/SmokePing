# -*- perl -*-
package Smokeping::RRDhelpers;

=head1 NAME

Smokeping::RRDhelpers - Functions for doing 'interesting things' with RRDs.

=head1 OVERVIEW

This module holds a collection of functions for doing advanced calculations
and effects on rrd files.

=cut

use strict;
use RRDs;

=head2 IMPLEMENTATION

=head3 get_stddev(rrd,ds,cf,start,end[,step])

Pull the data values off the rrd file and calculate the standard deviation. Nan
values get ignored in this process.

=cut

sub get_stddev{
    my $rrd = shift;
    my $ds = shift;
    my $cf = shift;
    my $start = shift;
    my $end = shift;
    my $step = shift;
    my ($realstart,$realstep,$names,$array) = RRDs::fetch $rrd, $cf, '--start',$start, '--end',$end,($step ? ('--resolution',$step):());
    if (my $err = RRDs::error){
        warn $err
    };
    my $idx = 0;
    for (@$names){
        last if $ds eq $_;
        $idx ++;
    }
    my $sum = 0;
    my $sqsum = 0;
    my $cnt = 0;
    foreach my $line (@$array){
        my $val = $line->[$idx];
        if (defined $val){
            $cnt++;
            $sum += $val;
            $sqsum += $val**2;
        }
    }
    return undef unless $cnt;
    my $sqdev =  1.0 / $cnt * ( $sqsum - $sum**2 / $cnt );
    return $sqdev < 0.0 ? 0.0 : sqrt($sqdev);
}



1;

__END__

=head1 COPYRIGHT

Copyright 2007 by Tobias Oetiker

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

=head1 AUTHOR

Tobias Oetiker E<lt>tobi@oetiker.chE<gt>

=cut
