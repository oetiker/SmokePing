# -*- perl -*-
package Smokeping::Master;
use HTTP::Request;
use Data::Dumper;
use Storable qw(lock_nstore dclone lock_retrieve);
use strict;
use warnings;
use Fcntl qw(:flock);

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
    return Dumper \%slave_config;
}

=head3 save_updates (updates)

When the cgi gets updates from a client, these updates are saved away, for
each 'target' so that the updates can be integrated into the relevant rrd
database by the rrd daemon as the next round of updates is processed. This
two stage process is chosen so that all results flow through the same code
path in the daemon.

=cut

sub save_updates {
    my $cfg = shift;
    my $slave = shift;
    my $updates = shift;
    # [ [ name, time, updatestring ],
    #   [ name, time, updatestring ] ]
    for my $update (split /\n/, $updates){
        my ($name, $time, $updatestring) = split /\t/, $update;
        my $file = $cfg->{General}{datadir}."/${name}.slave_cache";
        if ( ! -f $cfg->{General}{datadir}."/${name}.rrd" ){
            warn "Skipping update for $name since it does not exist in the local data structure ($cfg->{General}{datadir})\n";
        } elsif ( open (my $hand, '+>>', $file) ) {
            if ( flock $hand, LOCK_EX ){
                my $existing;
                if ( tell $hand > 0 ){
                   eval { $existing = fd_retreive  $hand };
                    if ($@) { #error
                        warn "Loading $file: $@";
                        $existing = [];
                    }
                };
                push @{$existing}, [ $slave, $time, $updatestring];
                nstore_fd ($existing, $hand);
                flock $hand, LOCK_UN;
            } else {
                warn "Could not lock $file. Can't store data.\n";
            }
            close $hand;
        } else {
            warn "Could not update $file: $!";
        }
    }            
};

=head3 get_slaveupdates

Read in all updates provided by slaves and return an array reference.

=cut

sub get_slaveupdates {
    my $name = shift;
    my $file = $name.".slave_cache";
    my $data;
    if ( open (my $hand, '<', $file) ) {
        if ( flock $hand, LOCK_EX ){
            eval { $data = fd_retreive  $hand };
            if ($@) { #error
                warn "Loading $file: $@";  
                return;
            }
            unlink $file;
            flock $hand, LOCK_UN;
        } else {
            warn "Could not lock $file. Can't load data.\n";
        }
        close $hand;
        return $data;
    }
    return;
}


=head3 get_secret

Read the secrtes file and figure the secret for the slave which is talking to us.

=cut

sub get_secret {
    my $cfg = shift;
    my $slave = shift;
    if (open my $hand, "<", $cfg->{Slaves}{secrets}){
        while (<$hand>){
            next unless /^${slave}:(\S+)/;
            close $hand;
            return $1;
        }
    } 
    warn "WARNING: Opening $cfg->{Slaves}{secrets}: $!\n";    
    return;
}

=head3 answer_slave

Answer the requests from the slave by accepting the data, verifying the secrets
and providing updated config information if necessary.

=cut

sub anwer_slave {
    my $cfg = shift;
    my $q = shift;
    my $slave = $q->param('slave');
    my $secret = get_secret($cfg,$slave);
    if (not $secret){
        warn "WARNING: No secret found for slave ${slave}\n";       
        return;
    }
    my $key = $q->param('key');
    my $data = $q->param('data');
    my $config_time = $q->param('config_time');
    if (not ref $cfg->{Slaves}{$slave} eq 'HASH'){
        warn "WARNING: I don't know the slave ${slave} ignoring it";
        return;
    }
    # lets make sure the she share a secret
    if (md5_base64($secret.$data) eq $key){
        save_updates $cfg, $slave, $data;
    } else {
        warn "WARNING: Data from $slave was signed with $key which does not match our expectation\n";
        return;
    }     
    # does the client need new config ?
    if ($config_time < $cfg->{__last}){
        print extract_config $cfg, $slave;
    } else {
        print "\n"
    };       
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
