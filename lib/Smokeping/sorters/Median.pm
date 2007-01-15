package Smokeping::sorters::Median;

=head1 NAME

Smokeping::sorters::Median - Order the target charts by Median RTT

=head1 OVERVIEW

Find the charts with the highest Median round trip time.

=head1 DESCRIPTION

Call the sorter in the charts section of the config file

 + charts
  menu = Charts
  title = The most interesting destinations

 ++ median
  sorter = Median(entries=>10)
  title = Top Median round trip time
  menu = Median RTT
  format = Median round trip time %f seconds


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
    return "The Median sorter sorts the targets by Median RTT.";
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
    return $info->{median} ? $info->{median} : -1;
}
