package Smokeping::matchers::ExpLoss;
=head1 NAME

Smokeping::matchers::ExpLoss - exponential weighting matcher for packet loss
with RMON-like thresholds

=head1 DESCRIPTION

Match against exponential weighted average of last samples, thus new values 
are more valuable as old ones. Two thresholds - rising and falling - produce 
hysteresis loop like in RMON alert subsystem. If the average reaches the 
"rising" threshold, matcher go to the "match" state and hold It until the 
average drops under the "falling" threshold.

Call the matcher with the following sequence:

 type = matcher
 pattern =  CheckLoss(hist => <hist>, rising=><rising> \
                     [,falling => <falling>] [,skip=><stat>] [,fast=><fast>])

Arguments:
 hist    - number of samples to weight against; weight will be disposed with
           exponetial decreasing manner from newest to oldest, so that the
           oldest sample would have 1% significance;
 rising  - rising threshold for packet loss, 0-100%
 falling - falling threshold for packet loss, default is <rising>
 skip    - skip <skip> number of samples after startup before "fire" alerts.
 fast    - use <fast> samples for fast transition: if the values of last <fast>
           samples more then <rising> - take "match" state, if less then
           <falling> - take "no match" state.

Note:
 If the actual history is less then <hist> value then this value is taken 
 as the actual history.

=head1 COPYRIGHT

Copyright (c) 2008 Veniamin Konoplev

Developed in cooperation with EU EGEE project

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

Veniamin Konoplev E<lt>vkonoplev@acm.orgE<gt>

=cut

use strict;
use base qw(Smokeping::matchers::base);
use vars qw($VERSION);
$VERSION = 1.0;
use Carp;

sub new(@) {
    my $class = shift;
    my $rules = {
        hist => '\d+',
        rising => '\d+(\.\d+)?',
	falling => '\d+(\.\d+)?',
        skip => '\d+',
        fast => '\d+',
    };
    my $self = $class->SUPER::new( $rules, @_ );
    return $self;
}

# how many values should we require before raising?
sub Length($) {
    my $self = shift;
    return $self->{param}{hist};    # 
}

sub Desc ($) {
    croak "Monitor if exponential weighted loss is in interval";
}

sub Test($$) {
    my $self   = shift;
    my $data   = shift;               # @{$data->{rtt}} and @{$data->{loss}}

    my $hist = $self->{param}{hist}; # history lengh
    my $skip = ($self->{param}{skip} || 0); # skip <skip> samples before start
    my $fast = ($self->{param}{fast} || 0); # use last <fast> samples for fast alerts

    return undef if scalar(@{ $data->{loss}}) <= $skip+1;
    
    # calculate alpha factor to obtain 1% significance 
    # of the old probes at the <hist> boundary
    my $alfa = 1-0.01**(1/$hist);

    my $rising = $self->{param}{rising};
    my $falling = (defined $self->{param}{falling} || $rising);

    my $result = 0; # initialize the filter as zero;
    my $loss;
    my $sum = 0;
    my $num = 0;
    my $rising_cnt = 0;
    my $falling_cnt = 0;
    foreach $loss ( @{ $data->{loss} } ) {
        # If there's an S in the array anywhere, return prevmatch
        next if ( $loss =~ /S/ or $loss =~ /U/);
        
        # update the filter
        $result = (1-$alfa)*$result+$alfa*$loss;
        $sum += $loss;
        $num++;
        if ($fast) { 
            $rising_cnt = ($loss >= $rising) ? $rising_cnt + 1 : 0;
            $falling_cnt = ($loss <= $falling) ? $falling_cnt + 1 : 0;
        }
    }

    return undef if $num == 0;
    
    # 
    if ($fast) {
        return 1 if $rising_cnt >= $fast;
        return "" if $falling_cnt >= $fast;
    }
    # correct filter result as if it was initialized with "average"
    $result += ($sum/$num)*((1-$alfa)**$num);
    
    my $res = (($result >= $rising) or ($data->{prevmatch} and $result >= $falling));

    # some debug stuff
    if (0) {
        my $d = `date`;
        chomp $d;
        my $array = join ":", @{ $data->{loss}}; 
        `echo $d $data->{target} $array $result. >> /tmp/matcher.log` if $rising == 0;
    }
    return $res;
}

1;
