# -*- perl -*-
package Smokeping;

use strict;
use CGI;
use Getopt::Long;
use Pod::Usage;
use Digest::MD5 qw(md5_base64);
use SNMP_util;
use SNMP_Session;
use POSIX;
use ISG::ParseConfig;
use RRDs;
use Sys::Syslog qw(:DEFAULT setlogsock);
setlogsock('unix')
   if grep /^ $^O $/xo, ("linux", "openbsd", "freebsd", "netbsd");
use File::Basename;

# globale persistent variables for speedy
use vars qw($cfg $probes $VERSION $havegetaddrinfo $cgimode);
$VERSION="1.38";

# we want opts everywhere
my %opt;

BEGIN {
  $havegetaddrinfo = 0;
  eval 'use Socket6';
  $havegetaddrinfo = 1 unless $@;
}

my $DEFAULTPRIORITY = 'info'; # default syslog priority

my $logging = 0; # keeps track of whether we have a logging method enabled

sub do_log(@);
sub load_probe($$$$);

sub load_probes ($){
    my $cfg = shift;
    my %prbs;
    foreach my $probe (keys %{$cfg->{Probes}}) {
    	my @subprobes = grep { ref $cfg->{Probes}{$probe}{$_} eq 'HASH' } keys %{$cfg->{Probes}{$probe}};
    	if (@subprobes) {
		my $modname = $probe;
		my %properties = %{$cfg->{Probes}{$probe}};
		delete @properties{@subprobes};
		for my $subprobe (@subprobes) {
			for (keys %properties) {
				$cfg->{Probes}{$probe}{$subprobe}{$_} = $properties{$_}
					unless exists $cfg->{Probes}{$probe}{$subprobe}{$_};
			}
			$prbs{$subprobe} = load_probe($modname,  $cfg->{Probes}{$probe}{$subprobe},$cfg, $subprobe);
		}
	} else {
		$prbs{$probe} = load_probe($probe, $cfg->{Probes}{$probe},$cfg, $probe);
	}
    }
    return \%prbs;
};

sub load_probe ($$$$) {
	my $modname = shift;
	my $properties = shift;
	my $cfg = shift;
	my $name = shift;
	$name = $modname unless defined $name;
        eval 'require probes::'.$modname;
        die "$@\n" if $@;
	my $rv;
	eval '$rv = probes::'.$modname.'->new( $properties,$cfg,$name);';
        die "$@\n" if $@;
        die "Failed to load Probe $name (module $modname)\n" unless defined $rv;
	return $rv;
}

sub snmpget_ident ($) {
    my $host = shift;
    $SNMP_Session::suppress_warnings = 10; # be silent
    my @get = snmpget("${host}::1:1:1", qw(sysContact sysName sysLocation));
    return undef unless @get;
    my $answer = join "/", grep { defined } @get;
    $answer =~ s/\s+//g;
    return $answer;
}

sub lnk ($$) {
    my ($q, $path) = @_;
    if ($q->isa('dummyCGI')) {
	return $path . ".html";
    } else {
	return ($q->script_name() || '') . "?target=" . $path;
    }
}

sub update_dynaddr ($$){
    my $cfg = shift;
    my $q = shift;
    my @target = split /\./, $q->param('target');
    my $secret = md5_base64($q->param('secret'));
    my $address = $ENV{REMOTE_ADDR};
    my $targetptr = $cfg->{Targets};
    foreach my $step (@target){
	return "Error: Unknown Target $step" 
	  unless defined $targetptr->{$step};
	$targetptr =  $targetptr->{$step};
    };
    return "Error: Invalid Target" 
      unless defined $targetptr->{host} and
      $targetptr->{host} eq "DYNAMIC/${secret}";
    my $file = $cfg->{General}{datadir}."/".(join "/", @target);
    my $prevaddress = "?";
    my $snmp = snmpget_ident $address;
    if (-r "$file.adr" and not -z "$file.adr"){
	open(D, "<$file.adr")
	  or return "Error opening $file.adr: $!\n";            
	chomp($prevaddress = <D>);
	close D;
    }

    if ( $prevaddress ne $address){
	open(D, ">$file.adr.new")
	  or return "Error writing $file.adr.new: $!";
	print D $address,"\n";
	close D;
	rename "$file.adr.new","$file.adr";
    }
    if ( $snmp ) {
	open (D, ">$file.snmp.new")
	  or return "Error writing $file.snmp.new: $!";
	print D $snmp,"\n";
	close D;
	rename "$file.snmp.new", "$file.snmp";
    } elsif ( -f "$file.snmp") { unlink "$file.snmp" };
        
}
sub sendmail ($$$){
    my $from = shift;
    my $to = shift;
    $to = $1 if $to =~ /<(.*?)>/;
    my $body = shift;
    if ($cfg->{General}{mailhost}){
	my $smtp = Net::SMTP->new($cfg->{General}{mailhost});
	$smtp->mail($from);
	$smtp->to(split(/\s*,\s*/, $to));
	$smtp->data();
	$smtp->datasend($body);
	$smtp->dataend();
	$smtp->quit;
    } elsif ($cfg->{General}{sendmail} or -x "/usr/lib/sendmail"){
	open (M, "|-") || exec (($cfg->{General}{sendmail} || "/usr/lib/sendmail"),"-f",$from,$to);
	print M $body;
	close M;
    }
}

sub sendsnpp ($$){
   my $to = shift;
   my $msg = shift;
   if ($cfg->{General}{snpphost}){
        my $snpp = Net::SNPP->new($cfg->{General}{snpphost}, Timeout => 60);
        $snpp->send( Pager => $to,
                     Message => $msg) || do_debuglog("ERROR - ". $snpp->message);
        $snpp->quit;
    }
}

sub init_alerts ($){
    my $cfg = shift;
    foreach my $al (keys %{$cfg->{Alerts}}) {
	my $x = $cfg->{Alerts}{$al};
        next unless ref $x eq 'HASH';
	if ($x->{type} eq 'matcher'){
	    $x->{pattern} =~ /(\S+)\((.+)\)/
		or die "ERROR: Alert $al pattern entry '$_' is invalid\n";
	    my $matcher = $1;
	    my $arg = $2;
	    eval 'require matchers::'.$matcher;
	    die "Matcher '$matcher' could not be loaded: $@\n" if $@;
	    my $hand;
	    eval "\$hand = matchers::$matcher->new($arg)";
  	    die "ERROR: Matcher '$matcher' could not be instantiated\nwith arguments $arg:\n$@\n" if $@;
	    $x->{length} = $hand->Length;
	    $x->{sub} = sub { $hand->Test(shift) } ;
	} else {
	    my $sub_front = <<SUB;
sub { 
    my \$d = shift;
    my \$y = \$d->{$x->{type}};
    for(1){
SUB
	    my $sub;
	    my $sub_back = "        return 1;\n    }\n    return 0;\n}\n";
	    my @ops = split /\s*,\s*/, $x->{pattern};
	    $x->{length} = scalar grep /^[!=><]/, @ops;
	    my $multis = scalar grep /^[*]/, @ops;
	    my $it = "";
	    for(1..$multis){
		my $ind = "    " x ($_-1);
		$sub .= <<FOR;
$ind        my \$i$_;
$ind        for(\$i$_=0; \$i$_<\$imax$_;\$i$_++){
FOR
	    };
	    my $i = - $x->{length};
	    my $incr = 0;
	    for (@ops) {
		my $extra = "";
		$it = "    " x $multis;
		for(1..$multis){
		    $extra .= "-\$i$_";
		};
		/^(==|!=|<|>|<=|>=|\*)(\d+(?:\.\d*)?|U|S|\d*\*)(%?)$/
		    or die "ERROR: Alert $al pattern entry '$_' is invalid\n";
		my $op = $1;
		my $value = $2;
		my $perc = $3;
		if ($op eq '*') {
		    if ($value =~ /^([1-9]\d*)\*$/) {
			$value = $1;
			$x->{length} += $value;
			$sub_front .= "        my \$imax$multis = $value;\n";
			$sub_back .=  "\n";
			$sub .= <<FOR;
$it        last;
$it    }
$it    return 0 if \$i$multis >= \$imax$multis;
FOR
			
			$multis--;
                    next;
		    } else {
			die "ERROR: multi-match operator * must be followed by Number* in Alert $al definition\n";
		    }
		} elsif ($value eq 'U') {
		    if ($op eq '==') {
			$sub .= "$it        next if defined \$y->[$i$extra];\n";
		} elsif ($op eq '!=') {
		    $sub .= "$it        next unless defined \$y->[$i$extra];\n";
		} else {
		    die "ERROR: invalid operator $op in connection U in Alert $al definition\n";
		}
		} elsif ($value eq 'S') {
		    if ($op eq '==') {
			$sub .= "$it        next unless defined \$y->[$i$extra] and \$y->[$i$extra] eq 'S';\n";
		    } else {
			die "ERROR: S is only valid with == operator in Alert $al definition\n";
		}
		} elsif ($value eq '*') {
		    if ($op ne '==') {
			die "ERROR: operator $op makes no sense with * in Alert $al definition\n";
		    } # do nothing else ...
		} else {
		    if ( $x->{type} eq 'loss') {
			die "ERROR: loss should be specified in % (alert $al pattern)\n" unless $perc eq "%";
		} elsif ( $x->{type} eq 'rtt' ) {
		    $value /= 1000;
		} else {
		    die "ERROR: unknown alert type $x->{type}\n";
		}
		    $sub .= <<IF;
$it        next unless defined \$y->[$i$extra]
$it                        and \$y->[$i$extra] =~ /^\\d/
$it                        and \$y->[$i$extra] $op $value;
IF
		}
		$i++;
	    }
	    $sub_front .= "$it        next if scalar \@\$y < $x->{length} ;\n";
	    do_debuglog(<<COMP);
### Compiling alert detector pattern '$al'
### $x->{pattern}
$sub_front$sub$sub_back
COMP
	    $x->{sub} = eval ( $sub_front.$sub.$sub_back );
	    die "ERROR: compiling alert pattern $al ($x->{pattern}): $@\n" if $@;
	}
    }
}


sub check_filter ($$) {
    my $cfg = shift;
    my $name = shift;
    # remove the path prefix when filtering and make sure the path again starts with /
    my $prefix = $cfg->{General}{datadir};
    $name =~ s|^${prefix}/*|/|;
    # if there is a filter do neither schedule these nor make rrds
    if ($opt{filter} && scalar @{$opt{filter}}){
         my $ok = 0;
         for (@{$opt{filter}}){
            /^\!(.+)$/ && do {
    	        my $rx = $1;
                $name !~ /^$rx/ && do{ $ok = 1};
                next;
            };
            /^(.+)$/ && do {
	        my $rx = $1;
                $name =~ /^$rx/ && do {$ok = 1};
                next;
            }; 
         }  
         return $ok;
      };
      return 1;
}

sub init_target_tree ($$$$$$$$); # predeclare recursive subs
sub init_target_tree ($$$$$$$$) {
    my $cfg = shift;
    my $probes = shift;
    my $probe = shift;
    my $tree = shift;
    my $name = shift;
    my $PROBE_CONF = shift;
    my $alerts = shift;
    my $alertee = shift;

    # inherit probe type from parent
    if (not defined $tree->{probe} or $tree->{probe} eq $probe){
	$tree->{probe} = $probe;	
	# inherit parent values if the probe type has not changed
	for (keys %$PROBE_CONF) {
	    $tree->{PROBE_CONF}{$_} = $PROBE_CONF->{$_} 
	    unless exists $tree->{PROBE_CONF}{$_};
	}
    };
    
    $tree->{alerts} = $alerts
	if not defined $tree->{alerts} and defined $alerts;

    $tree->{alertee} = $alertee
	if not defined $tree->{alertee} and defined $alertee;

    if ($tree->{alerts}){
	die "ERROR: no Alerts section\n"
	    unless exists $cfg->{Alerts};
	$tree->{alerts} = [ split(/\s*,\s*/, $tree->{alerts}) ] unless ref $tree->{alerts} eq 'ARRAY';
	$tree->{fetchlength} = 0;
 	foreach my $al (@{$tree->{alerts}}) {
	    die "ERROR: alert $al ($name) is not defined\n"
		unless defined $cfg->{Alerts}{$al};
	    $tree->{fetchlength} = $cfg->{Alerts}{$al}{length}
		if $tree->{fetchlength} < $cfg->{Alerts}{$al}{length};
	}
    };
    # fill in menu and title if missing
    $tree->{menu} ||=  $tree->{host} || "unknown";
    $tree->{title} ||=  $tree->{host} || "unknown";

    foreach my $prop (keys %{$tree}) {
    	next if $prop eq 'PROBE_CONF';
	if (ref $tree->{$prop} eq 'HASH'){
	    if (not -d $name) {
		mkdir $name, 0755 or die "ERROR: mkdir $name: $!\n";
	    };
	    init_target_tree $cfg, $probes, $tree->{probe}, $tree->{$prop}, "$name/$prop", $tree->{PROBE_CONF},$tree->{alerts},$tree->{alertee};
	}
	if ($prop eq 'host' and check_filter($cfg,$name)) {           
	    # print "init $name\n";
	    die "Error: Invalid Probe: $tree->{probe}" unless defined $probes->{$tree->{probe}};
	    my $probeobj = $probes->{$tree->{probe}};
    	    my $step = $probeobj->step();
	    # we have to do the add before calling the _pings method, it won't work otherwise
	    if($tree->{$prop} =~ /^DYNAMIC/) {
		$probeobj->add($tree,$name);
	    } else {
		$probeobj->add($tree,$tree->{$prop});
	    }
	    my $pings = $probeobj->_pings($tree);

	    if (not -f $name.".rrd"){
	    	my @create = 
			($name.".rrd", "--step",$step,
			      "DS:uptime:GAUGE:".(2*$step).":0:U",
			      "DS:loss:GAUGE:".(2*$step).":0:".$pings,
                               # 180 Seconds  is the max rtt we consider valid ... 
			      "DS:median:GAUGE:".(2*$step).":0:180",
			      (map { "DS:ping${_}:GAUGE:".(2*$step).":0:180" }
			                                                  1..$pings),
			      (map { "RRA:".(join ":", @{$_}) } @{$cfg->{Database}{_table}} ));
		do_debuglog("Calling RRDs::create(@create)");
		RRDs::create(@create);
		my $ERROR = RRDs::error();
		do_log "RRDs::create ERROR: $ERROR\n" if $ERROR;
	    }
	}
    }
};

