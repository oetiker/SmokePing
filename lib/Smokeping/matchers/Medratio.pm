package Smokeping::matchers::Medratio;

=head1 NAME

Smokeping::matchers::Medratio - detect changes in the latency median

=head1 OVERVIEW

The Medratio matcher establishes a historic median latency over
several measurement rounds. It compares this median, against a second
median latency value again build over several rounds of measurement.

By looking at the median value this matcher is largly imune against spikes
and will only react to long term developments.

=head1 DESCRIPTION

Call the matcher with the following sequence:

 type = matcher
 pattern =  Medratio(historic=>a,current=>b,comparator=>o,percentage=>p)

=over

=item historic

The number of values to use for building the 'historic' median.

=item current

The number of values to use for building the 'current' median.

=item comparator

Which comparison operator should be used to compare current/historic with percentage.

=item percentage

Right hand side of the comparison.

=back

  old <--- historic ---><--- current ---> now

=head1 EXAMPLE

Take  the 12 last median values. Build the median out of the first 10
and the median from the other 2 values. Divide the results and decide
if it is bigger than 150 percent.

 Medratio(historic=>10,current=>2,comparator=>'>',percentage=>150);

 med(current)/med(historic) > 150/100

This means the matcher will activate when the current latency median is
more than 1.5 times the historic latency median established over the last
10 rounds of measurement.

=head1 COPYRIGHT

Copyright (c) 2006 by OETIKER+PARTNER AG. All rights reserved.

=head1 SPONSORSHIP

The development of this matcher has been paied for by Virtela
Communications, L<http://www.virtela.net/>.

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

use vars qw($VERSION);


$VERSION = 1.0;

use strict;
use base qw(Smokeping::matchers::Avgratio);
use Carp;

sub Desc ($) {
    croak "Detect changes in median latency";
}    

sub Test($$)
{   my $self = shift;
    my $data = shift; # @{$data->{rtt}} and @{$data->{loss}}    
    my $len =  $self->Length;
    my $rlen = scalar @{$data->{rtt}};
    return undef 
	if $rlen < $len
           or (defined $data->{rtt}[-$len] and $data->{rtt}[-$len] eq 'S');
    my $ac = $self->{param}{historic};
    my $bc = $self->{param}{current};
    my $cc = $ac +$bc;
    my $hm = (sort {$a <=> $b} @{$data->{rtt}}[-$cc..-$bc-1])[int($ac/2)];
    my $cm = (sort {$a <=> $b} @{$data->{rtt}}[-$bc..-1])[int($bc/2)];
    return undef unless $hm and $cm;
    return &{$self->{param}{sub}}($cm/$hm,$self->{param}{value});
}
