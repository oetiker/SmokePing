package Smokeping::matchers::ConsecutiveLoss;

=head1 NAME

Smokeping::matchers::ConsecutiveLoss - Raise/clear alerts according to your choice of threshold and consecutive values

=head1 DESCRIPTION

Use this matcher to raise and clear alerts according to your choice of threshold and consecutive values.
As an example, you can raise an alert on first occurrence of 50% packet loss, but choose to hold the alert
active until packet loss stays below 10% for 5 consecutive measurements.

Add the matcher to your config file using below syntax:

 type = matcher
 edgetrigger = yes
 pattern =  ConsecutiveLoss(pctlossraise=>##,stepsraise=>##,pctlossclear=>##,stepsclear=>##)

Replace the ## with integers of your choice, see below for reference:

pctlossraise - Loss values at or above this percentage will raise an alert when...
stepsraise - ... number of consecutive values have been collected

pctlossclear - Loss values below this percentage will clear an alert when...
stepsclear - ... number of consecutive values have been collected

In my environment, I define four alerts for levels like:

 +packetloss_significant_instantalert
 type = matcher
 pattern = ConsecutiveLoss(pctlossraise=>10,stepsraise=>1,pctlossclear=>3,stepsclear=>3)
 comment = Instant alert - Significant packet loss detected (At least 10% over 1 cycle). Alert will clear when loss stays at max 2% for 3 cycles
 priority = 30

 +packetloss_major_instantalert
 type = matcher
 pattern = ConsecutiveLoss(pctlossraise=>25,stepsraise=>1,pctlossclear=>3,stepsclear=>3)
 comment = Instant alert - Major packet loss detected (At least 25% over 1 cycle). Alert will clear when loss stays at max 2% for 3 cycles
 priority = 20

 +packetloss_significant_consecutivealert
 type = matcher
 pattern = ConsecutiveLoss(pctlossraise=>10,stepsraise=>3,pctlossclear=>3,stepsclear=>5)
 comment = Consecutive occurrence of significant packet loss detected (At least 10% over 3 cycles). Alert will clear when loss stays at max 2% for 5 cycles.
 priority = 10

 +packetloss_major_consecutivealert
 type = matcher
 pattern = ConsecutiveLoss(pctlossraise=>25,stepsraise=>3,pctlossclear=>3,stepsclear=>5)
 comment = Consecutive occurrence of significant packet loss detected (At least 25% over 3 cycles). Alert will clear when loss stays at max 2% for 5 cycles.
 priority = 5



=head1 COPYRIGHT

Copyright (c) 2017 Rickard Borgmaster

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

Rickard Borgmaster. 2017.
Based on the CheckLoss/Checklatency matchers by Dylan Vanderhoof 2006.

=cut

use strict;
use base qw(Smokeping::matchers::base);
use vars qw($VERSION);
$VERSION = 1.0;
use Carp;
use List::Util qw(min max);

# I never checked why Median works, but for some reason the first part of the hash was being passed as the rules instead
sub new(@) {
    my $class = shift;
    my $rules = {
        pctlossraise => '\d+',
        stepsraise => '\d+',
        pctlossclear => '\d+',
        stepsclear => '\d+'
    };
    my $self = $class->SUPER::new( $rules, @_ );
    return $self;
}

# how many values should we require before raising?
sub Length($) {
    my $self = shift;
    return max($self->{param}{stepsraise},$self->{param}{stepsclear});    # Minimum number of samples required is the greater of stepsraise/stepsclear
}

sub Desc ($) {
    croak "Monitor loss with a cooldown period for clearing the alert";
}

sub Test($$) {
    my $self   = shift;
    my $data   = shift;               # @{$data->{rtt}} and @{$data->{loss}}
    my $count  = 0;
    my $loss;
    my $x;
    my $debug  = 0; # 0 will suppress debug messages

    if ($debug) { print "------------------------------------------------------------------------------------------\n"; }


    # Determine number of iterations for the for-loop. if we at all have enough values yet.
    if ( $data->{prevmatch} ) {
        # Alert state true
        if (scalar @{ $data->{loss} } < $self->{param}{stepsclear})  { return $data->{prevmatch}; } # Cannot consider $stepsclear values unless so many values actually exist in array
        $x = $self->{param}{stepsclear};
    } else {
        # Alert state false
        if (scalar @{ $data->{loss} } < $self->{param}{stepsraise})  { return $data->{prevmatch}; } # Cannot consider $stepsraise values unless so many values actually exist in array
        $x = $self->{param}{stepsraise};
    }

    if ($debug) { print "Will evaluate $x values because previous alert state= $data->{prevmatch}\n"; }


    ## Start iterating thru the array
    for (my $i=1;$i<=$x;$i++) {
        $loss = $data->{loss}[$_-$i];

        # If there's an S in the array anywhere, return prevmatch. We do not have enough values yet.
        if ( $loss =~ /S/ ) { return $data->{prevmatch}; }

        if ( $data->{prevmatch} ) {
            
            # Alert has already been raised.  Evaluate and count consecutive loss values that are below threshold.
            if ( $loss < $self->{param}{pctlossclear} ) { $count++; }
        } else {
            
            # Alert is not raised.  Evaluate and count consecutive loss values that are above threshold.
            if ( $loss >= $self->{param}{pctlossraise} ) { $count++; }
        }
        if ($debug) { print "i: $i x: $x count: $count loss: $loss previous alarm state: $data->{prevmatch}\n"; }
    }

    if ( $count >= $x ) { return !$data->{prevmatch} };
    return $data->{prevmatch};
}
