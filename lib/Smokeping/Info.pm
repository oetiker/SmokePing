# -*- perl -*-
package Smokeping::Info;
use warnings;
use strict;
use RRDs;
use Smokeping;
use Carp;
use Data::Dumper;

sub new {
    my $this   = shift;
    my $class   = ref($this) || $this;
    my $self = { cfg_file => shift };
    bless $self, $class;
    my $parser = Smokeping::get_parser();
    $self->{cfg_hash} = $parser->parse( $self->{cfg_file} )
        or croak "ERROR reading config file $parser->{err}";
    $self->{probe_hash} = Smokeping::load_probes $self->{cfg_hash};
    return $self;
}

# get a list of all rrd files in the config file

sub __flatten_targets;
sub __flatten_targets {
    my $probes = shift;
    my $root = shift;
    my $prefix = shift;
    my @paths;    
    for my $target ( sort {$root->{$a}{_order} <=> $root->{$b}{_order}} 
                     grep { ref $root->{$_} eq 'HASH' }  keys %$root ) {        
        push @paths,  __flatten_targets($probes,$root->{$target},$prefix.'/'.$target);
    };
    if (exists $root->{host} and not $root->{host} =~ m|/|){
        my $probe = $probes->{$root->{probe}};
        my $pings = $probe->_pings($root);
        if (not $root->{nomasterpoll} or $root->{nomasterpoll} eq 'no') {
            push @paths, { path => $prefix, pings=>$pings };
        };
        if ($root->{slaves}) {
            for my $slave (split /\s+/,$root->{slaves}){
                push @paths, { path => $prefix.'~'.$slave, pings=>$pings };
            }
        }
    };
    return @paths;
}

sub fetch_nodes {
    my $self = shift;
    my %args = ( 'mode' => 'plain', @_); # no mode  is default
    my %valid = ( pattern=>1, mode => 1 );
    my %valid_modes = ( plain=>1, recursive=>1, regexp=>1);
    map {
        croak "Invalid fetch nodes argument '$_'"
            if not $valid{$_};
    } keys %args;

    croak "Invalid fetch mode $args{mode}"
        if not $valid_modes{$args{mode}};

    my $cfg = $self->{cfg_hash};
    my @flat = __flatten_targets($self->{probe_hash},$cfg->{Targets},'');
    my $rx = qr{.*};
    if ( defined $args{pattern} ) {
        if ( $args{mode} eq 'recursive' ) {
            $rx  = qr{^\Q$args{pattern}\E};
        }
        elsif ( $args{mode} eq 'regexp' ) {
            $rx  = qr{$args{pattern}};
        }
        else {
            $rx  = qr{^\Q$args{pattern}\E[^/]*$};
        }
    }
    return [ grep { $_->{path} =~ /${rx}/ } @flat ];
}


sub stat_node {
    my $self = shift;
    my $path = shift;
    my $start = shift;
    my $end = shift;
    my $cfg = $self->{cfg_hash};
    my ($graphret,$xs,$ys) = RRDs::graph (
      '/tmp/dummy',
      '--start'=>$start,
      '--end'=>$end,
      'DEF:loss_avg_r='.$cfg->{General}{datadir}.$path->{path}.'.rrd:loss:AVERAGE',
      'CDEF:loss_avg=loss_avg_r,'.$path->{pings}.',/',
      'VDEF:loss_avg_tot=loss_avg,AVERAGE',
      'PRINT:loss_avg_tot:%.8le',
      'DEF:loss_max_r='.$cfg->{General}{datadir}.$path->{path}.'.rrd:loss:MAX',
      'CDEF:loss_max=loss_max_r,'.$path->{pings}.',/',
      'VDEF:loss_max_tot=loss_max,MAXIMUM',
      'PRINT:loss_max_tot:%.8le',
      'VDEF:loss_now=loss_avg,LAST',
      'PRINT:loss_now:%.8le',
      'DEF:median_avg='.$cfg->{General}{datadir}.$path->{path}.'.rrd:median:AVERAGE',
      'VDEF:median_avg_tot=median_avg,AVERAGE',
      'PRINT:median_avg_tot:%.8le',
      'DEF:median_min='.$cfg->{General}{datadir}.$path->{path}.'.rrd:median:MIN',
      'VDEF:median_min_tot=median_min,MINIMUM',
      'PRINT:median_min_tot:%.8le',
      'DEF:median_max='.$cfg->{General}{datadir}.$path->{path}.'.rrd:median:MAX',
      'VDEF:median_max_tot=median_max,MAXIMUM',
      'PRINT:median_max_tot:%.8le',
      'VDEF:median_now=median_avg,LAST',
      'PRINT:median_now:%.8le'
    );
    my %data;
    if (my $ERROR = RRDs::error()){
    	carp "$path->{path}: $ERROR";
    } else {
        @data{qw(loss_avg loss_max loss_now med_avg med_min med_max med_now)} = @$graphret;
    }
    return \%data;
};
1;

__END__

=head1 NAME

Smokeping::Info - Pull numerical info out of the rrd databases

=head1 OVERVIEW

This module provides methods to further process information contained in
smokeping rrd files. The smokeinfo tool is a simple wrapper around the
functionality containd in here.

 my $si = Smokeping::Info->new("config/file/path");

 my $array_ref = $si->fetch_nodes(pattern=>'/node/path',
                                  mode=>'recursive');

 my $hash_ref = $si->stat_node(path,start,end);

=head1 IMPLEMENTATION

=head2 new(path)

Create a new Smokeping::Info instance. Instantiating Smokeping::Info entails
reading the configuration file. This is a compte heavy procedure. So you may
want to use a single info object to handle multiple requests.

=head2 fetch_nodes(pattern=>'/...',mode=>{recursive|regexp})

The fetch_nodes method will find all nodes sitting in the given pattern
(absolute path) including the path itself. By setting the recursive mode,
all rrd files in paths below will be returned as well. In regexp mode, all
rrd paths matching the given expression will be returned.

=head2 stat_node(node,start,end)

Return a hash pointer to statistics based on the data stored in the given
rrd path.

 med_avg - average median
 med_min - minimal median
 med_max - maximal median
 med_now - current median
 loss_avg - average loss
 loss_max - maximum loss
 loss_now - current loss

=head1 COPYRIGHT

Copyright 2009 by OETIKER+PARTNER AG

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 675 Mass
Ave, Cambridge, MA 02139, USA.

=head1 AUTHOR

Tobias Oetiker E<lt>tobi@oetiker.chE<gt>, development sponsored by Swisscom Hospitality 

=cut

# Emacs Configuration
#
# Local Variables:
# mode: cperl
# eval: (cperl-set-style "PerlStyle")
# mode: flyspell
# mode: flyspell-prog
# End:
#
# vi: sw=4
