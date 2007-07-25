# -*- perl -*-
package Smokeping::Slave;
use warnings;
use strict;
use Data::Dumper;
use Storable qw(nstore retreive);
use Digest::MD5 qw(md5_ base64);
use LWP::UserAgent;
use Smokeping;


=head1 NAME

Smokeping::Slave - Slave functionality for Smokeping

=head1 OVERVIEW

The Module inmplements the functionality required to run in slave mode.

=head2 IMPLEMENTATION

=head3 submit_results

In slave mode we just hit our targets and submit the results to the server.
If we can not get to the server, we submit the results in the next round.
The server in turn sends us new config information if it sees that ours is
out of date.

=cut

sub get_results;
sub get_results {
    my $slave_cfg = shift;
    my $cfg = shift;
    my $probes = shift;
    my $tree = shift;
    my $name = shift;
    my $justthisprobe = shift; # if defined, update only the targets probed by this probe
    my $probe = $tree->{probe};
    my $results = [];
    foreach my $prop (keys %{$tree}) {
        if (ref $tree->{$prop} eq 'HASH'){
            my $subres = get_results $slave_cfg, $cfg, $probes, $tree->{$prop}, $name."/$prop", $justthisprobe;
            push @{$results}, @{$subres};
        } 
        next unless defined $probe;
        next if defined $justthisprobe and $probe ne $justthisprobe;
        my $probeobj = $probes->{$probe};
        if ($prop eq 'host') {
            #print "update $name\n";
            my $updatestring = $probeobj->rrdupdate_string($tree);
            my $pings = $probeobj->_pings($tree);
            push @$results, [ $name, time, $updatestring];
        }
    }
    return $results;
}
         
sub submit_results {    
    my $slave_cfg = shift;
    my $cfg = shift;
    my $myprobe = shift;
    my $store = $slave_cfg->{cache_dir}."/data";
    $store .= "_$myprobe" if $myprobe;
    $store .= ".cache";
    my $restore = retrieve $store if -f $store; 
    my $data =  get_results($slave_cfg, $cfg, $probes, $cfg->{Targets}, $cfg->{General}{datadir}, $myprobe);    
    push @$data, @$restore;    
    my $data_dump = Dumper $data;
    my $ua = LWP::UserAgent->new(
        agent => 'smokeping-slave/1.0',
        from => $slave_cfg->{slave_name},
        timeout => 10,
        env_proxy => 1 );
    my $response = $ua->post(
        $slave_cfg->{master_url},
        Content_Type => 'form-data',
        Content => [
            key  => md5_base_64($slave_cfg->{shared_secret}.$data_dump) 
            data => $data_dump,
            config_time => $cfg->{__last} || 0;
        ],
    );
    if ($response->is_success){
        my $data = $response->decoded_content;
        my $key = $response->header('Key');
        if (md5_base_64($slave_cfg->{shared_secret}.$data) ne $key){
            warn "Warning: $slave_cfg->{master_url} sent data with wrong key";
            return undef;
        }
        my $VAR1;
        eval $data;
        if (ref $VAR1 eq 'HASH'){
            update_config $cfg,$VAR1;
        }                       
    } else {
        # ok we have to store the result so that we can try again later
        nstore $store;
        warn $response->status_line();
    }
    return undef;
}

=head3 update_config 

Update the config information based on the latest input form the server.

=cut

sub update_config {
    my $cfg = shift;
    my $data = shift;
    $cfg->{General} = $data->{General};
    $cfg->{Probes} = $data->{Probes};
    $cfg->{Database} = $data->{Database};
    $cfg->{Targets} = $data->{Targets};
    $cfg->{__last} = $data->{__last};
    $Smokeping::probes = Smokeping::load_probes $cfg;
    $cfg->{__probes} = $probes;
    add_targets $cfg, $probes, $cfg->{Targets}, $cfg->{General}{datadir};
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