sub enable_dynamic($$$$);
sub enable_dynamic($$$$){
    my $cfg = shift;
    my $cfgfile = $cfg->{__cfgfile};
    my $tree = shift;
    my $path = shift;
    my $email = ($tree->{email} || shift);
    my $print;
    die "ERROR: smokemail property in $cfgfile not specified\n" unless defined $cfg->{General}{smokemail};
    die "ERROR: cgiurl property in $cfgfile not specified\n" unless defined $cfg->{General}{cgiurl};
    if (defined $tree->{host} and $tree->{host} eq 'DYNAMIC' ) {
        if ( not defined $email ) {
            warn "WARNING: No email address defined for $path\n";
        } else {
            my $usepath = $path;
            $usepath =~ s/\.$//;
            my $secret = int(rand 1000000);
	    my $md5 = md5_base64($secret);
	    open C, "<$cfgfile" or die "ERROR: Reading $cfgfile: $!\n";
	    open G, ">$cfgfile.new" or die "ERROR: Writing $cfgfile.new: $!\n";
	    my $section ;
	    my @goal = split /\./, $usepath;
	    my $indent = "+";
	    my $done;
	    while (<C>){
		$done && do { print G; next };
		/^\s*\Q*** Targets ***\E\s*$/ && do{$section = 'match'};
		@goal && $section && /^\s*\Q${indent}\E\s*\Q$goal[0]\E/ && do {
		    $indent .= "+";
		    shift @goal;
		};
		(not @goal) && /^\s*host\s*=\s*DYNAMIC$/ && do {
		    print G "host = DYNAMIC/$md5\n";
		    $done = 1;
		    next;
		};
		print G;
	    }
	    close G;
            rename "$cfgfile.new", $cfgfile;
	    close C;
            my $body;
	    open SMOKE, $cfg->{General}{smokemail} or die "ERROR: can't read $cfg->{General}{smokemail}: $!\n";
	    while (<SMOKE>){
		s/<##PATH##>/$usepath/ig;
		s/<##SECRET##>/$secret/ig;
		s/<##URL##>/$cfg->{General}{cgiurl}/;
                s/<##FROM##>/$cfg->{General}{contact}/;
                s/<##OWNER##>/$cfg->{General}{owner}/;
                s/<##TO##>/$email/;
		$body .= $_;
	    }
	    close SMOKE;


	    my $mail;
            print STDERR "Sending smoke-agent for $usepath to $email ... ";
	    sendmail $cfg->{General}{contact},$email,$body;
	    print STDERR "DONE\n";
        }
    }
    foreach my $prop ( keys %{$tree}) {
    	next if $prop eq "PROBE_CONF";
	enable_dynamic $cfg, $tree->{$prop},"$path$prop.",$email if ref $tree->{$prop} eq 'HASH';
    }
};


sub target_menu($$$;$);
sub target_menu($$$;$){
    my $tree = shift;
    my $open = shift;
    my $path = shift;
    my $suffix = shift || '';
    my $print;
    my $current =  shift @{$open} || "";
     
    my @hashes;
    foreach my $prop (sort { $tree->{$a}{_order} <=> $tree->{$b}{_order}}
                      grep { ref $tree->{$_} eq 'HASH' and $_ ne "PROBE_CONF" }
                      keys %{$tree}) {
	push @hashes, $prop;
    }
    return "" unless @hashes;
    $print .= "<table width=\"100%\" class=\"menu\" border=\"0\" cellpadding=\"0\" cellspacing=\"0\">\n";
    for (@hashes) {
        my $class;
        if ($_ eq $current ){
             if ( @$open ) {
                 $class = 'menuopen';
             } else {
                 $class = 'menuactive';
             }
        } else {
            $class = 'menuitem';
        };
	my $menu = $tree->{$_}{menu};
	$menu =~ s/ /&nbsp;/g;
	my $menuadd ="";
	$menuadd = "&nbsp;" x (20 - length($menu)) if length($menu) < 20;
	$print .= "<tr><td class=\"$class\" colspan=\"2\">&nbsp;-&nbsp;<a class=\"menulink\" HREF=\"$path$_$suffix\">$menu</a>$menuadd</td></tr>\n";
	if ($_ eq $current){
	    my $prline = target_menu $tree->{$_}, $open, "$path$_.", $suffix;
	    $print .= "<tr><td class=\"$class\">&nbsp;&nbsp;</td><td align=\"left\">$prline</td></tr>"
	      if $prline;
	}
    }
    $print .= "</table>\n";
    return $print;
};



sub fill_template ($$){
    my $template = shift;
    my $subst = shift;
    my $line = $/;
    undef $/;
    open I, $template or return "<HTML><BODY>ERROR: Reading page template $template: $!</BODY></HTML>";
    my $data = <I>;
    close I;
    $/ = $line;
    foreach my $tag (keys %{$subst}) {
	$data =~ s/<##${tag}##>/$subst->{$tag}/g;
    }
    return $data;
}

sub exp2seconds ($) {
    my $x = shift;
    $x =~/(\d+)m/ && return $1*60;
    $x =~/(\d+)h/ && return $1*60*60;
    $x =~/(\d+)d/ && return $1*60*60*24;
    $x =~/(\d+)w/ && return $1*60*60*24*7;
    $x =~/(\d+)y/ && return $1*60*60*24*365;
    return $x;
}

sub get_overview ($$$$){
    my $cfg = shift;
    my $q = shift;
    my $tree = shift;
    my $open = shift;
    my $dir = "";

    my $page ="";

    for (@$open) {
	$dir .= "/$_";
	mkdir $cfg->{General}{imgcache}.$dir, 0755 
            unless -d  $cfg->{General}{imgcache}.$dir;
	die "ERROR: creating  $cfg->{General}{imgcache}$dir: $!\n"
                unless -d  $cfg->{General}{imgcache}.$dir;
    }
    my $date = $cfg->{Presentation}{overview}{strftime} ? 
        POSIX::strftime($cfg->{Presentation}{overview}{strftime},
                        localtime(time)) : scalar localtime(time);
    foreach my $prop (sort {$tree->{$a}{_order} <=> $tree->{$b}{_order}} 
                      grep {  ref $tree->{$_} eq 'HASH' and $_ ne "PROBE_CONF" and defined $tree->{$_}{host}}
                      keys %$tree) {
        my $rrd = $cfg->{General}{datadir}.$dir."/$prop.rrd";
        my $max =  $cfg->{Presentation}{overview}{max_rtt} || "100000";
        my $medc = $cfg->{Presentation}{overview}{median_color} || "ff0000";
	my $probe = $probes->{$tree->{$prop}{probe}};
	my $pings = $probe->_pings($tree->{$prop});
	my ($graphret,$xs,$ys) = RRDs::graph 
	  ($cfg->{General}{imgcache}.$dir."/${prop}_mini.png",
	   '--lazy',
	   '--start','-'.exp2seconds($cfg->{Presentation}{overview}{range}),
           '--title',$tree->{$prop}{title},
	   '--height',$cfg->{Presentation}{overview}{height},
	   '--width',,$cfg->{Presentation}{overview}{width},
	   '--vertical-label',"Seconds",
	   '--imgformat','PNG',
           '--lower-limit','0',
	   "DEF:median=${rrd}:median:AVERAGE",
	   "DEF:loss=${rrd}:loss:AVERAGE",
           "CDEF:ploss=loss,$pings,/,100,*",
           "CDEF:dm=median,0,$max,LIMIT",
           "CDEF:dm2=median,1.5,*,0,$max,LIMIT",
	   "LINE1:dm2", # this is for kicking things down a bit
	   "LINE1:dm#$medc:median RTT avg\\:    ",
           "GPRINT:median:AVERAGE: %0.2lf %ss     ",
           "GPRINT:median:LAST:     latest RTT\\: %0.2lf %ss     ",
   	   "GPRINT:ploss:AVERAGE:    avg pkg loss\\: %.2lf %% ",
	   "COMMENT:         $date\\j");
	my $ERROR = RRDs::error();
	$page .= "<div>";
        if (defined $ERROR) {
                $page .= "ERROR: $ERROR";
        } else {
	 $page.="<A HREF=\"".lnk($q, (join ".", @$open, ${prop}))."\">".
            "<IMG BORDER=\"0\" WIDTH=\"$xs\" HEIGHT=\"$ys\" ".
	    "SRC=\"".$cfg->{General}{imgurl}.$dir."/${prop}_mini.png\"></A>";
        }
        $page .="</div>"
    }
    return $page;
}

