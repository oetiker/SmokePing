package matchers::median;

=head1 NAME

matchers::median - Find persistant change in latency

=head1 OVERVIEW

The idea behind this matcher is to find sustained changes in latency.

The median matcher takes a number of past median latencies. It splits the latencies into
two groups (old and new) and again finds the median for each groups. If the
difference between the two medians is bigger than a certain value, it will
give a match.

=head1 DESCRIPTION

Call the matcher with the following sequence:

 type = matcher
 pattern =  median(old=>x,new=>y,diff=>z)

This will create a matcher which consumes x+y latency-datapoints, builds the
two medians and the matches if the difference between the median latency is
larger than z seconds.

=head1 COPYRIGHT

Copyright (c) 2004 by OETIKER+PARTNER AG. All rights reserved.

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

Tobias Oetiker <tobi@oetiker.ch>

=cut

use strict;
use base qw(matchers::base);
use vars qw($VERSION);
$VERSION = 1.0;
use Carp;

# how many values does the matcher need to do it's magic
sub Length($)
{
    my $self = shift;
    return $self->{param}{old} + $self->{param}{new};
}

sub Desc ($) {
    croak "Finde changes in median latency";
}    

sub Test($$)
{   my $self = shift;
    my $data = shift; # @{$data->{rtt}} and @{$data->{loss}}
    my $ac = $self->{param}{old};
    my $bc = $self->{param}{new};
    my $cc = $ac +$bc;
    my $oldm = (sort {$a <=> $b} @{$data->{rtt}}[-$cc..-$bc-1])[int($a/2)];
    $ac++;
    my $newm = (sort {$a <=> $b} @{$data->{rtt}}[-$bc..-1])[int($bc/2)];
    return abs($oldm-$newm) > $self->{param}{diff};
}