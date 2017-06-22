# -*- perl -*-
package Smokeping::Graphs;
use strict;
use Smokeping;

=head1 NAME

Smokeping::Graphs - Functions used in Smokeping for creating graphs

=head1 OVERVIEW

This module currently only contains the code for generating the 'multi target' graphs.
Code for the other graphs will be moved here too in time.

=head2 IMPLEMENTATION

=head3 get_multi_detail

A version of get_detail for multi host graphs where there is data from
multiple targets shown in one graph. The look of the graph is modeld after
the graphs shown in the overview page, except for the size.

=cut

sub get_colors ($){
    my $cfg = shift;

    if ($cfg->{Presentation}{graphborders} eq 'no') {
        return '--border', '0',
                '--color', 'BACK#ffffff00',
                '--color', 'CANVAS#ffffff00';
    }

    # Use rrdtool defaults
    return;
}

sub get_multi_detail ($$$$;$){
    # a) 's' classic with several static graphs on the page
    # b) 'n' navigator mode with one graph. below the graph one can specify the end time
    #        and the length of the graph.
    # c) 'a' ajax mode, generate image based on given url and dump in on stdout
    #
    my $cfg = shift;
    my $q = shift;
    my $tree = shift;
    my $open = shift;
    my $mode = shift || $q->param('displaymode') || 's';
    my $phys_open = $open;
    if ($tree->{__tree_link}){
        $tree=$tree->{__tree_link};
        $phys_open = $tree->{__real_path};
    }
    
    my @dirs = @{$phys_open};

    return "<div>ERROR: ".(join ".", @dirs)." has no probe defined</div>"
        unless $tree->{probe};

    return "<div>ERROR: ".(join ".", @dirs)." $tree->{probe} is not known</div>"
        unless $cfg->{__probes}{$tree->{probe}};

    return "<div>ERROR: ".(join ".", @dirs)." ist no multi host</div>"
        unless $tree->{host} =~ m|^/|;

    return "<div>ERROR: unknown displaymode $mode</div>"
      unless $mode =~ /^[snca]$/;

    my $dir = "";

    for (@dirs) {
        $dir .= "/$_";
        mkdir $cfg->{General}{imgcache}.$dir, 0755 
                unless -d  $cfg->{General}{imgcache}.$dir;
        die "ERROR: creating  $cfg->{General}{imgcache}$dir: $!\n"
                unless -d  $cfg->{General}{imgcache}.$dir;
        
    }

    my $page;
    my $file = pop @dirs;

    my @hosts = split /\s+/, $tree->{host};
    

    
    my $ProbeDesc;
    my $ProbeUnit;


    my $imgbase;
    my $imghref;
    my @tasks;
    my %lastheight;     
    my $max = {};

    if ($mode eq 's'){
        # in nav mode there is only one graph, so the height calculation
        # is not necessary.     
        $imgbase = $cfg->{General}{imgcache}."/".(join "/", @dirs)."/${file}";
        $imghref = $cfg->{General}{imgurl}."/".(join "/", @dirs)."/${file}";    
        @tasks = @{$cfg->{Presentation}{detail}{_table}};
        if (open (HG,"<${imgbase}.maxheight")){
            while (<HG>){
                chomp;
                my @l = split / /;
                $lastheight{$l[0]} = $l[1];
            }
            close HG;
        }
        for my $rrd (@hosts){            
             my $newmax = Smokeping::findmax($cfg, $cfg->{General}{datadir}.$rrd.".rrd");             
             map {$max->{$_} = $newmax->{$_} if not $max->{$_} or $newmax->{$_} > $max->{$_} } keys %{$newmax};
        }
        if (open (HG,">${imgbase}.maxheight")){
             foreach my $size (keys %{$max}){
                 print HG "$size $max->{$size}\n";        
             }
             close HG;
        }
    } 
    elsif ($mode eq 'n' or $mode eq 'a') {

        if ($mode eq 'n') {
            $imgbase =$cfg->{General}{imgcache}."/__navcache/".time()."$$";
            $imghref =$cfg->{General}{imgurl}."/__navcache/".time()."$$";
        } else {
            my $serial = int(rand(2000));
            $imgbase =$cfg->{General}{imgcache}."/__navcache/".$serial;
            $imghref =$cfg->{General}{imgurl}."/__navcache/".$serial;
        }
        mkdir $cfg->{General}{imgcache}."/__navcache",0755  unless -d  $cfg->{General}{imgcache}."/__navcache";
        # remove old images after one hour
        my $pattern = $cfg->{General}{imgcache}."/__navcache/*.png";
        for (glob $pattern){
                unlink $_ if time - (stat $_)[9] > 3600;
        }

        @tasks = (["Navigator Graph", Smokeping::parse_datetime($q->param('start')),Smokeping::parse_datetime($q->param('end'))]);
    } else  { 
        # chart mode 
        mkdir $cfg->{General}{imgcache}."/__chartscache",0755  unless -d  $cfg->{General}{imgcache}."/__chartscache";
        # remove old images after one hour
        my $pattern = $cfg->{General}{imgcache}."/__chartscache/*.png";
        for (glob $pattern){
                unlink $_ if time - (stat $_)[9] > 3600;
        }
        my $desc = join "/",@{$open};
        @tasks = ([$desc , time()-3600, time()]);
        $imgbase = $cfg->{General}{imgcache}."/__chartscache/".(join ".", @dirs).".${file}";
        $imghref = $cfg->{General}{imgurl}."/__chartscache/".(join ".", @dirs).".${file}";
    }
    if ($mode =~ /[anc]/){
        my $val = 0;
        for my $host (@hosts){
            my ($graphret,$xs,$ys) = RRDs::graph
            ("dummy", 
            '--start', $tasks[0][1],
            '--end', $tasks[0][2],
            "DEF:maxping=$cfg->{General}{datadir}${host}.rrd:median:AVERAGE",
            'PRINT:maxping:MAX:%le' );
            my $ERROR = RRDs::error();
            return "<div>RRDtool did not understand your input: $ERROR.</div>" if $ERROR;
            $val = $graphret->[0] if $val < $graphret->[0];
        }
        $val = 1e-6 if $val =~ /nan/i;          
        $max = { $tasks[0][1] => $val * 1.5 };
    }

    for (@tasks) {
        my ($desc,$start,$end) = @{$_};
        my $xs;
        my $ys;
        my $sigtime = ($end and $end =~ /^\d+$/) ? $end : time;
        my $date = $cfg->{Presentation}{detail}{strftime} ? 
                   POSIX::strftime($cfg->{Presentation}{detail}{strftime}, localtime($sigtime)) : scalar localtime($sigtime);
        if ( $RRDs::VERSION >= 1.199908 ){
            $date =~ s|:|\\:|g;
        }
        $end ||= 'last';
        $start = Smokeping::exp2seconds($start) if $mode =~ /[s]/; 

        my $startstr = $start =~ /^\d+$/ ? POSIX::strftime("%Y-%m-%d %H:%M",localtime($mode eq 'n' ? $start : time-$start)) : $start;
        my $endstr   = $end =~ /^\d+$/ ? POSIX::strftime("%Y-%m-%d %H:%M",localtime($mode eq 'n' ? $end : time)) : $end;

        my $realstart = ( $mode =~ /[sc]/ ? '-'.$start : $start);

        my @G;
        my @colors = split /\s+/, $cfg->{Presentation}{multihost}{colors};        
        my $i = 0;
        for my $host (@hosts){
            $i++;
            my $swidth = $max->{$start} / $cfg->{Presentation}{detail}{height};
            my $rrd = $cfg->{General}{datadir}.$host.".rrd";
            next unless -r $rrd; # skip things that do not exist;
            my $medc = shift @colors;
            my @tree_path = split /\//,$host;
            shift @tree_path;
            my ($host,$real_slave) = split /~/, $tree_path[-1]; #/
            $tree_path[-1] = $host;
            my $tree = Smokeping::get_tree($cfg,\@tree_path);
            my $label = $tree->{menu};
            if ($real_slave){
                $label .= "<".  $cfg->{Slaves}{$real_slave}{display_name};
            }

            my $probe = $cfg->{__probes}{$tree->{probe}};
            my $XProbeDesc = $probe->ProbeDesc();
            if (not $ProbeDesc or $ProbeDesc eq $XProbeDesc){
                $ProbeDesc = $XProbeDesc;
            }
            else {
                $ProbeDesc = "various probes";
            }
            my $XProbeUnit = $probe->ProbeUnit(); 
            if (not $ProbeUnit or $ProbeUnit eq $XProbeUnit){
                $ProbeUnit = $XProbeUnit;
            }
            else {
                $ProbeUnit = "various units";
            }

            my $pings = $probe->_pings($tree);

            $label = sprintf("%-20s",$label);
            push @colors, $medc;
            my $sdc = $medc;
            my $stddev = Smokeping::RRDhelpers::get_stddev($rrd,'median','AVERAGE',$realstart,$sigtime) || 0;
            $sdc =~ s/^(......).*/${1}30/;
            push @G,
                "DEF:median$i=${rrd}:median:AVERAGE",
                "DEF:loss$i=${rrd}:loss:AVERAGE",
                "CDEF:ploss$i=loss$i,$pings,/,100,*",
                "CDEF:dm$i=median$i,0,".$max->{$start}.",LIMIT",
                Smokeping::calc_stddev($rrd,$i,$pings),
                "CDEF:dmlow$i=dm$i,sdev$i,2,/,-",
                "CDEF:s2d$i=sdev$i",
#               "CDEF:dm2=median,1.5,*,0,$max,LIMIT",
#               "LINE1:dm2", # this is for kicking things down a bit
                "AREA:dmlow$i",
                "AREA:s2d${i}#${sdc}::STACK",
                "LINE1:dm$i#${medc}:${label}",
                "VDEF:avmed$i=median$i,AVERAGE",
                "VDEF:avsd$i=sdev$i,AVERAGE",
                "CDEF:msr$i=median$i,POP,avmed$i,avsd$i,/",
                "VDEF:avmsr$i=msr$i,AVERAGE",
                "GPRINT:avmed$i:%5.1lf %ss av md ",
                "GPRINT:ploss$i:AVERAGE:%5.1lf %% av ls",
                sprintf('COMMENT:%5.1lf ms sd',$stddev*1000.0),
                "GPRINT:avmsr$i:%5.1lf %s am/as\\l";
             
        };
        my @task;
        push @task, "--logarithmic" if  $cfg->{Presentation}{detail}{logarithmic} and
            $cfg->{Presentation}{detail}{logarithmic} eq 'yes';
        push @task, '--lazy' if $mode eq 's' and $lastheight{$start} == $max->{$start};

        push @task,
               "${imgbase}_${end}_${start}.png",
               '--start',$realstart,
               ($end ne 'last' ? ('--end',$end) : ()),
               '--height',$cfg->{Presentation}{detail}{height},
               '--width',$cfg->{Presentation}{detail}{width},
               '--title',$cfg->{Presentation}{htmltitle} ne 'yes' ? $desc : '',
               '--rigid','--upper-limit', $max->{$start},
               '--lower-limit',($cfg->{Presentation}{detail}{logarithmic} ? ($max->{$start} > 0.01) ? '0.001' : '0.0001' : '0'),
               '--vertical-label',$ProbeUnit,
               '--imgformat','PNG',
               Smokeping::Graphs::get_colors($cfg),
                @G,
               "COMMENT:$ProbeDesc",
               'COMMENT:end\: '.$date.'\j';

        my $graphret;
        ($graphret,$xs,$ys) = RRDs::graph @task;
        #  print "<div>INFO:".join("<br/>",@task)."</div>";
        my $ERROR = RRDs::error();
        if ($ERROR) {
            return "<div>ERROR: $ERROR</div><div>".join("<br/>",@task)."</div>";
        };
        

        if ($mode eq 'a'){ # ajax mode
             open my $img, "${imgbase}_${end}_${start}.png";
             binmode $img;
             print "Content-Type: image/png\n";
             my $data;
             read($img,$data,(stat($img))[7]);
             close $img;
             print "Content-Length: ".length($data)."\n\n";
             print $data;
             unlink "${imgbase}_${end}_${start}.png";
             return undef;
        } 

        elsif ($mode eq 'n'){ # navigator mode
            $page .= "<div class=\"panel\">";
            $page .= "<div class=\"panel-heading\"><h2>$desc</h2></div>"
                if $cfg->{Presentation}{htmltitle} eq 'yes';
            $page .= "<div class=\"panel-body\">";

           $page .= qq|<IMG id="zoom" alt="" width="$xs" height="$ys" SRC="${imghref}_${end}_${start}.png">| ;

           $page .= $q->start_form(-method=>'GET', -id=>'range_form')
              . "<p>Time range: "
              . $q->textfield(-name=>'start',-default=>$startstr)
              . "&nbsp;&nbsp;to&nbsp;&nbsp;".$q->textfield(-name=>'end',-default=>$endstr)
              . $q->hidden(-name=>'epoch_start',-id=>'epoch_start',-default=>$start)
              . $q->hidden(-name=>'epoch_end',-id=>'epoch_end',-default=>time())
              . $q->hidden(-name=>'target',-id=>'target' )
              . $q->hidden(-name=>'hierarchy',-id=>'hierarchy' )
              . $q->hidden(-name=>'displaymode',-default=>$mode )
              . "&nbsp;"
              . $q->submit(-name=>'Generate!')
              . "</p>"
              . $q->end_form();

           $page .= "</div></div>\n";
        } elsif ($mode eq 's') { # classic mode
            $startstr =~ s/\s/%20/g;
            $endstr =~ s/\s/%20/g;
            $page .= "<div class=\"panel\">";
#           $page .= (time-$timer_start)."<br/>";
#           $page .= join " ",map {"'$_'"} @task;
            $page .= "<div class=\"panel-heading\"><h2>$desc</h2></div>"
                if $cfg->{Presentation}{htmltitle} eq 'yes';
            $page .= "<div class=\"panel-body\">";
            $page .= ( qq{<a href="?displaymode=n;start=$startstr;end=now;}."target=".$q->param('target').'">'
                  . qq{<IMG ALT="" SRC="${imghref}_${end}_${start}.png">}."</a>" ); #"
            $page .= "</div></div>\n";
        } else { # chart mode
            $page .= "<div class=\"panel\">";
            $page .= "<div class=\"panel-heading\"><h2>$desc</h2></div>"
                if $cfg->{Presentation}{htmltitle} eq 'yes';
            $page .= "<div class=\"panel-body\">";
            $page .= (  qq{<a href="}.lnk($q, (join ".", @$open)).qq{">}
                      . qq{<IMG ALT="" SRC="${imghref}_${end}_${start}.png">}."</a>" ); #"
            $page .= "</div></div>\n";
        }

    }
    return $page;
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
