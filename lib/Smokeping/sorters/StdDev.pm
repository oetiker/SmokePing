package Smokeping::sorters::StdDev;

=head1 NAME

Smokeping::sorters::StdDev - Order the target charts by StdDev

=head1 OVERVIEW

Find the charts with the highest standard deviation among the Pings sent to
a single target. The more smoke - higher the standard deviation.

=head1 DESCRIPTION

Call the sorter in the charts section of the config file

 + charts
  menu = Charts
  title = The most interesting destinations

 ++ stddev
  sorter = StdDev(entries=>4)
  title = Top StdDev
  menu = Std Deviation
  format = Standard Deviation %f

=head1 COPYRIGHT

Copyright (c) 2007 by OETIKER+PARTNER AG. All rights reserved.

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
use base qw(Smokeping::sorters::base);
use vars qw($VERSION);
$VERSION = 1.0;
use Carp;

# how many values does the matcher need to do it's magic

sub new(@) {
    my $class = shift;
    my $rules = {
        entries => '\d+'
    };
    my $self = $class->SUPER::new( $rules, @_ );
    return $self;
}

sub Desc ($) {
    return "The Standard Deviation sorter sorts the targets by Standard Deviation.";
}    

sub CalcValue($) {
    my $self = shift;
    my $info = shift;
    # $info = { uptime => w,
    #           loss   => x,
    #           median => y,
    #           alert  => z, (0/1)
    #           pings  => [qw(a b c d)]
    #
    my $avg = 0;
    my $cnt = 0;
    my @values = grep { defined $_ } @{$info->{pings}};
    for (@values){ $avg += $_; $cnt++};
    return -1 if $cnt == 0;
    $avg = $avg / $cnt;
    my $dev = 0;
    for (@values){ $dev += ($_ - $avg)**2};
    $dev = sqrt($dev / $cnt);
    return $dev;
}
