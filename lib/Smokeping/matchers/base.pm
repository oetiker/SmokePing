package Smokeping::matchers::base;

=head1 NAME

Smokeping::matchers::base - Base Class for implementing SmokePing Matchers

=head1 OVERVIEW
 
This is the base class for writing SmokePing matchers. Every matcher must
inherit from the base class and provide it's own methods for the 'business'
logic.

Note that the actual matchers must have at least one capital letter in their
name, to differentiate them from the base class(es).

=head1 DESCRIPTION

Every matcher must provide the following methods:

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
	croak "key '$key' is not known by this matcher" unless defined $rules->{$key};	
	croak "key '$key' contains invalid data: '$self->{param}{$key}'" unless $self->{param}{$key} =~ m/^$regex$/;
    }    
    bless $self, $class;
    return $self;
}

=head2 Length

The Length method returns the number of values the
matcher will expect from SmokePing. This method must
be overridden by the children of the base class.

=cut

sub Length($)
{
    my $self = shift;
    croak "SequenceLength must be overridden by the subclass";
}

=head2 Desc

Simply return the description of the function. This method must
be overwritten by a children of the base class.

=cut


sub Desc ($) {
    croak "MatcherDesc must be overridden by the subclass";
}    

=head2 Test

Run the matcher and return true or false. The Test method is called
with a hash containing two arrays giving it access to both rtt and loss values.

  my $data=shift;
  my @rtt = @{$data->{rtt}};
  my @loss = @{$data->{loss}};

The arrays are ordered from old to new.

  @rdd[old..new]

There may be more than the expected number of elements in this array. Address them with
$x[-1] to $x[-max].

There's also a key called 'prevmatch' in the hash. It contains the
value returned by the previous call of the 'Test' method. This allows
for somewhat more intelligent alerting due to state awareness.

  my $prevmatch = $data->{prevmatch};

=cut

sub Test($$)
{   my $self = shift;
    my $data = shift; # @{$data->{rtt}} and @{$data->{loss}}
    croak "Match must be overridden by the subclass";

}

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