sub findmax ($$) {
    my $cfg = shift;
    my $rrd = shift;
#    my $pings = "ping".int($cfg->{Database}{pings}/1.1);
    my %maxmedian;
    my @maxmedian;
    for (@{$cfg->{Presentation}{detail}{_table}}) {
	my ($desc,$start) = @{$_};
	$start = exp2seconds($start);
	my ($graphret,$xs,$ys) = RRDs::graph
	  ("dummy", '--start', -$start,
           "DEF:maxping=${rrd}:median:AVERAGE",
           'PRINT:maxping:MAX:%le' );
        my $ERROR = RRDs::error();
           do_log $ERROR if $ERROR;
        my $val = $graphret->[0];
        $val = 1 if $val =~ /nan/i;
        $maxmedian{$start} = $val;
        push @maxmedian, $val;
    }
    my $med = (sort @maxmedian)[int(($#maxmedian) / 2 )];
    my $max = 0.000001;
    foreach my $x ( keys %maxmedian ){
        if ( not defined $cfg->{Presentation}{detail}{unison_tolerance} or (
                $maxmedian{$x} <= $cfg->{Presentation}{detail}{unison_tolerance} * $med
                and $maxmedian{$x} >= $med / $cfg->{Presentation}{detail}{unison_tolerance}) ){
             $max = $maxmedian{$x} unless $maxmedian{$x} < $max;
             $maxmedian{$x} = undef;
        };
     }
     foreach my $x ( keys %maxmedian ){
        if (defined $maxmedian{$x}) {
                $maxmedian{$x} *= 1.5;
        } else {
                $maxmedian{$x} = $max * 1.5;
        }

        $maxmedian{$x} = $cfg->{Presentation}{detail}{max_rtt} 
                if $cfg->{Presentation}{detail}{max_rtt} and
		    $maxmedian{$x} > $cfg->{Presentation}{detail}{max_rtt}
     };
     return \%maxmedian;    
}

sub smokecol ($) {
    my $count = ( shift )- 2 ;
    return [] unless $count > 0;
    my $half = $count/2;
    my @items;
    for (my $i=$count; $i > $half; $i--){
	my $color = int(190/$half * ($i-$half))+50;
	push @items, "AREA:cp".($i+2)."#".(sprintf("%02x",$color) x 3);
    };
    for (my $i=int($half); $i >= 0; $i--){
	my $color = int(190/$half * ($half - $i))+64;
	push @items, "AREA:cp".($i+2)."#".(sprintf("%02x",$color) x 3);
    };
    return \@items;
}

sub get_detail ($$$$){
    my $cfg = shift;
    my $q = shift;
    my $tree = shift;
    my $open = shift;
    return "" unless $tree->{host};
    my @dirs = @{$open};
    my $file = pop @dirs;
    my $dir = "";
    die "ERROR: ".(join ".", @dirs)." has no probe defined\n" 
        unless $tree->{probe};
    die "ERROR: ".(join ".", @dirs)." $tree->{probe} is not known\n"
        unless $cfg->{__probes}{$tree->{probe}};
    my $probe = $cfg->{__probes}{$tree->{probe}};
    my $ProbeDesc = $probe->ProbeDesc();
    my $step = $probe->step();
    my $pings = $probe->_pings($tree);

    my $page;


    for (@dirs) {
	$dir .= "/$_";
	mkdir $cfg->{General}{imgcache}.$dir, 0755 
                unless -d  $cfg->{General}{imgcache}.$dir;
	die "ERROR: creating  $cfg->{General}{imgcache}$dir: $!\n"
                unless -d  $cfg->{General}{imgcache}.$dir;
	
    }
    my $rrd = $cfg->{General}{datadir}."/".(join "/", @dirs)."/${file}.rrd";
    my $img = $cfg->{General}{imgcache}."/".(join "/", @dirs)."/${file}.rrd";

    my %lasthight;
    if (open (HG,"<${img}.maxhight")){
        while (<HG>){
          chomp;
          my @l = split / /;
          $lasthight{$l[0]} = $l[1];
        }
        close HG;
    }
    my $max = findmax $cfg, $rrd;
    if (open (HG,">${img}.maxhight")){
        foreach my $s (keys %{$max}){
          print HG "$s $max->{$s}\n";        
        }
        close HG;
    }

    my $smoke = $pings - 3 > 0
         ? smokecol $pings : [ 'COMMENT:"Not enough data collected to draw graph"'  ];
    my @upargs;
    my @upsmoke;
    my @median;
    my $date = $cfg->{Presentation}{detail}{strftime} ? 
        POSIX::strftime($cfg->{Presentation}{detail}{strftime},
                        localtime(time)) : scalar localtime(time);

    for (@{$cfg->{Presentation}{detail}{_table}}) {
	my ($desc,$start) = @{$_};
	$start = exp2seconds($start);
    do {
	@median = ("DEF:median=${rrd}:median:AVERAGE",
		   "DEF:loss=${rrd}:loss:AVERAGE",
                   "CDEF:ploss=loss,$pings,/,100,*",
           	   "GPRINT:median:AVERAGE:Median Ping RTT (avg %.1lf %ss) ",
                   "LINE1:median#202020"
        	   );
	my $p = $pings;

        my %lc;
        my $lastup = 0;
        if ( defined $cfg->{Presentation}{detail}{loss_colors}{_table} ) {
              for (@{$cfg->{Presentation}{detail}{loss_colors}{_table}}) {
                   my ($num,$col,$txt) = @{$_};
                   $lc{$num} = [ $txt, "#".$col ];
              }
       } else {  
         	%lc =  (0     => ['0',   '#26ff00'],
		   1          => ["1/$p",  '#00b8ff'],
		   2          => ["2/$p",  '#0059ff'],
		   3          => ["3/$p",  '#5e00ff'],
		   4          => ["4/$p",  '#7e00ff'],
		   int($p/2)  => [int($p/2)."/$p", '#dd00ff'],
		   $p-1       => [($p-1)."/$p",    '#ff0000'],
		  );
        };
        my $last = -1;
        my $swidth = $max->{$start} / $cfg->{Presentation}{detail}{height};
	foreach my $loss (sort {$a <=> $b} keys %lc){
            my $lvar = $loss; $lvar =~ s/\./d/g ;
	    push @median, 
	    (
	     "CDEF:me$lvar=loss,$last,GT,loss,$loss,LE,*,1,UNKN,IF,median,*",
	     "CDEF:meL$lvar=me$lvar,$swidth,-",
	     "CDEF:meH$lvar=me$lvar,0,*,$swidth,2,*,+",             
	     "AREA:meL$lvar",
	     "STACK:meH$lvar$lc{$loss}[1]:$lc{$loss}[0]"
	     );
             $last = $loss;
	}
	push @median, ( "GPRINT:ploss:AVERAGE:    avg pkg loss\\: %.2lf %%\\l" );
#	map {print "$_<br/>"} @median;
    };
        # if we have uptime draw a colorful background or the graph showing the uptime
        my $cdir=$cfg->{General}{datadir}."/".(join "/", @dirs)."/";
        if (-f "$cdir/${file}.adr") {
                @upsmoke = ();
        	@upargs = ('COMMENT:Link Up:     ',
	        	   "DEF:uptime=${rrd}:uptime:AVERAGE",
		           "CDEF:duptime=uptime,86400,/", 
       		           'GPRINT:duptime:LAST: %0.1lf days  (');
        	my %upt;
                if ( defined $cfg->{Presentation}{detail}{uptime_colors}{_table} ) {
                    for (@{$cfg->{Presentation}{detail}{uptime_colors}{_table}}) {
                        my ($num,$col,$txt) = @{$_};
                        $upt{$num} = [ $txt, "#".$col];
                    }
                } else {  
                    %upt = ( 3600       => ['<1h', '#FFD3D3'],
	        	    2*3600     => ['<2h', '#FFE4C7'],
	        	    6*3600     => ['<6h', '#FFF9BA'],
	        	    12*3600    => ['<12h','#F3FFC0'],
	        	    24*3600    => ['<1d', '#E1FFCC'],
         		    7*24*3600  => ['<1w', '#BBFFCB'],
	        	    30*24*3600 => ['<1m', '#BAFFF5'],
	        	    '1e100'    => ['>1m', '#DAECFF']
	        	    );
                }                
	        my $lastup = 0;
        	foreach my $uptime (sort {$a <=> $b} keys %upt){
        	    push @upargs, 
        	    (
        	     "CDEF:up$uptime=uptime,$lastup,GE,uptime,$uptime,LE,*,INF,UNKN,IF",
        	     "AREA:up$uptime$upt{$uptime}[1]:$upt{$uptime}[0]"
        	     );
                    push @upsmoke, 
        	    (
        	     "CDEF:ups$uptime=uptime,$lastup,GE,uptime,$uptime,LE,*,cp2,UNKN,IF",
        	     "AREA:ups$uptime$upt{$uptime}[1]"
        	     );                    
               	    $lastup=$uptime;
	}
	
	push @upargs, 'COMMENT:)\l';
#	map {print "$_<br/>"} @upargs;
    };
        my @log = ();
        push @log, "--logarithmic" if  $cfg->{Presentation}{detail}{logarithmic} and
	    $cfg->{Presentation}{detail}{logarithmic} eq 'yes';

        my @lazy =();
        @lazy = ('--lazy') if $lasthight{$start} and $lasthight{$start} == $max->{$start};
	my ($graphret,$xs,$ys) = RRDs::graph
	  ($cfg->{General}{imgcache}.$dir."/${file}_last_${start}.png",
	   @lazy,
	   '--start','-'.$start,
	   '--height',$cfg->{Presentation}{detail}{height},
	   '--width',,$cfg->{Presentation}{detail}{width},
	   '--title',$desc,
           '--rigid',
           '--upper-limit', $max->{$start},
	   @log,
	   '--lower-limit',(@log ? ($max->{$start} > 0.01) ? '0.001' : '0.0001' : '0'),
	   '--vertical-label',"Seconds",
	   '--imgformat','PNG',
	   '--color', 'SHADEA#ffffff',
	   '--color', 'SHADEB#ffffff',
	   '--color', 'BACK#ffffff',
	   '--color', 'CANVAS#ffffff',
	   (map {"DEF:ping${_}=${rrd}:ping${_}:AVERAGE"} 1..$pings),
	   (map {"CDEF:cp${_}=ping${_},0,$max->{$start},LIMIT"} 1..$pings),
	   @upargs,# draw the uptime bg color
 	   @$smoke,
           @upsmoke, # draw the rest of the uptime bg color
	   @median,
#	   'LINE3:median#ff0000:Median RTT    in grey '.$cfg->{Database}{pings}.' pings sorted by RTT',
#	   'LINE1:median#ff8080',
           # Gray background for times when no data was collected, so they can
           # be distinguished from network being down.
           ( $cfg->{Presentation}{detail}{nodata_color} ? (
		 'CDEF:nodata=loss,UN,INF,UNKN,IF',
           	 "AREA:nodata#$cfg->{Presentation}{detail}{nodata_color}" ):
		 ()),
	   'HRULE:0#000000',
	   'COMMENT:\s',
           "COMMENT:Probe: $pings $ProbeDesc every $step seconds",
	   'COMMENT:created on '.$date.'\j' );
	
	my $ERROR = RRDs::error();
	$page .= "<div>".
	  ( $ERROR ||
	   "<IMG BORDER=\"0\" WIDTH=\"$xs\" HEIGHT=\"$ys\" ".
	   "SRC=\"".$cfg->{General}{imgurl}.$dir."/${file}_last_${start}.png\">" )."</div>";

    }
    return $page;
}

sub display_webpage($$){
    my $cfg = shift;
    my $q = shift;
    my $open = [ split /\./,( $q->param('target') || '')];
    my $tree = $cfg->{Targets};
    my $step = $cfg->{__probes}{$tree->{probe}}->step();
    for (@$open) {
        die "ERROR: Section '$_' does not exist.\n" 
                unless exists $tree->{$_};
	last unless  ref $tree->{$_} eq 'HASH';
	$tree = $tree->{$_};
    }
    gen_imgs($cfg); # create logos in imgcache

    print fill_template
      ($cfg->{Presentation}{template},
       {
	menu => target_menu($cfg->{Targets},
			    [@$open], #copy this because it gets changed
			    ($q->script_name() || '')."?target="),
	title => $tree->{title},
	remark => ($tree->{remark} || ''),
	overview => get_overview( $cfg,$q,$tree,$open ),
	body => get_detail( $cfg,$q,$tree,$open ),
        target_ip => ($tree->{host} || ''),
	owner => $cfg->{General}{owner},
        contact => $cfg->{General}{contact},
        author => '<A HREF="http://tobi.oetiker.ch/">Tobi&nbsp;Oetiker</A>',
        smokeping => '<A HREF="http://people.ee.ethz.ch/~oetiker/webtools/smokeping/counter.cgi/'.$VERSION.'">SmokePing-'.$VERSION.'</A>',
        step => $step,
        rrdlogo => '<A HREF="http://people.ee.ethz.ch/~oetiker/webtools/rrdtool/"><img border="0" src="'.$cfg->{General}{imgurl}.'/rrdtool.png"></a>',
        smokelogo => '<A HREF="http://people.ee.ethz.ch/~oetiker/webtools/smokeping/counter.cgi/'.$VERSION.'"><img border="0" src="'.$cfg->{General}{imgurl}.'/smokeping.png"></a>',
       }
       );
}

# fetch all data.
sub run_probes($$) {
    my $probes = shift;
    my $justthisprobe = shift;
    if (defined $justthisprobe) {
      $probes->{$justthisprobe}->ping();
    } else {
      foreach my $probe (keys %{$probes}) {
              $probes->{$probe}->ping();
      }
    }
}

# report probe status
sub report_probes($$) {
    my $probes = shift;
    my $justthisprobe = shift;
    if (defined $justthisprobe) {
      $probes->{$justthisprobe}->report();
    } else {
      foreach my $probe (keys %{$probes}){
              $probes->{$probe}->report();
      }
    }
}

sub update_rrds($$$$$$);
sub update_rrds($$$$$$) {
    my $cfg = shift;
    my $probes = shift;
    my $probe = shift;
    my $tree = shift;
    my $name = shift;
    my $justthisprobe = shift; # if defined, update only the targets probed by this probe

    $probe = $tree->{probe} if defined $tree->{probe};
    my $probeobj = $probes->{$probe};
    foreach my $prop (keys %{$tree}) {

    	next if $prop eq "PROBE_CONF";
        if (ref $tree->{$prop} eq 'HASH'){
            update_rrds $cfg, $probes, $probe, $tree->{$prop}, $name."/$prop", $justthisprobe;
        } 
        next if defined $justthisprobe and $probe ne $justthisprobe;
        if ($prop eq 'host' and check_filter($cfg,$name)) {
            #print "update $name\n";
	    my $updatestring = $probeobj->rrdupdate_string($tree);
	    my $pings = $probeobj->_pings($tree);
	    if ( $tree->{rawlog} ){
		my $file =  POSIX::strftime $tree->{rawlog},localtime(time);
		if (open LOG,">>$name.$file.csv"){
			print LOG time,"\t",join("\t",split /:/,$updatestring),"\n";
			close LOG;
		} else {
			do_log "Warning: failed to open $file for logging: $!\n";
		}
            }	
            my @update = ( $name.".rrd", 
        	   '--template',(join ":", "uptime", "loss", "median",
				 map { "ping${_}" } 1..$pings),
	           "N:".$updatestring
		 );     
	    do_debuglog("Calling RRDs::update(@update)");
            RRDs::update ( @update );
            my $ERROR = RRDs::error();
	    do_log "RRDs::update ERROR: $ERROR\n" if $ERROR;
	    # check alerts
            # disabled
	    if ( $tree->{alerts} ) {
                $tree->{stack} = {loss=>['S'],rtt=>['S']} unless defined $tree->{stack};
		my $x = $tree->{stack};
		my ($loss,$rtt) = 
		    (split /:/, $probeobj->rrdupdate_string($tree))[1,2];
		$loss = undef if $loss eq 'U';
		my $lossprct = $loss * 100 / $pings;
		$rtt = undef if $rtt eq 'U';
		push @{$x->{loss}}, $lossprct;
		push @{$x->{rtt}}, $rtt;
		if (scalar @{$x->{loss}} > $tree->{fetchlength}){
		    shift @{$x->{loss}};
		    shift @{$x->{rtt}};
		}
		for (@{$tree->{alerts}}) {
                    if ( not $cfg->{Alerts}{$_} ) {
                        do_log "WARNING: Empty alert in ".(join ",", @{$tree->{alerts}})." ($name)\n";
                        next;
                    };
                    if ( ref $cfg->{Alerts}{$_}{sub} ne 'CODE' ) {
       		        do_log "WARNING: Alert '$_' did not resolve to a Sub Ref. Skipping\n";
                        next;
                    };
		    if ( &{$cfg->{Alerts}{$_}{sub}}($x) ){
			# we got a match
			my $from;
                        my $line = "$name/$prop";
                        my $base = $cfg->{General}{datadir};
                        $line =~ s|^$base/||;
                        $line =~ s|/host$||;
                        $line =~ s|/|.|g;
			do_log("Alert $_ triggered for $line");
                        my $urlline = $line;
                        $urlline =  $cfg->{General}{cgiurl}."?target=".$line;
                        my $loss = "loss: ".join ", ",map {defined $_ ? (/^\d/ ? sprintf "%.0f%%", $_ :$_):"U" } @{$x->{loss}};
                        my $rtt = "rtt: ".join ", ",map {defined $_ ? (/^\d/ ? sprintf "%.0fms", $_*1000 :$_):"U" } @{$x->{rtt}}; 
                        my $stamp = scalar localtime time;
			my @to;
			foreach my $addr (map {$_ ? (split /\s*,\s*/,$_) : ()} $cfg->{Alerts}{to},$tree->{alertee},$cfg->{Alerts}{$_}{to}){
			     next unless $addr;
			     if ( $addr =~ /^\|(.+)/) {
  			         system $1,$_,$line,$loss,$rtt,$tree->{host};				     
			     } elsif ( $addr =~ /^snpp:(.+)/ ) {
				 sendsnpp $1, <<SNPPALERT;
$cfg->{Alerts}{$_}{comment}
$_ on $line
$loss
$rtt
SNPPALERT
			     } else {
			    	 push @to, $addr;
			     }
			};
			if (@to){
			    my $to = join ",",@to;
			    sendmail $cfg->{Alerts}{from},$to, <<ALERT;
To: $to
From: $cfg->{Alerts}{from}
Subject: [SmokeAlert] $_ on $line

$stamp

Got a match for alert "$_" for $urlline

Pattern
-------
$cfg->{Alerts}{$_}{pattern}

Data (old --> now)
------------------
$loss
$rtt

Comment
-------
$cfg->{Alerts}{$_}{comment}



ALERT
			}
		    }
		}
	    }
	}
    }
}

sub get_parser () {
    my $KEY_RE = '[-_0-9a-zA-Z]+';
    my $KEYD_RE = '[-_0-9a-zA-Z.]+';
    my $TARGET = 
      {
       _sections => [ ( "PROBE_CONF", "/$KEY_RE/" ) ],
       _vars     => [ qw (probe menu title alerts note email host remark rawlog alertee) ],
       _order    => 1,
       _doc => <<DOC,
Each target section can contain information about a host to monitor as
well as further target sections. Most variables have already been
described above. The expression above defines legal names for target
sections.
DOC
       alerts    => {
		     _doc => 'Comma separated list of alert names',
		     _re => '([^\s,]+(,[^\s,]+)*)?',
		     _re_error => 'Comma separated list of alert names',
		    },
       host      => 
       {
	_doc => <<DOC,
Can either contain the name of a target host or the string B<DYNAMIC>.

In the second case, the target machine has a dynamic IP address and
thus is required to regularly contact the SmokePing server to verify
its IP address.  When starting SmokePing with the commandline argument
B<--email> it will add a secret password to each of the B<DYNAMIC>
host lines and send a script to the owner of each host. This script
must be started regularly on the host in question to make sure
SmokePing monitors the right box. If the target machine supports
SNMP SmokePing will also query the hosts
sysContact, sysName and sysLocation properties to make sure it is
still the same host.
DOC

	_sub => sub {
	    for ( shift ) {
		m|^DYNAMIC| && return undef;
		/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/ && return undef;
		/^[0-9a-f]{0,4}(\:[0-9a-f]{0,4}){0,6}\:[0-9a-f]{0,4}$/i && return undef;
		my $addressfound = 0;
		my @tried;
		if ($havegetaddrinfo) {
  		    my @ai;
		    @ai = getaddrinfo( $_, "" );
                    unless ($addressfound = scalar(@ai) > 5) {
                        do_debuglog("WARNING: Hostname '$_' does currently not resolve to an IPv6 address\n");
			@tried = qw{IPv6};
		    }
                }
                unless ($addressfound) {
                   unless ($addressfound = gethostbyname( $_ )) {
                        do_debuglog("WARNING: Hostname '$_' does currently not resolve to an IPv4 address\n");
			push @tried, qw{IPv4};
                   }
                }
                unless ($addressfound) {
                   # do not bomb, as this could be temporary
	           my $tried = join " or ", @tried;
                   warn "WARNING: Hostname '$_' does currently not resolve to an $tried address\n" unless $cgimode;
		}
                return undef;
	    }
	    return undef;
        },
       },
       email => { _re => '.+\s<\S+@\S+>',
		  _re_error =>
		  "use an email address of the form 'First Last <em\@ail.kg>'",
		  _doc => <<DOC,
This is the contact address for the owner of the current host. In connection with the B<DYNAMIC> hosts,
the address will be used for sending the belowmentioned script.
DOC
		},
       note => { _doc => <<DOC },
Some information about this entry which does NOT get displayed on the web.
DOC
      rawlog => { _doc => <<DOC,
Log the raw data, gathered for this target, in tab separated format, to a file with the
same basename as the corresponding RRD file. Use posix strftime to format the timestamp to be
put into the file name. The filename is built like this:

 basename.strftime.csv

Example:

 rawlog=%Y-%m-%d

this would create a new logfile every day with a name like this: 

 targethost.2004-05-03.csv

DOC
       		  _sub => sub {
               		eval ( "POSIX::strftime('$_[0]', localtime(time))");
                        return $@ if $@;
                        return undef;
        	  }, 
           },
	   alertee => { _re => '(\|.+|.+@\S+|snpp:)',
			_re_error => 'the alertee must be an email address here',
			_doc => <<DOC },
If you want to have alerts for this target and all targets below it go to a particular address
on top of the address already specified in the alert, you can add it here. This can be a comma separated list of items.
DOC

    };

    $TARGET->{ "/$KEY_RE/" } = $TARGET;

    my $PROBEVARS = {
    	_vars => [ "/$KEYD_RE/" ],
	_doc => <<DOC,
Probe specific variables. 
DOC
	"/$KEYD_RE/" => { _doc => <<DOC },
Should be found in the documentation of the
corresponding probe. The values get propagated to those child
nodes using the same Probe.
DOC
    };

    $TARGET->{PROBE_CONF} = $PROBEVARS;

    my $INTEGER_SUB = {
        _sub => sub {
            return "must be an integer >= 1"
                unless $_[ 0 ] == int( $_[ 0 ] ) and $_[ 0 ] >= 1;
            return undef;
        }
    };
    my $DIRCHECK_SUB = {
        _sub => sub {
            return "Directory '$_[0]' does not exist" unless -d $_[ 0 ];
            return undef;
        }
    };

    my $FILECHECK_SUB = {
        _sub => sub {
            return "File '$_[0]' does not exist" unless -f $_[ 0 ];
            return undef;
        }
    };

    my $PROBES = {
		                    _doc => <<DOC,
Each module can take specific configuration information from this area. The jumble of letters above is a regular expression defining legal module names.
DOC
				    _vars => [ "step", "offset", "pings", "/$KEYD_RE/" ],
				    "/$KEYD_RE/" => { _doc => 'Each module defines which
variables it wants to accept. So this expression here just defines legal variable names.'},
				    "step" => { %$INTEGER_SUB,
				    		_doc => <<DOC },
Duration of the base interval that this probe should use, if different
from the one specified in the 'Database' section. Note that the step in 
the RRD files is fixed when they are originally generated, and if you
change the step parameter afterwards, you'll have to delete the old RRD
files or somehow convert them. (This variable is only applicable if 
the variable 'concurrentprobes' is set in the 'General' section.)
DOC
				    "offset" => {
	  				_re => '(\d+%|random)',
	  				_re_error => 
	  				"Use offset either in % of operation interval or 'random'",
         				_doc => <<DOC },
If you run many probes concurrently you may want to prevent them from
hitting your network all at the same time. Using the probe-specific
offset parameter you can change the point in time when each probe will
be run. Offset is specified in % of total interval, or alternatively as
'random', and the offset from the 'General' section is used if nothing
is specified here. Note that this does NOT influence the rrds itself,
it is just a matter of when data acqusition is initiated. 
(This variable is only applicable if the variable 'concurrentprobes' is set
in the 'General' section.)
DOC
				    "pings" => {
	  				%$INTEGER_SUB,
	  				_doc => <<DOC},
How many pings should be sent to each target, if different from the global
value specified in the Database section.  Some probes (those derived from
basefork.pm, ie. most except the FPing variants) will even let this be
overridden target-specifically in the PROBE_CONF section (see the
basefork documentation for details).  Note that the number of pings in
the RRD files is fixed when they are originally generated, and if you
change this parameter afterwards, you'll have to delete the old RRD
files or somehow convert them.
DOC
    }; # $PROBES

    my $PROBESTOP = {};
    %$PROBESTOP = %$PROBES;
    $PROBESTOP->{_sections} = ["/$KEY_RE/"];
    $PROBESTOP->{"/$KEY_RE/"} = $PROBES;
    for (qw(step offset pings)) {
    	# we need a deep copy of these
	my %h = %{$PROBESTOP->{$_}};
    	$PROBES->{$_} = \%h;
    	delete $PROBES->{$_}{_doc} 
    }
    $PROBES->{_doc} = <<DOC;
You can define multiple instances of the same probe with subsections. 
These instances can have different values for their variables, so you
can eg. have one instance of the FPing probe with packet size 1000 and
step 30 and another instance with packet size 64 and step 300.
The name of the subsection determines what the probe will be called, so
you can write descriptive names for the probes.

If there are any subsections defined, the main section for this probe
will just provide default parameter values for the probe instances, ie.
it will not become a probe instance itself.
DOC

    my $parser = ISG::ParseConfig->new 
      (
       {
	_sections  => [ qw(General Database Presentation Probes Alerts Targets) ],
	_mandatory => [ qw(General Database Presentation Probes Targets) ],
	General    => 
	{
	 _doc => <<DOC,
General configuration values valid for the whole SmokePing setup.
DOC
	 _vars =>
	 [ qw(owner imgcache imgurl datadir pagedir piddir sendmail offset
              smokemail cgiurl mailhost contact netsnpp
	      syslogfacility syslogpriority concurrentprobes changeprocessnames) ],
	 _mandatory =>
	 [ qw(owner imgcache imgurl datadir piddir
              smokemail cgiurl contact) ],
	 imgcache => 
	 { %$DIRCHECK_SUB,
	   _doc => <<DOC,
A directory which is visible on your webserver where SmokePing can cache graphs.
DOC
	 },
	 
	 imgurl   => 
	 {
	  _doc => <<DOC,
Either an absolute URL to the B<imgcache> directory or one relative to the directory where you keep the
SmokePing cgi.
DOC
	 },

	 pagedir =>
	 {
	  %$DIRCHECK_SUB,
	  _doc => <<DOC,
Directory to store static representations of pages.
DOC
	 },
	 owner  => 
	 {
	  _doc => <<DOC,
Name of the person responsible for this smokeping installation.
DOC
	 },

	 mailhost  => 
	 {
	  _doc => <<DOC,
Instead of using sendmail, you can specify the name of an smtp server 
and use perl's Net::SMTP module to send mail to DYNAMIC host owners (see below).
DOC
          _sub => sub { require Net::SMTP ||return "ERROR: loading Net::SMTP"; return undef; }
	 },
	 snpphost  => 
	 {
	  _doc => <<DOC,
If you have a SNPP (Simple Network Pager Protocol) server at hand, you can have alerts
sent there too. Use the syntax B<snpp:someaddress> to use a snpp address in any place where you can use a mail address otherwhise.
DOC
          _sub => sub { require Net::SNPP ||return "ERROR: loading Net::SNPP"; return undef; }
	 },

	 contact  => 
	 { _re => '\S+@\S+',
           _re_error =>
	  "use an email address of the form 'name\@place.dom'",
		
	  _doc => <<DOC,
Mail address of the person responsible for this smokeping installation.
DOC
	 },
            
	 
	 datadir  => 
	 {
	  %$DIRCHECK_SUB,
	  _doc => <<DOC,
The directory where SmokePing can keep its rrd files.
DOC
	},

	piddir  =>
	{
	 %$DIRCHECK_SUB,
	 _doc => <<DOC,
The directory where SmokePing keeps its pid when daemonised.
DOC
	 },
	 sendmail => 
	 {
	  %$FILECHECK_SUB,
	  _doc => <<DOC,
Path to your sendmail binary. It will be used for sending mails in connection with the support of DYNAMIC addresses.			     
DOC
	 },
	 smokemail => 
	 {
	  %$FILECHECK_SUB,
	  _doc => <<DOC,
Path to the mail template for DYNAMIC hosts. This mail template
must contain keywords of the form B<E<lt>##>I<keyword>B<##E<gt>>. There is a sample
template included with SmokePing.
DOC
	 },
	 cgiurl    => 
	 { 
	  _re => 'https?://\S+',
	  _re_error =>
	  "cgiurl must be a http(s)://.... url",
	  _doc => <<DOC,
Complete URL path of the SmokePing.cgi
DOC
	  
	 },
	 syslogfacility	=>
	 {
	  _re => '\w+',
	  _re_error => 
	  "syslogfacility must be alphanumeric",
	  _doc => <<DOC,
The syslog facility to use, eg. local0...local7. 
Note: syslog logging is only used if you specify this.
DOC
	 },
	 syslogpriority	=>
	 {
	  _re => '\w+',
	  _re_error => 
	  "syslogpriority must be alphanumeric",
	  _doc => <<DOC,
The syslog priority to use, eg. debug, notice or info. 
Default is $DEFAULTPRIORITY.
DOC
	 },
         offset => {
	  _re => '(\d+%|random)',
	  _re_error => 
	  "Use offset either in % of operation interval or 'random'",
         _doc => <<DOC,
If you run many instances of smokeping you may want to prevent them from
hitting your network all at the same time. Using the offset parameter you
can change the point in time when the probes are run. Offset is specified
in % of total interval, or alternatively as 'random'. I recommend to use
'random'. Note that this does NOT influence the rrds itself, it is just a
matter of when data acqusition is initiated.  The default offset is 'random'.
DOC
         },
	 concurrentprobes => {
	  _re => '(yes|no)',
          _re_error =>"this must either be 'yes' or 'no'",
	  _doc => <<DOC,
If you use multiple probes or multiple instances of the same probe and you
want them to run concurrently in separate processes, set this to 'yes'. This
gives you the possibility to specify probe-specific step and offset parameters 
(see the 'Probes' section) for each probe and makes the probes unable to block
each other in cases of service outages. The default is 'yes', but if you for
some reason want the old behaviour you can set this to 'no'.
DOC
	 },
	 changeprocessnames => {
	  _re => '(yes|no)',
          _re_error =>"this must either be 'yes' or 'no'",
	  _doc => <<DOC,
When using 'concurrentprobes' (see above), this controls whether the probe
subprocesses should change their argv string to indicate their probe in
the process name.  If set to 'yes' (the default), the probe name will
be appended to the process name as '[probe]', eg.  '/usr/bin/smokeping
[FPing]'. If you don't like this behaviour, set this variable to 'no'.
If 'concurrentprobes' is not set to 'yes', this variable has no effect.
DOC
	 },
	},
	Database => 
	{ 
	 _vars => [ qw(step pings) ],
	 _mandatory => [ qw(step pings) ],
	 _doc => <<DOC,
Describes the properties of the round robin database for storing the
SmokePing data. Note that it is not possible to edit existing RRDs
by changing the entries in the cfg file.
DOC
	 
	 step   => 
	 { %$INTEGER_SUB,
	   _doc => <<DOC,
Duration of the base operation interval of SmokePing in seconds.
SmokePing will venture out every B<step> seconds to ping your target hosts.
If 'concurrent_probes' is set to 'yes' (see above), this variable can be 
overridden by each probe. Note that the step in the RRD files is fixed when 
they are originally generated, and if you change the step parameter afterwards, 
you'll have to delete the old RRD files or somehow convert them. 
DOC
	 },
	 pings  => 
	 {
	  %$INTEGER_SUB,
	  _doc => <<DOC,
How many pings should be sent to each target. Suggested: 20 pings.
This can be overridden by each probe. Some probes (those derived from
basefork.pm, ie. most except the FPing variants) will even let this
be overridden target-specifically in the PROBE_CONF section (see the
basefork documentation for details).  Note that the number of pings in
the RRD files is fixed when they are originally generated, and if you
change this parameter afterwards, you'll have to delete the old RRD
files or somehow convert them.
DOC
	 },

	 _table => 
	 {
	  _doc => <<DOC,
This section also contains a table describing the setup of the
SmokePing database. Below are reasonable defaults. Only change them if
you know rrdtool and its workings. Each row in the table describes one RRA.

 # cons   xff steps rows
 AVERAGE  0.5   1   1008
 AVERAGE  0.5  12   4320
     MIN  0.5  12   4320
     MAX  0.5  12   4320
 AVERAGE  0.5 144    720
     MAX  0.5 144    720
     MIN  0.5 144    720

DOC
	  _columns => 4,
	  0        => 
	  {
	   _doc => <<DOC,
Consolidation method.
DOC
	   _re       => '(AVERAGE|MIN|MAX)',
	   _re_error => "Choose a valid consolidation function",
	  },
	  1 => 
	  {
	   _doc => <<DOC,
What part of the consolidated intervals must be known to warrant a known entry.
DOC
		_sub => sub {
		    return "Xff must be between 0 and 1"
		      unless $_[ 0 ] > 0 and $_[ 0 ] <= 1;
		    return undef;
		}
	       },
	  2 => {%$INTEGER_SUB,
	   _doc => <<DOC,
How many B<steps> to consolidate into for each RRA entry.
DOC
	       },

	  3 => {%$INTEGER_SUB,
	   _doc => <<DOC,
How many B<rows> this RRA should have.
DOC
	       }
	 }
	},
	Presentation => 
	{ 
	 _doc => <<DOC,
Defines how the SmokePing data should be presented.
DOC
	 _sections => [ qw(overview detail) ],
	  _mandatory => [ qw(overview template detail) ],
	  _vars      => [ qw (template charset) ],
	  template   => 
	 {
	  _doc => <<DOC,
The webpage template must contain keywords of the form 
B<E<lt>##>I<keyword>B<##E<gt>>. There is a sample
template included with SmokePing; use it as the basis for your
experiments. Default template contains a pointer to the SmokePing
counter and homepage. I would be glad if you would not remove this as
it gives me an indication as to how widely used the tool is.
DOC

	  _sub => sub {
	      return "template '$_[0]' not readable" unless -r $_[ 0 ];
	      return undef;
	  }
	 },
         charset => {
	  _doc => <<DOC,
By default, SmokePing assumes the 'iso-8859-15' character set. If you use
something else, this is the place to speak up.
DOC
        },
			 
	 overview   => 
	 { _vars => [ qw(width height range max_rtt median_color strftime) ],
	   _mandatory => [ qw(width height) ],           
	   _doc => <<DOC,
The Overview section defines how the Overview graphs should look.
DOC
         max_rtt => {    _doc => <<DOC },
Any roundtrip time larger than this value will cropped in the overview graph
DOC
        median_color => {    _doc => <<DOC,
By default the median line is drawn in red. Override it here with a hex color
in the format I<rrggbb>.
DOC
                              _re => '[0-9a-f]{6}',
                              _re_error => 'use rrggbb for color',
           },
          strftime => { _doc => <<DOC,
Use posix strftime to format the timestamp in the left hand
lower corner of the overview graph
DOC
          _sub => sub {
                eval ( "POSIX::strftime( '$_[0]', localtime(time))" );
                return $@ if $@;
                return undef;
	    },
          },

              
	   width      =>
	   {
	    _sub => sub {
		return "width must be be an integer >= 10"
		  unless $_[ 0 ] >= 10
		    and int( $_[ 0 ] ) == $_[ 0 ];
		return undef;
	    },
	    _doc => <<DOC,
Width of the Overview Graphs.
DOC
	    },
	    height => 
	    { 
	     _doc => <<DOC,
Height of the Overview Graphs.
DOC
	     _sub => sub {
		 return "height must be an integer >= 10"
		   unless $_[ 0 ] >= 10
		     and int( $_[ 0 ] ) == $_[ 0 ];
		 return undef;
	     },
	    },
	    range => { _re => '\d+[smhdwy]',
		     _re_error =>
		     "graph range must be a number followed by [smhdwy]",
		     _doc => <<DOC,
How much time should be depicted in the Overview graph. Time must be specified
as a number followed by a letter which specifies the unit of time. Known units are:
B<s>econds, B<m>inutes, B<h>ours, B<d>days, B<w>eeks, B<y>ears.
DOC
		   },
	       },
	 detail => 
	 { 
	  _vars => [ qw(width height logarithmic unison_tolerance max_rtt strftime nodata_color) ],
          _sections => [ qw(loss_colors uptime_colors) ],
	  _mandatory => [ qw(width height) ],
	  _table     => { _columns => 2,
			  _doc => <<DOC,
The detailed display can contain several graphs of different resolution. In this
table you can specify the resolution of each graph.

Example:

 "Last 3 Hours"    3h
 "Last 30 Hours"   30h
 "Last 10 Days"    10d
 "Last 400 Days"   400d

DOC
			  1 => 
			  {
			   _doc => <<DOC,
How much time should be depicted. The format is the same as for the B<age>  parameter of the Overview section.
DOC
			   _re       => '\d+[smhdwy]',
			   _re_error =>
			   "graph age must be a number followed by [smhdwy]",
			  },
			  0 =>  
			  {
			   _doc => <<DOC,
Description of the particular resolution.
DOC
			  }
	 },
         strftime => { _doc => <<DOC,
Use posix strftime to format the timestamp in the left hand
lower corner of the detail graph
DOC
          _sub => sub {
                eval ( " 
                         POSIX::strftime('$_[0]', localtime(time)) " );
                return $@ if $@;
                return undef;
	    },
          },
	 nodata_color => {
		_re       => '[0-9a-f]{6}',
                _re_error =>  "color must be defined with in rrggbb syntax",
		_doc => "Paint the graph background in a special color when there is no data for this period because smokeping has not been running (#rrggbb)",
			},
         logarithmic      => { _doc => 'should the graphs be shown in a logarithmic scale (yes/no)',
                       _re  => '(yes|no)',
                       _re_error =>"this must either be 'yes' or 'no'",
                     },
         unison_tolerance => { _doc => "if a graph is more than this factor of the median 'max' it drops out of the unison scaling algorithm. A factor of two would mean that any graph with a max either less than half or more than twice the median 'max' will be dropped from unison scaling",
                       _sub => sub { return "tolerance must be larger than 1" if $_[0] <= 1; return undef},
                             },
         max_rtt => {    _doc => <<DOC },
Any roundtrip time larger than this value will cropped in the detail graph
DOC
	 width    => { _doc => 'How many pixels wide should detail graphs be',
		       _sub => sub {
			   return "width must be be an integer >= 10"
			     unless $_[ 0 ] >= 10
			       and int( $_[ 0 ] ) == $_[ 0 ];
			   return undef;
		       },
		     },        
	 height => {  _doc => 'How many pixels high should detail graphs be',
		    _sub => sub {
			  return "height must be an integer >= 10"
			    unless $_[ 0 ] >= 10
			      and int( $_[ 0 ] ) == $_[ 0 ];
			  return undef;
		      },
                    },
	 
         loss_colors => {
	  _table     => { _columns => 3,
			  _doc => <<DOC,
In the Detail view, the color of the median line depends
the amount of lost packets. SmokePing comes with a reasonable default setting,
but you may choose to disagree. The table below
lets you specify your own coloring.

Example:

 Loss Color   Legend
 1    00ff00    "<1"
 3    0000ff    "<3"
 100  ff0000    ">=3"

DOC
			  0 => 
			  {
			   _doc => <<DOC,
Activate when the lossrate (in percent) is larger of equal to this number
DOC
			   _re       => '\d+.?\d*',
			   _re_error =>
			   "I was expecting a number",
			  },
			  1 =>  
			  {
			   _doc => <<DOC,
Color for this range.
DOC
			   _re       => '[0-9a-f]+',
			   _re_error =>
			   "I was expecting a color of the form rrggbb",
			  },

			  2 =>  
			  {
			   _doc => <<DOC,
Description for this range.
DOC
                          }
                
	             }, # table
              }, #loss_colors
	uptime_colors => {
	  _table     => { _columns => 3,
			  _doc => <<DOC,
When monitoring a host with DYNAMIC addressing, SmokePing will keep
track of how long the machine is able to keep the same IP
address. This time is plotted as a color in the graphs
background. SmokePing comes with a reasonable default setting, but you
may choose to disagree. The table below lets you specify your own
coloring

Example:

 # Uptime      Color     Legend
 3600          00ff00   "<1h"
 86400         0000ff   "<1d"
 604800        ff0000   "<1w"
 1000000000000 ffff00   ">1w"

Uptime is in days!

DOC
			  0 => 
			  {
			   _doc => <<DOC,
Activate when uptime in days is larger of equal to this number
DOC
			   _re       => '\d+.?\d*',
			   _re_error =>
			   "I was expecting a number",
			  },
			  1 =>  
			  {
			   _doc => <<DOC,
Color for this uptime range range.
DOC
			   _re       => '[0-9a-f]{6}',
			   _re_error =>
			   "I was expecting a color of the form rrggbb",
			  },

			  2 =>  
			  {
			   _doc => <<DOC,
Description for this range.
DOC
                          }
                
	             },#table
              }, #uptime_colors
        
	   }, #detail
        }, #present
	Probes => { _sections => [ "/$KEY_RE/" ],
		    _doc => <<DOC,
The Probes Section configures Probe modules. Probe modules integrate an external ping command into SmokePing. Check the documentation of the FPing module for configuration details.
DOC
		  "/$KEY_RE/" => $PROBESTOP,
	},
	Alerts  => {
		    _doc => <<DOC,
The Alert section lets you setup loss and RTT pattern detectors. After each
round of polling, SmokePing will examine its data and determine which
detectors match. Detectors are enabled per target and get inherited by
the targets children.

Detectors are not just simple thresholds which go off at first sight
of a problem. They are configurable to detect special loss or RTT
patterns. They let you look at a number of past readings to make a
more educated decision on what kind of alert should be sent, or if an
alert should be sent at all.

The patterns are numbers prefixed with an operator indicating the type
of comparison required for a match.

The following RTT pattern detects if a target's RTT goes from constantly
below 10ms to constantly 100ms and more:

 old ------------------------------> new
 <10,<10,<10,<10,<10,>10,>100,>100,>100

Loss patterns work in a similar way, except that the loss is defined as the
percentage the total number of received packets is of the total number of packets sent.

 old ------------------------------> new
 ==0%,==0%,==0%,==0%,>20%,>20%,>=20%

Apart from normal numbers, patterns can also contain the values B<*>
which is true for all values regardless of the operator. And B<U>
which is true for B<unknown> data together with the B<==> and B<=!> operators.

Detectors normally act on state changes. This has the disadvantage, that
they will fail to find conditions which were already present when launching
smokeping. For this it is possible to write detectors that begin with the
special value B<==S> it is inserted whenever smokeping is started up.

You can write

 ==S,>20%,>20%

to detect lines that have been losing more than 20% of the packets for two
periods after startup.

Sometimes it may be that conditions occur at irregular intervals. But still
you only want to throw an alert if they occur several times within a certain
amount of times. The operator B<*X*> will ignore up to I<X> values and still
let the pattern match:

  >10%,*10*,>10%

will fire if more than 10% of the packets have been losst twice over the
last 10 samples.

A complete example

 *** Alerts ***
 to = admin\@company.xy,peter\@home.xy
 from = smokealert\@company.xy

 +lossdetect
 type = loss
 # in percent
 pattern = ==0%,==0%,==0%,==0%,>20%,>20%,>20%
 comment = suddenly there is packet loss

 +miniloss
 type = loss
 # in percent
 pattern = >0%,*12*,>0%,*12*,>0%
 comment = detected loss 3 times over the last two hours

 +rttdetect
 type = rtt
 # in milliseconds
 pattern = <10,<10,<10,<10,<10,<100,>100,>100,>100
 comment = routing messed up again ?

 +rttbadstart
 type = rtt
 # in milliseconds
 pattern = ==S,==U
 comment = offline at startup
  
DOC

	     _sections => [ '/[^\s,]+/' ],
	     _vars => [ qw(to from) ],
	     _mandatory => [ qw(to from)],
	     to => { doc => <<DOC,
Either an email address to send alerts to, or the name of a program to
execute when an alert matches. To call a program, the first character of the
B<to> value must be a pipe symbol "|". The program will the be called
whenever an alert matches, using the following 5 arguments:
B<name-of-alert>, B<target>, B<loss-pattern>, B<rtt-pattern>, B<hostname>.
You can also provide a comma separated list of addresses and programs.
DOC
			_re => '(\|.+|.+@\S+|snpp:)',
			_re_error => 'put an email address or the name of a program here',
		      },
	     from => { doc => 'who should alerts appear to be coming from ?',
		       _re => '.+@\S+',
		       _re_error => 'put an email address here',
		      },
	     '/[^\s,]+/' => {
		  _vars => [ qw(type pattern comment to) ],
		  _mandatory => [ qw(type pattern comment) ],
	          to => { doc => 'Similar to the "to" parameter on the top-level except that  it will only be used IN ADDITION to the value of the toplevel parameter. Same rules apply.',
			_re => '(\|.+|.+@\S+|snpp:)',
			_re_error => 'put an email address or the name of a program here',
		          },
		  
		  type => {
		     _doc => 'Currently the pattern types B<rtt> and B<loss> and B<matcher> are known',
		     _re => '(rtt|loss|matcher)',
                     _re_error => 'Use loss or rtt'
			  },
   	 	  pattern => {
 		     _doc => "a comma separated list of comparison operators and numbers. rtt patterns are in milliseconds, loss patterns are in percents",
		     _re => '(?:([^,]+)(,[^,]+)*|\S+\(.+\s)',
 		     _re_error => 'Could not parse pattern or matcher',
		             },
		  },
        },
       Targets => {_doc        => <<DOC,
The Target Section defines the actual work of SmokePing. It contains a hierarchical list
of hosts which mark the endpoints of the network connections the system should monitor.
Each section can contain one host as well as other sections.
DOC
		   _vars       => [ qw(probe menu title remark alerts) ],
		   _mandatory  => [ qw(probe menu title) ],
                   _order => 1,
		   _sections   => [ ( "PROBE_CONF", "/$KEY_RE/" ) ],
		   probe => { _doc => <<DOC },
The name of the probe module to be used for this host. The value of
this variable gets propagated
DOC
		   PROBE_CONF => $PROBEVARS,
		   menu => { _doc => <<DOC },
Menu entry for this section. If not set this will be set to the hostname.
DOC
                   alerts => { _doc => <<DOC },
A comma separated list of alerts to check for this target. The alerts have
to be setup in the Alerts section. Alerts are inherited by child nodes. Use
an empty alerts definition to remove inherited alerts from the current target
and its children.

DOC
		   title => { _doc => <<DOC },
Title of the page when it is displayed. This will be set to the hostname if
left empty.
DOC

		   remark => { _doc => <<DOC },
An optional remark on the current section. It gets displayed on the webpage.
DOC

		   "/$KEY_RE/" => $TARGET
		  }
            
      }
    );
    return $parser;
}

sub get_config ($$){
    my $parser = shift;
    my $cfgfile = shift;

    return $parser->parse( $cfgfile ) || die "ERROR: $parser->{err}\n";
}

sub kill_smoke ($) { 
  my $pidfile = shift;
    if (defined $pidfile){ 
        if ( -f $pidfile && open PIDFILE, "<$pidfile" ) {
            <PIDFILE> =~ /(\d+)/;
            my $pid = $1;
            kill 2, $pid if kill 0, $pid;
            sleep 3; # let it die
            die "ERROR: Can not stop running instance of SmokePing ($pid)\n"
                if kill 0, $pid;    
            close PIDFILE;
        } else {	
	    die "ERROR: Can not read pid from $pidfile: $!\n";
	};
    }
}

sub daemonize_me ($) {
  my $pidfile = shift;
    if (defined $pidfile){ 
        if (-f $pidfile ) {
            open PIDFILE, "<$pidfile";
            <PIDFILE> =~ /(\d+)/;
            close PIDFILE;
            my $pid = $1;
            die "ERROR: I Quit! Another copy of $0 ($pid) seems to be running.\n".
              "       Check $pidfile\n"
                if kill 0, $pid;
        }
    }
    print "Warning: no logging method specified. Messages will be lost.\n"
    	unless $logging;
    print "Daemonizing $0 ...\n";
    defined (my $pid = fork) or die "Can't fork: $!";
    if ($pid) {
        exit;
    } else {
        if(open(PIDFILE,">$pidfile")){
        print PIDFILE "$$\n";
        close PIDFILE;
	} else {
          warn "creating $pidfile: $!\n";
	};
	require 'POSIX.pm';
        &POSIX::setsid or die "Can't start a new session: $!";
        open STDOUT,'>/dev/null' or die "ERROR: Redirecting STDOUT to /dev/null: $!";
        open STDIN, '</dev/null' or die "ERROR: Redirecting STDIN from /dev/null: $!";
        open STDERR, '>/dev/null' or die "ERROR: Redirecting STDERR to /dev/null: $!";
	# send warnings and die messages to log
        $SIG{__WARN__} = sub { do_log ((shift)."\n") };
        $SIG{__DIE__} = sub { do_log ((shift)."\n"); exit 1 };	
    }
}

# pseudo log system object
{
	my $use_syslog;
	my $use_cgilog;
	my $use_debuglog;
        my $use_filelog;

	my $syslog_facility;
	my $syslog_priority = $DEFAULTPRIORITY;
	
	sub initialize_debuglog (){
		$use_debuglog = 1;
	}

	sub initialize_cgilog (){
		$use_cgilog = 1;
		$logging=1;
	}

	sub initialize_filelog ($){
		$use_filelog = shift;
		$logging=1;
	}
	
	sub initialize_syslog ($$) {
		my $fac = shift;
		my $pri = shift;
		$use_syslog = 1;
		$logging=1;
		die "missing facility?" unless defined $fac;
		$syslog_facility = $fac if defined $fac;
		$syslog_priority = $pri if defined $pri;
		print "Note: logging to syslog as $syslog_facility/$syslog_priority.\n";
		openlog(basename($0), 'pid', $syslog_facility);
	}

	sub do_syslog ($){
		syslog("$syslog_facility|$syslog_priority", shift);
	}

	sub do_cgilog ($){
                my $str = shift;
		print "<p>" , $str, "</p>\n";
		print STDERR $str,"\n"; # for the webserver log
	}

	sub do_debuglog ($){
		do_log(shift) if $use_debuglog;
	}

	sub do_filelog ($){
                open X,">>$use_filelog" or return;
                print X scalar localtime(time)," - ",shift,"\n";
                close X;
	}

	sub do_log (@){
		my $string = join(" ", @_);
		chomp $string; 
		do_syslog($string) if $use_syslog;
		do_cgilog($string) if $use_cgilog;
		do_filelog($string) if $use_filelog;
		print STDERR $string,"\n" unless $logging;
	}

}

###########################################################################
# The Main Program 
###########################################################################

my $RCS_VERSION = '$Id: Smokeping.pm,v 1.5 2004/10/21 21:10:51 oetiker Exp $';

sub load_cfg ($) { 
    my $cfgfile = shift;
    my $cfmod = (stat $cfgfile)[9] || die "ERROR: calling stat on $cfgfile: $!\n";
    # when running under speedy this will prevent reloading on every run
    # if cfgfile has been modified we will still run.
    if (not defined $cfg or $cfg->{__last} < $cfmod ){
        $cfg = undef;
        my $parser = get_parser;
	$cfg = get_config $parser, $cfgfile;       
        $cfg->{__parser} = $parser;
	$cfg->{__last} = $cfmod;
	$cfg->{__cfgfile} = $cfgfile;
        $probes = undef;
	$probes = load_probes $cfg;
	$cfg->{__probes} = $probes;
	init_alerts $cfg if $cfg->{Alerts};
      	init_target_tree $cfg, $probes, $cfg->{Targets}{probe}, $cfg->{Targets}, $cfg->{General}{datadir}, $cfg->{Targets}{PROBE_CONF},$cfg->{Targets}{alerts},undef; 
    }    
}


sub makepod ($){
    my $parser = shift;
    my $e='=';
    print <<POD;

${e}head1 NAME

smokeping_config - Reference for the SmokePing Config File

${e}head1 OVERVIEW

SmokePing takes its configuration from a single central configuration file.
Its location must be hardcoded in the smokeping script and smokeping.cgi.

The contents of this manual is generated directly from the configuration
file parser.

The Parser for the Configuration file is written using David Schweikers
ParseConfig module. Read all about it in L<ISG::ParseConfig>.

The Configuration file has a tree-like structure with section headings at
various levels. It also contains variable assignments and tables.

${e}head1 REFERENCE

The text below describes the syntax of the SmokePing configuration file.

POD

    print $parser->makepod;
    print <<POD;

${e}head1 COPYRIGHT

Copyright (c) 2001-2003 by Tobias Oetiker. All right reserved.

${e}head1 LICENSE

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

${e}head1 AUTHOR

Tobias Oetiker E<lt>tobi\@oetiker.chE<gt>

${e}cut
POD
    exit 0;


}
sub cgi ($) {
    $cgimode = 'yes';
    # make sure error are shown in appropriate manner even when running from speedy
    # and thus not getting BEGIN re-executed.
    if ($ENV{SERVER_SOFTWARE}) {
        $SIG{__WARN__} = sub { print "Content-Type: text/plain\n\n".(shift)."\n"; };
        $SIG{__DIE__} = sub { print "Content-Type: text/plain\n\n".(shift)."\n"; exit 1 }
    };
    umask 022;
    load_cfg shift;
    my $q=new CGI;
    print $q->header(-type=>'text/html',
                     -expires=>'+'.($cfg->{Database}{step}).'s',
                     -charset=> ( $cfg->{Presentation}{charset} || 'iso-8859-15')                   
                     );
    if ($ENV{SERVER_SOFTWARE}) {
        $SIG{__WARN__} = sub { print "<pre>".(shift)."</pre>"; };
        $SIG{__DIE__} = sub { print "<pre>".(shift)."</pre>"; exit 1 }
    };
    initialize_cgilog();
    if ($q->param(-name=>'secret') && $q->param(-name=>'target') ) {
	update_dynaddr $cfg,$q;
    } else {
	display_webpage $cfg,$q;
    }
}

    
sub gen_page  ($$$);
sub gen_page  ($$$) {
    my ($cfg, $tree, $open) = @_;
    my ($q, $name, $page);

    $q = bless \$q, 'dummyCGI';

    $name = @$open ? join('.', @$open) . ".html" : "index.html";

    die "Can not open $cfg-{General}{pagedir}/$name for writing: $!" unless
      open PAGEFILE, ">$cfg->{General}{pagedir}/$name";

    my $step = $probes->{$tree->{probe}}->step();

    $page = fill_template
	($cfg->{Presentation}{template},
	 {
	  menu => target_menu($cfg->{Targets},
			      [@$open], #copy this because it gets changed
			      "", ".html"),
	  title => $tree->{title},
	  remark => ($tree->{remark} || ''),
	  overview => get_overview( $cfg,$q,$tree,$open ),
	  body => get_detail( $cfg,$q,$tree,$open ),
	  target_ip => ($tree->{host} || ''),
	  owner => $cfg->{General}{owner},
	  contact => $cfg->{General}{contact},
	  author => '<A HREF="http://tobi.oetiker.ch/">Tobi&nbsp;Oetiker</A>',
	  smokeping => '<A HREF="http://people.ee.ethz.ch/~oetiker/webtools/smokeping/counter.cgi/'.$VERSION.'">SmokePing-'.$VERSION.'</A>',
	  step => $step,
	  rrdlogo => '<A HREF="http://people.ee.ethz.ch/~oetiker/webtools/rrdtool/"><img border="0" src="'.$cfg->{General}{imgurl}.'/rrdtool.png"></a>',
	  smokelogo => '<A HREF="http://people.ee.ethz.ch/~oetiker/webtools/smokeping/counter.cgi/'.$VERSION.'"><img border="0" src="'.$cfg->{General}{imgurl}.'/smokeping.png"></a>',
	 });

    print PAGEFILE $page;
    close PAGEFILE;

    foreach my $key (keys %$tree) {
	my $value = $tree->{$key};
	next unless ref($value) eq 'HASH';
	gen_page($cfg, $value, [ @$open, $key ]);
    }
}

sub makestaticpages ($$) {
  my $cfg = shift;
  my $dir = shift;

  # If directory is given, override current values (pagedir and and
  # imgurl) so that all generated data is in $dir. If $dir is undef,
  # use values from config file.
  if ($dir) {
    mkdir $dir, 0755 unless -d $dir;
    $cfg->{General}{pagedir} = $dir;
    $cfg->{General}{imgurl} = '.';
  }
  
  die "ERROR: No pagedir defined for static pages\n"
        unless $cfg->{General}{pagedir};
  # Logos.
  gen_imgs($cfg);

  # Iterate over all targets.
  my $tree = $cfg->{Targets};
  gen_page($cfg, $tree, []);
}

sub pages ($) {
  my ($config) = @_;
  umask 022;
  load_cfg($config);
  makestaticpages($cfg, undef);
}
      
sub main ($) {
    $cgimode = 0;
    umask 022;
    my $cfgfile = shift;
    $opt{filter}=[];
    GetOptions(\%opt, 'version', 'email', ,'man','help','logfile=s','static-pages:s', 'debug-daemon',
		      'nosleep', 'makepod','debug','restart', 'filter=s', 'nodaemon|nodemon') or pod2usage(2);
    if($opt{version})  { print "$RCS_VERSION\n"; exit(0) };
    if($opt{man})      {  pod2usage(-verbose => 2); exit 0 };
    if($opt{help})     {  pod2usage(-verbose => 1); exit 0 };
    if($opt{makepod})  { makepod(get_parser) ; exit 0}; 
    initialize_debuglog if $opt{debug} or $opt{'debug-daemon'};
    load_cfg $cfgfile;
    if(defined $opt{'static-pages'}) { makestaticpages $cfg, $opt{'static-pages'}; exit 0 };
    if($opt{email})    { enable_dynamic $cfg, $cfg->{Targets},"",""; exit 0 };
    if($opt{restart})  { kill_smoke $cfg->{General}{piddir}."/smokeping.pid";};
    if($opt{logfile})      { initialize_filelog($opt{logfile}) };
    if (not keys %$probes) {
    	do_log("No probes defined, exiting.");
	exit 1;
    }
    unless ($opt{debug} or $opt{nodaemon}) {
    	if (defined $cfg->{General}{syslogfacility}) {
		initialize_syslog($cfg->{General}{syslogfacility}, 
				  $cfg->{General}{syslogpriority});
	}
    	daemonize_me $cfg->{General}{piddir}."/smokeping.pid";
    }
    do_log "Launched successfully";

    my $myprobe;
    my $forkprobes = $cfg->{General}{concurrentprobes} || 'yes';
    if ($forkprobes eq "yes" and keys %$probes > 1 and not $opt{debug}) {
    	my %probepids;
	my $pid;
	do_log("Entering multiprocess mode.");
    	for my $p (keys %$probes) {
		if ($probes->{$p}->target_count == 0) {
			do_log("No targets defined for probe $p, skipping.");
			next;
		}
		my $sleep_count = 0;
		do {
			$pid = fork;
			unless (defined $pid) {
				do_log("Fatal: cannot fork: $!");
				die "bailing out" 
					if $sleep_count++ > 6;
				sleep 10;
			}
		} until defined $pid;
		$myprobe = $p;
		goto KID unless $pid; # child skips rest of loop
		do_log("Child process $pid started for probe $myprobe.");
		$probepids{$pid} = $myprobe;
	}
	# parent
	do_log("All probe processes started succesfully.");
	my $exiting = 0;
	for my $sig (qw(INT TERM)) {
		$SIG{$sig} = sub {
			do_log("Got $sig signal, terminating child processes.");
			$exiting = 1;
			kill $sig, $_ for keys %probepids;
			my $now = time;
			while(keys %probepids) { # SIGCHLD handler below removes the keys
				if (time - $now > 2) {
					do_log("Can't terminate all child processes, giving up.");
					exit 1;
				}
				sleep 1;
			}
			do_log("All child processes succesfully terminated, exiting.");
			exit 0;
		}
	};
	$SIG{CHLD} = sub {
		while ((my $dead = waitpid(-1, WNOHANG)) > 0) {
			my $p = $probepids{$dead};
			$p = 'unknown' unless defined $p;
			do_log("Child process $dead (probe $p) exited unexpectedly with status $?.")
				unless $exiting;
			delete $probepids{$dead};
		}
	};
	sleep while 1; # just wait for the signals
	do_log("Exiting abnormally - this should not happen.");
	exit 1; # not reached
    } else {
    	if ($forkprobes ne "yes") {
		do_log("Not entering multiprocess mode because the 'concurrentprobes' variable is not set.");
    		for my $p (keys %$probes) {
			for my $what (qw(offset step)) {
				do_log("Warning: probe-specific parameter '$what' ignored for probe $p in single-process mode."	)
					if defined $cfg->{Probes}{$p}{$what};
			}
		}
	} elsif ($opt{debug}) {
    		do_debuglog("Not entering multiprocess mode with '--debug'. Use '--debug-daemon' for that.")
	} elsif (keys %$probes == 1) {
		do_log("Not entering multiprocess mode for just a single probe.");
		$myprobe = (keys %$probes)[0]; # this way we won't ignore a probe-specific step parameter
	}
	for my $sig (qw(INT TERM)) {
		$SIG{$sig} = sub {
			do_log("Got $sig signal, terminating.");
			exit 1;
		}
	}
    }
KID:
    my $offset;
    my $step; 
    if (defined $myprobe) {
    	$offset = $probes->{$myprobe}->offset || 'random';
	$step = $probes->{$myprobe}->step;
	$0 .= " [$myprobe]" unless defined $cfg->{General}{changeprocessnames}
	                    and $cfg->{General}{changeprocessnames} eq "no";
    } else {
	$offset = $cfg->{General}{offset} || 'random';
	$step = $cfg->{Database}{step};
    }
    if ($offset eq 'random'){
	  $offset = int(rand($step));
    } else {   
          $offset =~ s/%$//;
          $offset = $offset / 100 * $step;
    }
    for (keys %$probes) {
    	next if defined $myprobe and $_ ne $myprobe;
    	# fill this in for report_probes() below
    	$probes->{$_}->offset_in_seconds($offset); # this is just for humans
	if ($opt{debug} or $opt{'debug-daemon'}) {
		$probes->{$_}->debug(1) if $probes->{$_}->can('debug');
	}
    }

    report_probes($probes, $myprobe);

    while (1) {
	unless ($opt{nosleep} or $opt{debug}) {
		my $sleeptime = $step - (time-$offset) % $step;
		if (defined $myprobe) {
        		$probes->{$myprobe}->do_debug("Sleeping $sleeptime seconds.");
		} else {
        		do_debuglog("Sleeping $sleeptime seconds.");
		}
		sleep $sleeptime;
	}
        my $now = time;
	run_probes $probes, $myprobe; # $myprobe is undef if running without 'concurrentprobes'
	update_rrds $cfg, $probes, $cfg->{Targets}{probe}, $cfg->{Targets}, $cfg->{General}{datadir}, $myprobe;
	exit 0 if $opt{debug};
        my $runtime = time - $now;
	if ($runtime > $step) {
        	my $warn = "WARNING: smokeping took $runtime seconds to complete 1 round of polling. ".
             	"It should complete polling in $step seconds. ".
             	"You may have unresponsive devices in your setup.\n";
		if (defined $myprobe) {
        		$probes->{$myprobe}->do_log($warn);
		} else {
        		do_log($warn);
		}
	}
    }
}

sub gen_imgs ($){

  my $cfg = shift;
  if (not -r $cfg->{General}{imgcache}."/rrdtool.png"){
open W, ">".$cfg->{General}{imgcache}."/rrdtool.png" 
   or do { warn "WARNING: creating $cfg->{General}{imgcache}/rrdtool.png: $!\n"; return 0 };
print W unpack ('u', <<'UUENC');
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
GK@CL_D-K0>[]"@'[?,KT_\<_ *X%"4UQ:&PM     $E%3D2N0F""
UUENC
close W;
}

  if (not -r $cfg->{General}{imgcache}."/smokeping.png"){
open W, ">".$cfg->{General}{imgcache}."/smokeping.png" 
   or do { warn "WARNING: creating $cfg->{General}{imgcache}/smokeping.png: $!\n"; return 0};
print W unpack ('u', <<'UUENC');
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
*``!)14Y$KD)@@@``
UUENC
close W;
}
}


=head1 NAME

Smokeping.pm - SmokePing Perl Module

=head1 OVERVIEW

Almost all SmokePing functionality sits in this Module.
The programs B<smokeping> and B<smokeping.cgi> are merely
figure heads allowing to hardcode some pathnames.

If you feel like documenting what is happening within this library you are
most welcome todo so.

=head1 COPYRIGHT

Copyright (c) 2001 by Tobias Oetiker. All right reserved.

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

Tobias Oetiker E<lt>tobi\@oetiker.chE<gt>

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
