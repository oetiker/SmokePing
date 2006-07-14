package Smokeping::matchers::CheckLatency;

=head1 NAME

Smokeping::matchers::CheckLatency - Edge triggered alert to check latency is under a value for x number of samples

=head1 DESCRIPTION

Call the matcher with the following sequence:

 type = matcher
 edgetrigger = yes
 pattern =  CheckLatency(l=>latency to check against,x=>num samples required for a match)

This will create a matcher which checks for "l" latency or greater over "x" samples before raising, 
and will hold the alert until "x" samples under "l" before clearing

=head1 COPYRIGHT

Copyright (c) 2006 Dylan C Vanderhoof, Semaphore Corporation

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

Dylan Vanderhoof <dylanv@semaphore.com>

=cut

use strict;
use base qw(Smokeping::matchers::base);
use vars qw($VERSION);
$VERSION = 1.0;
use Carp;

# I never checked why Median works, but for some reason the first part of the hash was being passed as the rules instead
sub new(@) {
    my $class = shift;
    my $rules = {
        l => '\d+',
        x => '\d+'
    };
    my $self = $class->SUPER::new( $rules, @_ );
    return $self;
}

# how many values should we require before raising?
sub Length($) {
    my $self = shift;
    return $self->{param}{x};    # Because we're edge triggered, we don't need any more than the required samples
}

sub Desc ($) {
    croak "Monitor latency with a cooldown period for clearing the alert";
}

sub Test($$) {
    my $self   = shift;
    my $data   = shift;                       # @{$data->{rtt}} and @{$data->{loss}}
    my $target = $self->{param}{l} / 1000;    # Smokeping reports in seconds
    my $count  = 0;
    my $rtt;
    my @rtts = @{ $data->{rtt} };
    foreach $rtt ( @{ $data->{rtt} } ) {

        # If there's an S in the array anywhere, return prevmatch
        if ( $rtt =~ /S/ ) { return $data->{prevmatch}; }
        if ( $data->{prevmatch} ) {

            # Alert has already been raised.  Check to make sure ALL latencies in RTT are less than the target
            if ( $rtt < $target ) { $count++; }
        } else {

            # Alert is not raised.  If all values are over the alert threshold OR unreachable, raise the alert
            if ( $rtt >= $target ) { $count++; }
        }
    }
    if ( $count >= $self->{param}{x} ) {
        return !$data->{prevmatch};
    }

    return $data->{prevmatch};
}
