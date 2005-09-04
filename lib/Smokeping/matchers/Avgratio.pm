package Smokeping::matchers::Avgratio;

=head1 NAME

Smokeping::matchers::Avgratio - detect changes in average median latency

=head1 OVERVIEW

The Avgratio matcher establishes a historic average median latency over
several measurement rounds. It compares this average, against a second
average latency value again build over several rounds of measurement.

=head1 DESCRIPTION

Call the matcher with the following sequence:

 type = matcher
 pattern =  Avgratio(historic=>a,current=>b,comparator=>o,percentage=>p)

=over

=item historic

The number of median values to use for building the 'historic' average.

=item current

The number of median values to use for building the 'current' average.

=item comparator

Which comparison operator should be used to compare current/historic with percentage.

=item percentage

Right hand side of the comparison.

=back

  old <--- historic ---><--- current ---> now

=head1 EXAMPLE

Take build the average median latency over 10 samples, use this to divide the
current average latency built over 2 samples and check if it is bigger than
150%.

 Avgratio(historic=>10,current=>2,comparator=>'>',percentage=>150);

 avg(current)/avg(historic) > 150/100

This means the matcher will activate when the current latency average is
more than 1.5 times the historic latency average established over the last
10 rounds of measurement.

=head1 COPYRIGHT

Copyright (c) 2004 by OETIKER+PARTNER AG. All rights reserved.

=head1 SPONSORSHIP

The development of this matcher has been sponsored by Virtela Communications, L<http://www.virtela.net/>.

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
use base qw(Smokeping::matchers::base);
use Carp;

sub new(@)
{
    my $class = shift;
    my $rules = {
                historic=>'\d+',
                current=>'\d+',
                comparator=>'(<|>|<=|>=|==)',
                percentage=>'\d+(\.\d+)?' };

    my $self  = $class->SUPER::new($rules,@_);
    $self->{param}{sub} = eval "sub {\$_[0] ".$self->{param}{comparator}." \$_[1]}";
    croak "compiling comparator $self->{param}{comparator}: $@" if $@;
    $self->{param}{value} = $self->{param}{percentage}/100;
    return $self;
}

sub Length($)
{
    my $self = shift;
    return $self->{param}{historic} + $self->{param}{current};
}

sub Desc ($) {
    croak "Detect changes in average median latency";
}    

sub avg(@){
    my $sum=0;
    my $cnt=0;
    for (@_){
	next unless defined $_;
 	$sum += $_;
	$cnt ++;
    }
    return $sum/$cnt if $cnt;
    return undef;
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
    my $ha = avg(@{$data->{rtt}}[-$cc..-$bc-1]);
    my $ca = avg(@{$data->{rtt}}[-$bc..-1]);
    return undef unless $ha and $ca;
    return &{$self->{param}{sub}}($ca/$ha,$self->{param}{value});
}
