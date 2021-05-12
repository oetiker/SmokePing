# -*- perl -*-
package Smokeping::Slave;
use warnings;
use strict;
use Data::Dumper;
use Storable qw(nstore retrieve);
use Digest::HMAC_MD5 qw(hmac_md5_hex);
use LWP::UserAgent;
use Safe;
use Smokeping;
# keep this in sync with the Slave.pm part
# only update if you have to force a parallel upgrade
my $PROTOCOL = "2";

=head1 NAME

Smokeping::Slave - Slave functionality for Smokeping

=head1 OVERVIEW

The Module implements the functionality required to run in slave mode.

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
    return [] unless $cfg;
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
            push @$results, "$name\t".time()."\t$updatestring";
        }
    }
    return $results;
}
         
sub submit_results {    
    my $slave_cfg = shift;
    my $cfg = shift;
    my $myprobe = shift;
    my $probes = shift;
    my $store = $slave_cfg->{cache_dir}."/data";
    $store .= "_$myprobe" if $myprobe;
    $store .= ".cache";
    my $restore = -f $store ? retrieve $store : []; 
    unlink $store;
    my $new =  get_results($slave_cfg, $cfg, $probes, $cfg->{Targets}, '', $myprobe);    
    push @$restore, @$new;
    my $data_dump = join("\n",@{$restore}) || "";
    my $ua = LWP::UserAgent->new(
        agent => 'smokeping-slave/1.0',
        timeout => 300,
        env_proxy => 1 );

    my $response = $ua->post(
        $slave_cfg->{master_url},
        Content_Type => 'form-data',
        Content => [
            slave => $slave_cfg->{slave_name},
            key  => hmac_md5_hex($data_dump,$slave_cfg->{shared_secret}),
            protocol => $PROTOCOL,
            data => $data_dump,
            config_time => $cfg->{__last} || 0,
        ],
    );
    if ($response->is_success){
        my $data = $response->content;
        my $key = $response->header('Key');
        my $protocol = $response->header('Protocol') || '?';

        if ($response->header('Content-Type') ne 'application/smokeping-config'){
            warn "$data\n" unless $data =~ /OK/;
            Smokeping::do_debuglog("Sent data to Server. Server said $data");
            return undef;
        };

        if ($protocol ne $PROTOCOL){
            warn "WARNING $slave_cfg->{master_url} sent data with protocol $protocol. Expected $PROTOCOL.";
            return undef;
        }
        if (hmac_md5_hex($data,$slave_cfg->{shared_secret}) ne $key){
            warn "WARNING $slave_cfg->{master_url} sent data with wrong key";
            return undef;
        }
        # Safe seems to reset SIG on at least FreeBSD, causing slave to crash after first reload
        # since all handlers are gone.
        my %sig_backup = %SIG;

        my $zone = new Safe;
        # $zone->permit_only(???); #input welcome as to good settings
        my $config = $zone->reval($data);

        %SIG = %sig_backup;

        if ($@){
            warn "WARNING evaluating new config from server failed: $@ --\n$data";
        } elsif (defined $config and ref $config eq 'HASH'){
            $config->{General}{piddir} = $slave_cfg->{pid_dir};
            Smokeping::do_log("Sent data to Server and got new config in response.");
            return $config;
        }                       
    } else {
        # ok did not manage to get our data to the server.
        # we store the result so that we can try again later.
        warn "WARNING Master said ".$response->status_line()."\n";
        nstore $restore, $store;
    }
    return undef;
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
