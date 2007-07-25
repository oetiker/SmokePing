# -*- perl -*-
package Smokeping::Master;
use HTTP::Request;
use Data::Dumper;
use Storable qw(dclone nfreeze);
use strict;
use warnings;

=head1 NAME

Smokeping::Master - Master Functionality for Smokeping

=head1 OVERVIEW

This module handles all special functionality required by smokeping running
in master mode.

=head2 IMPLEMENTATION

=head3 slave_cfg=extract_config(cfg,slave)

Extract the relevant configuration information for the selected slave. The
configuration will only contain the information that is relevant for the
slave. Any parameters overwritten in the B<Slaves> section of the configuration
file will be patched for the slave.

=cut

sub get_targets;
sub get_targets {
    my $trg = shift;
    my $slave = shift;
    my %return;
    my $ok;
    foreach my $key (keys %{$trg}){
        # dynamic hosts can only be queried from the
        # master
        next if $key eq 'host' and $trg->{$key} eq 'DYNAMIC';
        next if $key eq 'host' and not ( defined $trg->{slaves} and $trg->{slaves} =~ /\b${slave}\b/);
        if (ref $trg->{$key} eq 'HASH'){
            $return{$key} = get_targets ($trg->{$key},$slave);
            $ok = 1 if defined $return{$key};
        } else {
            $ok = 1 if $key eq 'host';
            $return{$key} = $trg->{$key};
        }
    }    
    return ($ok ? \%return : undef);
}
    
            
        
sub extract_config {
    my $cfg = shift;
    my $slave = shift;
    # get relevant Targets
    my %slave_config;
    $slave_config{Database} = dclone $cfg->{Database}; 
    $slave_config{General}  = dclone $cfg->{General};
    $slave_config{Probes}   = dclone $cfg->{Probes};
    $slave_config{Targets}  = get_targets($cfg->{Targets},$slave);
    $slave_config{__last}   = $cfg->{__last};
    if ($cfg->{Slaves} and $cfg->{Slaves}{$slave} and $cfg->{Slaves}{$slave}{override}){
        for my $override (keys %{$cfg->{Slaves}{$slave}{override}}){
            my $node = \%slave_config;
            my @keys = split /\./, $override;
            my $last_key = pop @keys;
            for my $key (@keys){
                $node->{$key} = {}
                    unless $node->{$key} and ref $node->{$key} eq 'HASH';
                $node = $node->{$key};
            }
            $node->{$last_key} = $cfg->{Slaves}{$slave}{override}{$override};
        }
    }
    return nfreeze \%slave_config;
}

1;

__END__

=head1 COPYRIGHT

Copyright 2007 by Tobias Oetiker

=head1 LICENSE

This program is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.  See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public
License along with this program; if not, write to the Free
Software Foundation, Inc., 675 Mass Ave, Cambridge, MA
02139, USA.

=head1 AUTHOR

Tobias Oetiker E<lt>tobi@oetiker.chE<gt>

=cut
