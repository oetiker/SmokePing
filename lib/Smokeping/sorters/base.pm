package Smokeping::sorters::base;

=head1 NAME

Smokeping::sorters::base - Base Class for implementing SmokePing Sorters

=head1 OVERVIEW
 
Sorters are at the core of the SmokePing Charts feature, where the most
interesting graphs are presented on a single page. The Sorter decides which
graphs are considerd interesting.

Every sorter must inherit from the base class and provide it's own
methods for the 'business' logic.

In order to maintain a decent performance the sorters activity is split into
two parts.

The first part is active while the smokeping daemon gathers its data.
Whenever data is received, the sorter is called to calculate a 'value' for
the present data. On every 'query round' this information is stored in the
sorter store directory. Each smokeping process stores it's own information.
Since smokeping can run in multiple instances at the same time, the data may
be split over several files

The second part of the sorter is called from smokeping.cgi. It loads all the
information from the sorter store and integrates it into a single 'tree'. It
then calls each sorter with the pre-calculated data to get it sorted and to
and to select the interesting information.

=head1 DESCRIPTION

Every sorter must provide the following methods:

=cut

use vars qw($VERSION);
use Carp;

$VERSION = 1.0;

use strict;

=head2 new

The new method expects hash elements as an argument
eg new({x=>'\d+',y=>'\d+'},x=>1,y=>2). The first part is
a syntax rule for the arguments it should expect and the second part
are the arguments itself. The first part will be supplied
by the child class as it calls the parent method.

=cut

sub new(@)
{
    my $this   = shift;
    my $class   = ref($this) || $this;
    my $rules = shift;
    my $self = { param => { @_ } };
    foreach my $key (keys %{$self->{param}}){
	my $regex = $rules->{$key};
	croak "key '$key' is not known by this sorter" unless defined $rules->{$key};	
	croak "key '$key' contains invalid data: '$self->{param}{$key}'" unless $self->{param}{$key} =~ m/^$regex$/;
    }
    bless $self, $class;
    return $self;
}

=head2 Desc

Simply return the description of the function. This method must
be overwritten by a children of the base class.

=cut

sub Desc ($) {
    croak "Sorter::Desc must be overridden by the subclass";
}    

=head2 SortTree

Returns an array of 'targets'. It is up to the sorter to decide how many
entries the list should contain. If the list is empty, the whole entry will
be supressed in the webfrontend. 

The methode gets access to all the targets in the system, together with the
last data set acquired for each target.

=cut

sub SortTree($$) {
    my $self = shift;
    my $target = shift @{$self->{targets}};
    my $cache = shift;
    my $entries = $self->{param}{entries} || 3;
    my $sorted = [
        map { $entries-- > 0 ? { open => [ split '/', $_ ], value => $cache->{$_} } : () }
           sort { $cache->{$b} <=> $cache->{$a} } keys %$cache ];
    return $sorted;
}

=head2 CalcValues

Figure out the curent sorting value using te following input.

 $info = { uptime => w,
  	   loss   => x,
           median => y,
    	   alert  => z, # (0/1)
           pings  => [qw(a b c d)] }

The output can have any structure you want. It will be returned to the
sorter method for further processng.

=cut

sub CalcValue($) {
    my $self = shift;
    my $info = shift;
    croak "CalcValue must be overridden by the subclass";
    return ( { any=>'structure' } );
}


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
