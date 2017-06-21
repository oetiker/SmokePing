# -*- perl -*-
package Smokeping;

use strict;
use CGI;
use Getopt::Long;
use Pod::Usage;
use Digest::MD5 qw(md5_base64);
use SNMP_util;
use SNMP_Session;
# enable locale??
#use locale;
use POSIX qw(fmod locale_h signal_h sys_wait_h);
use Smokeping::Config;
use RRDs;
use Sys::Syslog qw(:DEFAULT setlogsock);
use Sys::Hostname;
use Smokeping::Colorspace;
use Smokeping::Master;
use Smokeping::Slave;
use Smokeping::RRDhelpers;
use Smokeping::Graphs;
use URI::Escape;
use Time::HiRes;

setlogsock('unix')
   if grep /^ $^O $/xo, ("linux", "openbsd", "freebsd", "netbsd");

# make sure we do not end up with , in odd places where one would expect a '.'
# we set the environment variable so that our 'kids' get the benefit too

my $xssBadRx = qr/[<>%&'";]/;

$ENV{'LC_NUMERIC'}='C';
if (setlocale(LC_NUMERIC,"") ne "C") {
    if ($ENV{'LC_ALL'} eq 'C') {
        # This has got to be a bug in perl/mod_perl, apache or libc
        die("Your internalization implementation on your operating system is "
          . "not responding to your setup of LC_ALL to \"C\" as LC_NUMERIC is "
          . "coming up as \"" . setlocale(LC_NUMERIC, "") . "\" leaving "
          . "smokeping unable to compare numbers...");
    }
    elsif ($ENV{'LC_ALL'} ne "") {
        # This error is most likely setup related and easy to fix with proper 
        # setup of the operating system or multilanguage locale setup.  Hint,
        # setting LANG is better than setting LC_ALL...
        die("Resetting LC_NUMERIC failed probably because your international "
          . "setup of the LC_ALL to \"". $ENV{'LC_ALL'} . "\" is overridding "
          . "LC_NUMERIC.  Setting LC_ALL is not compatible with smokeping...");
    }
    else {
        # This is pretty nasty to figure out.  Seems there are still lots
        # of bugs in LOCALE behavior and if you get this error, you are
        # affected by it.  The worst is when "setlocale" is reading the
        # environment variables of your webserver and not reading the PERL
        # %ENV array like it should.
        die("Something is wrong with the internalization setup of your "
          . "operating system, webserver, or the perl plugin to your webserver "
          . "(like mod_perl) and smokeping can not compare numbers correctly.  "
          . "On unix, check your /etc/locale.gen and run sudo locale-gen, set "
          . "LC_NUMERIC in your perl plugin config or even your webserver "
          . "startup script to potentially fix or work around the problem...");
    }
}


use File::Basename;
use Smokeping::Examples;
use Smokeping::RRDtools;

# globale persistent variables for speedy
use vars qw($cfg $probes $VERSION $havegetaddrinfo $cgimode);

$VERSION="2.006000";

# we want opts everywhere
my %opt;

BEGIN {
  $havegetaddrinfo = 0;
  eval 'use Socket6';
  $havegetaddrinfo = 1 unless $@;
}

my $DEFAULTPRIORITY = 'info'; # default syslog priority

my $logging = 0; # keeps track of whether we have a logging method enabled

sub find_libdir {
    # find the directory where the probe and matcher modules are located
    # by looking for 'Smokeping/probes/FPing.pm' in @INC
    # 
    # yes, this is ugly. Suggestions welcome.
    for (@INC) {
          -f "$_/Smokeping/probes/FPing.pm" or next;
          return $_;
    }
    return undef;
}
                
sub do_log(@);
sub load_probe($$$$);

sub dummyCGI::param {
    return wantarray ? () : "";
}

sub dummyCGI::script_name {
    return "sorry_no_script_name_when_running_offline";
}

sub load_probes ($){
    my $cfg = shift;
    my %prbs;
    foreach my $probe (keys %{$cfg->{Probes}}) {
        my @subprobes = grep { ref $cfg->{Probes}{$probe}{$_} eq 'HASH' } keys %{$cfg->{Probes}{$probe}};
        if (@subprobes) {
                my $modname = $probe;
                for my $subprobe (@subprobes) {
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
        # just in case, make sure we have the module loaded. unless
        # we are running as slave, this will already be the case
        # after reading the config file
        eval 'require Smokeping::probes::'.$modname;
        die "$@\n" if $@;
        my $rv;        
        eval '$rv = Smokeping::probes::'.$modname.'->new( $properties,$cfg,$name);';
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

sub cgiurl {
    my ($q, $cfg) = @_;
    my %url_of = (
        absolute => $cfg->{General}{cgiurl},
        relative => q{},
        original => $q->script_name,
    );
    my $linkstyle = $cfg->{General}->{linkstyle};
    die('unknown value for $cfg->{General}->{linkstyle}: '
                         . $linkstyle
    ) unless exists $url_of{$linkstyle};
    return $url_of{$linkstyle};
}

sub hierarchy ($){
    my $q = shift;
    my $hierarchy = '';
    my $h = $q->param('hierarchy');
    if ($q->param('hierarchy')){
       $h =~ s/$xssBadRx/_/g;
       $hierarchy = 'hierarchy='.$h.';';
    }; 
    return $hierarchy;
}        
sub lnk ($$) {
    my ($q, $path) = @_;
    if ($q->isa('dummyCGI')) {
        return $path . ".html";
    } else {
        return cgiurl($q, $cfg) . "?".hierarchy($q)."target=" . $path;
    }
}

sub dyndir ($) {
    my $cfg = shift;
    return $cfg->{General}{dyndir} || $cfg->{General}{datadir};
}

sub make_cgi_directories {
    my $targets = shift;
    my $dir = shift;
    my $perms = shift;
    while (my ($k, $v) = each %$targets) {
        next if ref $v ne "HASH";
        if ( ! -d "$dir/$k" ) {
            my $saved = umask 0;
            mkdir "$dir/$k", oct($perms);
            umask $saved;
        }
        make_cgi_directories($targets->{$k}, "$dir/$k", $perms);
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
        $step =~ s/$xssBadRx/_/g; 
        return "Error: Unknown target $step" 
          unless defined $targetptr->{$step};
        $targetptr =  $targetptr->{$step};
    };
    return "Error: Invalid target or secret" 
      unless defined $targetptr->{host} and
      $targetptr->{host} eq "DYNAMIC/${secret}";
    my $file = dyndir($cfg);
    for (0..$#target-1) {
        $file .= "/" . $target[$_];
        ( -d $file ) || mkdir $file, 0755;
    }
    $file.= "/" . $target[-1];
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
    if ($cfg->{General}{mailhost} and  
        my $smtp = Net::SMTP->new([split /\s*,\s*/, $cfg->{General}{mailhost}],Timeout=>5) ){
	$smtp->auth($cfg->{General}{mailuser}, $cfg->{General}{mailpass})
	    if ($cfg->{General}{mailuser} and $cfg->{General}{mailpass});
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
    } else {
        warn "ERROR: not sending mail to $to, as all methodes failed\n";
    }
}

sub sendsnpp ($$){
   my $to = shift;
   my $msg = shift;
   if ($cfg->{General}{snpphost} and
        my $snpp = Net::SNPP->new($cfg->{General}{snpphost}, Timeout => 60)){
        $snpp->send( Pager => $to,
                     Message => $msg) || do_debuglog("ERROR - ". $snpp->message);
        $snpp->quit;
    } else {
        warn "ERROR: not sending page to $to, as all SNPP setup failed\n";
    }
}

sub min ($$) {
        my ($a, $b) = @_;
        return $a < $b ? $a : $b;
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
            die "ERROR: matcher $matcher: all matchers start with a capital letter since version 2.0\n"
                unless $matcher =~ /^[A-Z]/;
            eval 'require Smokeping::matchers::'.$matcher;
            die "Matcher '$matcher' could not be loaded: $@\n" if $@;
            my $hand;
            eval "\$hand = Smokeping::matchers::$matcher->new($arg)";
            die "ERROR: Matcher '$matcher' could not be instantiated\nwith arguments $arg:\n$@\n" if $@;
            $x->{minlength} = $hand->Length;
            $x->{maxlength} = $x->{minlength};
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
            $x->{minlength} = scalar grep /^[!=><]/, @ops;
            $x->{maxlength} = $x->{minlength};
            my $multis = scalar grep /^[*]/, @ops;
            my $it = "";
            for(1..$multis){
                my $ind = "    " x ($_-1);
                my $extra = "";
                for (1..$_-1) {
                        $extra .= "-\$i$_";
                }
                $sub .= <<FOR;
$ind        my \$i$_;
$ind        for(\$i$_=0; \$i$_ < min(\$maxlength$extra,\$imax$_); \$i$_++){
FOR
            };
            my $i = - $x->{maxlength};
            my $incr = 0;
            for (@ops) {
                my $extra = "";
                $it = "    " x $multis;
                for(1..$multis){
                    $extra .= "-\$i$_";
                };
                /^(==|!=|<|>|<=|>=|\*)(\d+(?:\.\d*)?|U|S|\d*\*)(%?)(?:(<|>|<=|>=)(\d+(?:\.\d*)?)(%?))?$/
                    or die "ERROR: Alert $al pattern entry '$_' is invalid\n";
                my $op = $1;
                my $value = $2;
                my $perc = $3;
                my $op2 = $4;
                my $value2 = $5;
                my $perc2 = $6;
                if ($op eq '*') {
                    if ($value =~ /^([1-9]\d*)\*$/) {
                        $value = $1;
                        $x->{maxlength} += $value;
                        $sub_front .= "        my \$imax$multis = min(\@\$y - $x->{minlength}, $value);\n";
                        $sub_back .=  "\n";
                        $sub .= <<FOR;
$it        last;
$it    }
$it    return 0 if \$i$multis >= min(\$maxlength$extra,\$imax$multis);
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
$it                        and \$y->[$i$extra] $op $value
IF
                    if ($op2){
                       if ( $x->{type} eq 'loss') {
                          die "ERROR: loss should be specified in % (alert $al pattern)\n" unless $perc2 eq "%";
                       } elsif ( $x->{type} eq 'rtt' ) {
                          $value2 /= 1000;
                       }                    
                       $sub  .= <<IF;
$it                        and \$y->[$i$extra] $op2 $value2            
IF
                    }
                    $sub .= "$it                             ;";
                }
                $i++;
            }
            $sub_front .= "$it        my \$minlength = $x->{minlength};\n";
            $sub_front .= "$it        my \$maxlength = $x->{maxlength};\n";
            $sub_front .= "$it        next if scalar \@\$y < \$minlength ;\n";
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

sub add_targets ($$$$);
sub add_targets ($$$$){
    my $cfg = shift;   
    my $probes = shift;
    my $tree = shift;
    my $name = shift;
    die "Error: Invalid Probe: $tree->{probe}" unless defined $probes->{$tree->{probe}};
    my $probeobj = $probes->{$tree->{probe}};
    foreach my $prop (keys %{$tree}) {
        if (ref $tree->{$prop} eq 'HASH'){
            add_targets $cfg, $probes, $tree->{$prop}, "$name/$prop";
        }
        if ($prop eq 'host' and ( check_filter($cfg,$name) and $tree->{$prop} !~ m|^/| )) {
            if($tree->{host} =~ /^DYNAMIC/) {
                $probeobj->add($tree,$name);
            } else {
                $probeobj->add($tree,$tree->{host});
            }
        }
    }
}


sub init_target_tree ($$$$); # predeclare recursive subs
sub init_target_tree ($$$$) {
    my $cfg = shift;
    my $probes = shift;
    my $tree = shift;
    my $name = shift;
    my $hierarchies = $cfg->{__hierarchies};
    die "Error: Invalid Probe: $tree->{probe}" unless defined $probes->{$tree->{probe}};
    my $probeobj = $probes->{$tree->{probe}};

    if ($tree->{alerts}){
        die "ERROR: no Alerts section\n"
            unless exists $cfg->{Alerts};
        $tree->{alerts} = [ split(/\s*,\s*/, $tree->{alerts}) ] unless ref $tree->{alerts} eq 'ARRAY';
        $tree->{fetchlength} = 0;
        foreach my $al (@{$tree->{alerts}}) {
            die "ERROR: alert $al ($name) is not defined\n"
                unless defined $cfg->{Alerts}{$al};
            $tree->{fetchlength} = $cfg->{Alerts}{$al}{maxlength}
                if $tree->{fetchlength} < $cfg->{Alerts}{$al}{maxlength};
        }
    };
    # fill in menu and title if missing
    $tree->{menu} ||=  $tree->{host} || "unknown";
    $tree->{title} ||=  $tree->{host} || "unknown";
    my $real_path = $name;
    my $dataroot = $cfg->{General}{datadir};
    $real_path =~ s/^$dataroot\/*//;
    my @real_path = split /\//, $real_path;

    foreach my $prop (keys %{$tree}) {
        if (ref $tree->{$prop} eq 'HASH'){
            if (not -d $name and not $cgimode) {
                mkdir $name, 0755 or die "ERROR: mkdir $name: $!\n";
            };

            if (defined $tree->{$prop}{parents}){
                for my $parent (split /\s/, $tree->{$prop}{parents}){
                    my($hierarchy,$path)=split /:/,$parent,2;
                    die "ERROR: unknown hierarchy $hierarchy in $name. Make sure it is listed in Presentation->hierarchies.\n"
                        unless $cfg->{Presentation}{hierarchies} and $cfg->{Presentation}{hierarchies}{$hierarchy};
                    my @path = split /\/+/, $path;
                    shift @path; # drop empty root element;
                    if ( not exists $hierarchies->{$hierarchy} ){
                        $hierarchies->{$hierarchy} = {};
                    };
                    my $point = $hierarchies->{$hierarchy};
                    for my $item (@path){
                        if (not exists $point->{$item}){
                            $point->{$item} = {};
                        }
                        $point = $point->{$item};
                    };
                    $point->{$prop}{__tree_link} = $tree->{$prop};
	            $point->{$prop}{__real_path} = [ @real_path,$prop ];
                }
            }               
            init_target_tree $cfg, $probes, $tree->{$prop}, "$name/$prop";
        }
        if ($prop eq 'host' and check_filter($cfg,$name) and $tree->{$prop} !~ m|^/|) {           
            # print "init $name\n";
            my $step = $probeobj->step();
            # we have to do the add before calling the _pings method, it won't work otherwise
            my $pings = $probeobj->_pings($tree);
            my @slaves = ("");
    
            if ($tree->{slaves}){
                push @slaves, split /\s+/, $tree->{slaves};
            };
            for my $slave (@slaves){
                die "ERROR: slave '$slave' is not defined in the '*** Slaves ***' section!\n"
                        unless $slave eq '' or defined $cfg->{Slaves}{$slave};
                my $s = $slave ? "~".$slave : "";
                my @create =    
                        ($name.$s.".rrd", "--start",(time-1),"--step",$step,
                              "DS:uptime:GAUGE:".(2*$step).":0:U",
                              "DS:loss:GAUGE:".(2*$step).":0:".$pings,
                              "DS:median:GAUGE:".(2*$step).":0:U",
                              (map { "DS:ping${_}:GAUGE:".(2*$step).":0:U" }
                                                                          1..$pings),
                              (map { "RRA:".(join ":", @{$_}) } @{$cfg->{Database}{_table}} ));
                if (not -f $name.$s.".rrd"){
                    unless ($cgimode) {
                        do_debuglog("Calling RRDs::create(@create)");
                        RRDs::create(@create);
                        my $ERROR = RRDs::error();
                        do_log "RRDs::create ERROR: $ERROR\n" if $ERROR;
                    }
                } else {
                    shift @create; # remove the filename
                    my ($fatal, $comparison) = Smokeping::RRDtools::compare($name.$s.".rrd", \@create);
                    die("Error: RRD parameter mismatch ('$comparison'). You must delete $name$s.rrd or fix the configuration parameters.\n")
                            if $fatal;
                    warn("Warning: RRD parameter mismatch('$comparison'). Continuing anyway.\n") if $comparison and not $fatal;
                    Smokeping::RRDtools::tuneds($name.$s.".rrd", \@create);                 
                }
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
        enable_dynamic $cfg, $tree->{$prop},"$path$prop.",$email if ref $tree->{$prop} eq 'HASH';
    }
};

sub get_tree($$){
    my $cfg = shift;
    my $open = shift;
    my $tree = $cfg->{Targets};
    for (@{$open}){
        $tree =  $tree->{$_};
    }
    return $tree;
}

sub target_menu($$$$;$);
sub target_menu($$$$;$){
    my $tree = shift;
    my $open = shift;
    $open = [@$open]; # make a copy 
    my $path = shift;
    my $filter = shift;
    my $suffix = shift || '';
    my $print;
    my $current =  shift @{$open} || "";
    my @hashes;
    foreach my $prop (sort {exists $tree->{$a}{_order} ? ($tree->{$a}{_order} <=> $tree->{$b}{_order}) : ($a cmp $b)} 
                      grep {  ref $tree->{$_} eq 'HASH' and not /^__/ }
                      keys %$tree) {
            push @hashes, $prop;
    }
    return wantarray ? () : "" unless @hashes;

	$print .= qq{<ul class="menu">\n}
		unless $filter;

	my @matches;
    for my $key (@hashes) {

		my $menu = $key;
        my $title = $key;
        my $hide;
        my $host;
        my $menuextra;
        if ($tree->{$key}{__tree_link} and $tree->{$key}{__tree_link}{menu}){
    		$menu = $tree->{$key}{__tree_link}{menu};
    		$title = $tree->{$key}{__tree_link}{title};
    		$host = $tree->{$key}{__tree_link}{host};
            $menuextra = $tree->{$key}{__tree_link}{menuextra};
            next if $tree->{$key}{__tree_link}{hide} and $tree->{$key}{__tree_link}{hide} eq 'yes';
        } elsif ($tree->{$key}{menu}) {	
	        $menu = $tree->{$key}{menu};
	        $title = $tree->{$key}{title};
    		$host = $tree->{$key}{host};
            $menuextra = $tree->{$key}{menuextra};
            next if $tree->{$key}{hide} and $tree->{$key}{hide} eq 'yes';
        }

        # no menuextra for multihost   
        if (not $host or $host =~ m|^/|){
            $menuextra = undef;
        }

		my $class = 'menuitem';
		my $menuclass = "menulink";
   	    if ($key eq $current ){
			if ( @$open ) {
         		$class = 'menuopen';
    		} else {
   	            $class = 'menuactive';
                $menuclass = "menulinkactive";
            }
   	    };
		if ($filter){
			if (($menu and $menu =~ /$filter/i) or ($title and $title =~ /$filter/i)){
				push @matches, ["$path$key$suffix",$menu,$class,$menuclass];
			};
			push @matches, target_menu($tree->{$key}, $open, "$path$key.",$filter, $suffix);
		}
		else {
             if ($menuextra){
                 $menuextra =~ s/{HOST}/#$host/g;
                 $menuextra =~ s/{CLASS}/$menuclass/g;
                 $menuextra =~ s/{HASH}/#/g;
                 $menuextra =~ s/{HOSTNAME}/$host/g;
                 $menuextra = '&nbsp;'.$menuextra;
             } else {
                 $menuextra = '';
             }

          	$print .= qq{<li class="$class"><a class="$menuclass" href="$path$key$suffix">$menu</a>\n};
     	    if ($key eq $current){
        	    my $prline = target_menu $tree->{$key}, $open, "$path$key.",$filter, $suffix;
	            $print .= $prline
   		           if $prline;
        	}
            $print .= "</li>";
		}
    }
    $print .= "</ul>\n" unless $filter;
	if ($filter){
		if (wantarray()){
			return @matches;
		}
		else {
			$print .= qq{<ul class="menu">\n};
			for my $entry (sort {$a->[1] cmp $b->[1] } grep {ref $_ eq 'ARRAY'} @matches) {
				my ($href,$menu,$class,$menuclass) = @{$entry};
				$print .= qq{<li class="$class"><a class="$menuclass" href="$href">$menu</a></li>\n};
			}
			$print .= "</ul>\n";
		}
	}
    return $print;
};


sub fill_template ($$;$){
    my $template = shift;
    my $subst = shift;
    my $data = shift;
    if ($template){
        my $line = $/;
        undef $/;
        open I, $template or return undef;
        $data = <I>;
        close I;
        $/ = $line;
    }
    foreach my $tag (keys %{$subst}) {
	my $replace = $subst->{$tag} || '';
        $data =~ s/<##${tag}##>/$replace/g;
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

sub calc_stddev {
    my $rrd = shift;
    my $id = shift;
    my $pings = shift;    
    my @G = map {("DEF:pin${id}p${_}=${rrd}:ping${_}:AVERAGE","CDEF:p${id}p${_}=pin${id}p${_},UN,0,pin${id}p${_},IF")} 1..$pings;
    push @G, "CDEF:pings${id}="."$pings,p${id}p1,UN,".join(",",map {"p${id}p$_,UN,+"} 2..$pings).",-";
    push @G, "CDEF:m${id}="."p${id}p1,".join(",",map {"p${id}p$_,+"} 2..$pings).",pings${id},/";
    push @G, "CDEF:sdev${id}=p${id}p1,m${id},-,DUP,*,".join(",",map {"p${id}p$_,m${id},-,DUP,*,+"} 2..$pings).",pings${id},/,SQRT";
    return @G;
}    

sub brighten_webcolor {
    my $web = shift;
    my @rgb = Smokeping::Colorspace::web_to_rgb($web);
    my @hsl = Smokeping::Colorspace::rgb_to_hsl(@rgb);
    $hsl[2] = (1 - $hsl[2]) * (2/3) + $hsl[2];
    @rgb = Smokeping::Colorspace::hsl_to_rgb(@hsl);
    return Smokeping::Colorspace::rgb_to_web(@rgb);
}

sub get_overview ($$$$){
    my $cfg = shift;
    my $q = shift;
    my $tree = shift;
    my $open = shift;

    my $page ="";

    my $date = $cfg->{Presentation}{overview}{strftime} ? 
        POSIX::strftime($cfg->{Presentation}{overview}{strftime},
                        localtime(time)) : scalar localtime(time);

    if ( $RRDs::VERSION >= 1.199908 ){
            $date =~ s|:|\\:|g;
    }
    foreach my $prop (sort {exists $tree->{$a}{_order} ? ($tree->{$a}{_order} <=> $tree->{$b}{_order}) : ($a cmp $b)} 
                      grep {  ref $tree->{$_} eq 'HASH' and not /^__/ }
                      keys %$tree) {
        my @slaves;

        my $phys_tree = $tree->{$prop};
	my $phys_open = $open;
	my $dir = "";
	if ($tree->{$prop}{__tree_link}){
            $phys_tree = $tree->{$prop}{__tree_link};
	    $phys_open = [ @{$tree->{$prop}{__real_path}} ];
	    pop @$phys_open;
	}

	next unless $phys_tree->{host};
	next if $phys_tree->{hide} and $phys_tree->{hide} eq 'yes';

        if (not $phys_tree->{nomasterpoll} or $phys_tree->{nomasterpoll} eq 'no'){
            @slaves  = ("");
        };

	if ($phys_tree->{host} =~ m|^/|){            # multi host syntax
            @slaves = split /\s+/, $phys_tree->{host};
        }
        elsif ($phys_tree->{slaves}){
            push @slaves, split /\s+/,$phys_tree->{slaves};       
        } 

        next if 0 == @slaves;

        for (@$phys_open) {
            $dir .= "/$_";
            mkdir $cfg->{General}{imgcache}.$dir, 0755 
                unless -d  $cfg->{General}{imgcache}.$dir;
            die "ERROR: creating  $cfg->{General}{imgcache}$dir: $!\n"
                unless -d  $cfg->{General}{imgcache}.$dir;
        }

        my @G; #Graph 'script'
        my $max =  $cfg->{Presentation}{overview}{max_rtt} || "100000";
        my $probe = $probes->{$phys_tree->{probe}};
        my $pings = $probe->_pings($phys_tree);
        my $i = 0;
        my @colors = split /\s+/, $cfg->{Presentation}{multihost}{colors};
        my $ProbeUnit = $probe->ProbeUnit();
        for my $slave (@slaves){
            $i++;
            my $rrd;
            my $medc; 
            my $label;        
            if ($slave =~ m|^/|){ # multihost entry
                $rrd = $cfg->{General}{datadir}.'/'.$slave.".rrd";
                $medc = shift @colors;
                my @tree_path = split /\//,$slave;
                shift @tree_path;
                my ($host,$real_slave) = split /~/, $tree_path[-1]; #/
                $tree_path[-1]= $host;                
                my $tree = get_tree($cfg,\@tree_path);
                # not all multihost entries must have the same number of pings
                $probe = $probes->{$tree->{probe}};
                $pings = $probe->_pings($tree);
                $label = $tree->{menu};
                # if there are multiple units ... lets say so ... 
                if ($ProbeUnit ne $probe->ProbeUnit()){
                    $ProbeUnit = 'var units';
                }
                
                if ($real_slave){
                    $label .= "<".  $cfg->{Slaves}{$real_slave}{display_name};
                }
                $label = sprintf("%-20s",$label);
                push @colors, $medc;                
            } 
            else {
                my $s = $slave ? "~".$slave : "";  
                $rrd = $cfg->{General}{datadir}.$dir.'/'.$prop.$s.'.rrd';                
                $medc = $slave ? $cfg->{Slaves}{$slave}{color} : ($cfg->{Presentation}{overview}{median_color} || shift @colors);            
                if ($#slaves > 0){
                    $label = sprintf("%-25s","median RTT from ".($slave ? $cfg->{Slaves}{$slave}{display_name} : $cfg->{General}{display_name} || hostname));
                }
                else {
                    $label = "med RTT"
                }
            };

            my $sdc = $medc;
            $sdc =~ s/^(......).*/${1}30/;
            push @G, 
                "DEF:median$i=${rrd}:median:AVERAGE",
                "DEF:loss$i=${rrd}:loss:AVERAGE",
                "CDEF:ploss$i=loss$i,$pings,/,100,*",
                "CDEF:dm$i=median$i,0,$max,LIMIT",
                calc_stddev($rrd,$i,$pings),
                "CDEF:dmlow$i=dm$i,sdev$i,2,/,-",
                "CDEF:s2d$i=sdev$i",
#                "CDEF:dm2=median,1.5,*,0,$max,LIMIT",
#                "LINE1:dm2", # this is for kicking things down a bit
                "AREA:dmlow$i",
                "AREA:s2d${i}#${sdc}::STACK",
                "LINE1:dm$i#${medc}:${label}",
                  "VDEF:avmed$i=median$i,AVERAGE",
                  "VDEF:avsd$i=sdev$i,AVERAGE",
                  "CDEF:msr$i=median$i,POP,avmed$i,avsd$i,/",
                  "VDEF:avmsr$i=msr$i,AVERAGE",
                  "GPRINT:avmed$i:%5.1lf %ss av md ",
                  "GPRINT:ploss$i:AVERAGE:%5.1lf %% av ls",                
                  "GPRINT:avsd$i:%5.1lf %ss av sd",
                  "GPRINT:avmsr$i:%5.1lf %s am/as\\l";

        }
        my ($graphret,$xs,$ys) = RRDs::graph 
          ($cfg->{General}{imgcache}.$dir."/${prop}_mini.png",
    #       '--lazy',
           '--start','-'.exp2seconds($cfg->{Presentation}{overview}{range}),
           '--title',$cfg->{Presentation}{htmltitle} ne 'yes' ? $phys_tree->{title} : '',
           '--height',$cfg->{Presentation}{overview}{height},
           '--width',$cfg->{Presentation}{overview}{width},
           '--vertical-label', $ProbeUnit,
           '--imgformat','PNG',
           Smokeping::Graphs::get_colors($cfg),
           '--alt-autoscale-max',
           '--alt-y-grid',
           '--rigid',
           '--lower-limit','0',
           @G,
           "COMMENT:$date\\r");
        my $ERROR = RRDs::error();
        $page .= "<div class=\"panel\">";
        $page .= "<div class=\"panel-heading\"><h2>".$phys_tree->{title}."</h2></div>"
            if $cfg->{Presentation}{htmltitle} eq 'yes';
        $page .= "<div class=\"panel-body\">";
        if (defined $ERROR) {
                $page .= "ERROR: $ERROR<br>".join("<br>", map {"'$_'"} @G);
        } else {
         $page.="<A HREF=\"".lnk($q, (join ".", @$open, ${prop}))."\">".
            "<IMG BORDER=\"0\" WIDTH=\"$xs\" HEIGHT=\"$ys\" ".
            "SRC=\"".$cfg->{General}{imgurl}.$dir."/${prop}_mini.png\"></A>";
        }
        $page .="</div></div>\n";
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
           '--width',$cfg->{Presentation}{overview}{width},
           '--end','-'.int($start / $cfg->{Presentation}{detail}{width}),
           "DEF:maxping=${rrd}:median:AVERAGE",
           'PRINT:maxping:MAX:%le' );
        my $ERROR = RRDs::error();
           do_log $ERROR if $ERROR;
        my $val = $graphret->[0];
        $val = 0 if $val =~ /nan/i;
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
                $maxmedian{$x} *= 1.2;
        } else {
                $maxmedian{$x} = $max * 1.2;
        }

        $maxmedian{$x} = $cfg->{Presentation}{detail}{max_rtt} 
            if $cfg->{Presentation}{detail}{max_rtt}
                and $maxmedian{$x} > $cfg->{Presentation}{detail}{max_rtt}
     };
     return \%maxmedian;    
}

sub smokecol ($) {
    my $count = shift;
    return [] unless $count > 2;
    my $half = $count/2;
    my @items;
    my $itop=$count;
    my $ibot=1;
    for (; $itop > $ibot; $itop--,$ibot++){
        my $color = int(190/$half * ($half-$ibot))+50;
        push @items, "CDEF:smoke${ibot}=cp${ibot},UN,UNKN,cp${itop},cp${ibot},-,IF";
        push @items, "AREA:cp${ibot}";
        push @items, "STACK:smoke${ibot}#".(sprintf("%02x",$color) x 3);
    };
    return \@items;
}

sub parse_datetime($){
    my $in = shift;
    for ($in){ 
        $in =~ s/$xssBadRx/_/g;
        /^(\d+)$/ && do { my $value = $1; $value = time if $value > 2**32; return $value};
        /^\s*(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\s*$/  && 
            return POSIX::mktime($6||0,$5||0,$4||0,$3,$2-1,$1-1900,0,0,-1);
        /^now$/ && return time;
        /([ -:a-z0-9]+)/ && return $1;     
    };
    return time;
}
        
sub get_detail ($$$$;$){
    # when drawing the detail page there are three modes for doing it
 
    # a) 's' classic with several static graphs on the page
    # b) 'n' navigator mode with one graph. below the graph one can specify the end time
    #        and the length of the graph.
    # c) 'c' chart mode, one graph with a link to it's full page
    # d) 'a' ajax mode, generate image based on given url and dump in on stdout
    #    
    my $cfg = shift;
    my $q = shift;
    my $tree = shift;
    my $open = shift;
    my $mode = shift || $q->param('displaymode') || 's';
    $mode =~ s/$xssBadRx/_/g; 
    my $phys_tree = $tree;
    my $phys_open = $open;    
    if ($tree->{__tree_link}){
	$phys_tree=$tree->{__tree_link};
	$phys_open = $tree->{__real_path};
    }

    if ($phys_tree->{host} and $phys_tree->{host} =~ m|^/|){
        return Smokeping::Graphs::get_multi_detail($cfg,$q,$tree,$open,$mode);
    }

    # don't distinguish anymore ... tree is now phys_tree
    $tree = $phys_tree;

    my @slaves;
    if (not $tree->{nomasterpoll} or $tree->{nomasterpoll} eq 'no' or $mode eq 'a' or $mode eq 'n'){
        @slaves  = ("");
    };

    if ($tree->{slaves} and $mode eq 's'){
        push @slaves, split /\s+/,$tree->{slaves};       
    };
 
    return "" if not defined $tree->{host} or 0 == @slaves;

    my $file = $mode eq 'c' ? (split(/~/, $open->[-1]))[0] : $open->[-1];
    my @dirs = @{$phys_open};
    pop @dirs;
    my $dir = "";

    return "<div>ERROR: ".(join ".", @dirs)." has no probe defined</div>"
        unless $tree->{probe};

    return "<div>ERROR: ".(join ".", @dirs)." $tree->{probe} is not known</div>"
        unless $cfg->{__probes}{$tree->{probe}};

    my $probe = $cfg->{__probes}{$tree->{probe}};
    my $ProbeDesc = $probe->ProbeDesc();
    my $ProbeUnit = $probe->ProbeUnit();
    my $pings = $probe->_pings($tree);
    my $step = $probe->step();
    my $page;

    return "<div>ERROR: unknown displaymode $mode</div>"
      unless $mode =~ /^[snca]$/;

    for (@dirs) {
        $dir .= "/$_";
        mkdir $cfg->{General}{imgcache}.$dir, 0755 
                unless -d  $cfg->{General}{imgcache}.$dir;
        die "ERROR: creating  $cfg->{General}{imgcache}$dir: $!\n"
                unless -d  $cfg->{General}{imgcache}.$dir;
        
    }
    my $base_rrd = $cfg->{General}{datadir}.$dir."/${file}";

    my $imgbase;
    my $imghref;
    my $max = {};
    my @tasks;
    my %lastheight;     

    if ($mode eq 's'){
        # in nav mode there is only one graph, so the height calculation
        # is not necessary.     
        $imgbase = $cfg->{General}{imgcache}."/".(join "/", @dirs)."/${file}";
        $imghref = $cfg->{General}{imgurl}."/".(join "/", @dirs)."/${file}";    
        @tasks = @{$cfg->{Presentation}{detail}{_table}};
        for my $slave (@slaves){            
            my $s =  $slave ? "~$slave" : "";
            if (open (HG,"<${imgbase}.maxheight$s")){
                 while (<HG>){
                     chomp;
                     my @l = split / /;
                     $lastheight{$s}{$l[0]} = $l[1];
                 }
                 close HG;
             }
             $max->{$s} = findmax $cfg, $base_rrd.$s.".rrd";
             if (open (HG,">${imgbase}.maxheight$s")){
                 foreach my $size (keys %{$max->{$s}}){
                     print HG "$s $max->{$s}{$size}\n";        
                 }
                 close HG;
             }
        }
    } 
    elsif ($mode eq 'n' or $mode eq 'a') {
        my $slave = (split(/~/, $open->[-1]))[1];
        my $name = $slave ? " as seen from ". $cfg->{Slaves}{$slave}{display_name} : "";
        mkdir $cfg->{General}{imgcache}."/__navcache",0755  unless -d  $cfg->{General}{imgcache}."/__navcache";
        # remove old images after one hour
        my $pattern = $cfg->{General}{imgcache}."/__navcache/*.png";
        for (glob $pattern){
                unlink $_ if time - (stat $_)[9] > 3600;
        }
        if ($mode eq 'n') {
	    $imgbase =$cfg->{General}{imgcache}."/__navcache/".time()."$$";
	    $imghref =$cfg->{General}{imgurl}."/__navcache/".time()."$$";
        } else {
            my $serial = int(rand(2000));
            $imgbase =$cfg->{General}{imgcache}."/__navcache/".$serial;
            $imghref =$cfg->{General}{imgurl}."/__navcache/".$serial;
        }

	$q->param('epoch_start',parse_datetime($q->param('start')));
	$q->param('epoch_end',parse_datetime($q->param('end')));
    my $title = $q->param('title') || ("Navigator Graph".$name);
    @tasks = ([$title, parse_datetime($q->param('start')),parse_datetime($q->param('end'))]);
        my ($graphret,$xs,$ys) = RRDs::graph
          ("dummy", 
           '--start', $tasks[0][1],
           '--end',$tasks[0][2], 
           "DEF:maxping=${base_rrd}.rrd:median:AVERAGE",
           'PRINT:maxping:MAX:%le' );
        my $ERROR = RRDs::error();
        return "<div>RRDtool did not understand your input: $ERROR.</div>" if $ERROR;     
        my $val = $graphret->[0];
        $val = 1 if $val =~ /nan/i;
        $max->{''} = { $tasks[0][1] => $val * 1.5 };
    } else  { 
        # chart mode 
        mkdir $cfg->{General}{imgcache}."/__chartscache",0755  unless -d  $cfg->{General}{imgcache}."/__chartscache";
        # remove old images after one hour
        my $pattern = $cfg->{General}{imgcache}."/__chartscache/*.png";
        for (glob $pattern){
                unlink $_ if time - (stat $_)[9] > 3600;
        }
        my $desc = join "/",@{$open};
        @tasks = ([$desc , 3600]);
        $imgbase = $cfg->{General}{imgcache}."/__chartscache/".(join ".", @dirs).".${file}";
        $imghref = $cfg->{General}{imgurl}."/__chartscache/".(join ".", @dirs).".${file}";      

        my ($graphret,$xs,$ys) = RRDs::graph
          ("dummy", 
           '--start', time()-3600,
           '--end', time(),  
           "DEF:maxping=${base_rrd}.rrd:median:AVERAGE",
           'PRINT:maxping:MAX:%le' );
        my $ERROR = RRDs::error();
        return "<div>RRDtool did not understand your input: $ERROR.</div>" if $ERROR;     
        my $val = $graphret->[0];
        $val = 1 if $val =~ /nan/i;
        $max->{''} = { $tasks[0][1] => $val * 1.5 };
    }
        
    my $smoke = $pings >= 3
      ? smokecol $pings : 
      [ 'COMMENT:(Not enough pings to draw any smoke.)\s', 'COMMENT:\s' ]; 
    # one \s doesn't seem to be enough
    my @upargs;
    my @upsmoke;

    my %lc;
    my %lcback;
    if ( defined $cfg->{Presentation}{detail}{loss_colors}{_table} ) {
        for (@{$cfg->{Presentation}{detail}{loss_colors}{_table}}) {
            my ($num,$col,$txt) = @{$_};
            $lc{$num} = [ $txt, "#".$col ];
        }
    } else {  
        my $p = $pings;
        %lc =  (0          => ['0',   '#26ff00'],
                1          => ["1/$p",  '#00b8ff'],
                2          => ["2/$p",  '#0059ff'],
                3          => ["3/$p",  '#5e00ff'],
                4          => ["4/$p",  '#7e00ff'],
                int($p/2)  => [int($p/2)."/$p", '#dd00ff'],
                $p-1       => [($p-1)."/$p",    '#ff0000'],
                );
    };
    # determine a more 'pastel' version of the ping colours; this is 
    # used for the optional loss background colouring
    foreach my $key (keys %lc) {
        if ($key == 0) {
                $lcback{$key} = "";
                next;
        }
        my $web = $lc{$key}[1];
        my @rgb = Smokeping::Colorspace::web_to_rgb($web);
        my @hsl = Smokeping::Colorspace::rgb_to_hsl(@rgb);
        $hsl[2] = (1 - $hsl[2]) * (2/3) + $hsl[2];
        @rgb = Smokeping::Colorspace::hsl_to_rgb(@hsl);
        $web = Smokeping::Colorspace::rgb_to_web(@rgb);
        $lcback{$key} = $web;
    }

    my %upt;
    if ( defined $cfg->{Presentation}{detail}{uptime_colors}{_table} ) {
        for (@{$cfg->{Presentation}{detail}{uptime_colors}{_table}}) {
            my ($num,$col,$txt) = @{$_};
            $upt{$num} = [ $txt, "#".$col];
        }
    } else {  
        %upt = (3600       => ['<1h', '#FFD3D3'],
                2*3600     => ['<2h', '#FFE4C7'],
                6*3600     => ['<6h', '#FFF9BA'],
                12*3600    => ['<12h','#F3FFC0'],
                24*3600    => ['<1d', '#E1FFCC'],
                7*24*3600  => ['<1w', '#BBFFCB'],
                30*24*3600 => ['<1m', '#BAFFF5'],
                '1e100'    => ['>1m', '#DAECFF']
                );
    }
                
    my $BS = '';
    if ( $RRDs::VERSION >= 1.199908 ){
        $ProbeDesc =~ s|:|\\:|g;
        $BS = '\\';
    }

    for (@tasks) {
        my ($desc,$start,$end) = @{$_};
        my %xs;
        my %ys;
        my $sigtime = ($end and $end =~ /^\d+$/) ? $end : time;
        my $date = $cfg->{Presentation}{detail}{strftime} ? 
                   POSIX::strftime($cfg->{Presentation}{detail}{strftime}, localtime($sigtime)) : scalar localtime($sigtime);
        if ( $RRDs::VERSION >= 1.199908 ){
            $date =~ s|:|\\:|g;
        }
        $end ||= 'last';
        $start = exp2seconds($start) if $mode =~ /[s]/; 

        my $startstr = $start =~ /^\d+$/ ? POSIX::strftime("%Y-%m-%d %H:%M",localtime($mode eq 'n' ? $start : time-$start)) : $start;
        my $endstr   = $end =~ /^\d+$/ ? POSIX::strftime("%Y-%m-%d %H:%M",localtime($mode eq 'n' ? $end : time)) : $end;

        my $realstart = ( $mode =~ /[sc]/ ? '-'.$start : $start);

        for my $slave (@slaves){
            my $s = $slave ? "~$slave" : "";
            my $swidth = $max->{$s}{$start} / $cfg->{Presentation}{detail}{height};
            my $rrd = $base_rrd.$s.".rrd";
            my $stddev = Smokeping::RRDhelpers::get_stddev($rrd,'median','AVERAGE',$realstart,$sigtime) || 0;
            my @median = ("DEF:median=${rrd}:median:AVERAGE",
                          "CDEF:ploss=loss,$pings,/,100,*",
                          "VDEF:avmed=median,AVERAGE",
                          "CDEF:mesd=median,POP,avmed,$stddev,/",
                          'GPRINT:avmed:median rtt\:  %.1lf %ss avg',
                          'GPRINT:median:MAX:%.1lf %ss max',
                          'GPRINT:median:MIN:%.1lf %ss min',
                          'GPRINT:median:LAST:%.1lf %ss now',
                          sprintf('COMMENT:%.1f ms sd',$stddev*1000.0),
                          'GPRINT:mesd:AVERAGE:%.1lf %s am/s\l',
                          "LINE1:median#202020"
                  );
            push @median, ( "GPRINT:ploss:AVERAGE:packet loss\\: %.2lf %% avg",
                        "GPRINT:ploss:MAX:%.2lf %% max",
                        "GPRINT:ploss:MIN:%.2lf %% min",
                        'GPRINT:ploss:LAST:%.2lf %% now\l',
                        'COMMENT:loss color\:'
            );
            my @lossargs = ();
            my @losssmoke = ();
            my $last = -1;        
            foreach my $loss (sort {$a <=> $b} keys %lc){
                next if $loss >= $pings;
                my $lvar = $loss; $lvar =~ s/\./d/g ;
                push @median, 
                   (
                     "CDEF:me$lvar=loss,$last,GT,loss,$loss,LE,*,1,UNKN,IF,median,*",
                     "CDEF:meL$lvar=me$lvar,$swidth,-",
                     "CDEF:meH$lvar=me$lvar,0,*,$swidth,2,*,+",             
                     "AREA:meL$lvar",
                     "STACK:meH$lvar$lc{$loss}[1]:$lc{$loss}[0]"
                     #                   "LINE2:me$lvar$lc{$loss}[1]:$lc{$loss}[0]"
                    );
                if  ($cfg->{Presentation}{detail}{loss_background} and $cfg->{Presentation}{detail}{loss_background} eq 'yes') {
                    push @lossargs,
                    (
                        "CDEF:lossbg$lvar=loss,$last,GT,loss,$loss,LE,*,INF,UNKN,IF",
                        "AREA:lossbg$lvar$lcback{$loss}",
                    );
                    push @losssmoke,
                    (
                        "CDEF:lossbgs$lvar=loss,$last,GT,loss,$loss,LE,*,cp2,UNKN,IF",
                        "AREA:lossbgs$lvar$lcback{$loss}",
                    );
                }
                $last = $loss;
            }

            # if we have uptime draw a colorful background or the graph showing the uptime

            my $cdir=dyndir($cfg)."/".(join "/", @dirs)."/";
            if ((not defined $cfg->{Presentation}{detail}{loss_background} or $cfg->{Presentation}{detail}{loss_background} ne 'yes') &&
                (-f "$cdir/${file}.adr")) {
                @upsmoke = ();
                @upargs = ("COMMENT:Link Up${BS}:     ",
                       "DEF:uptime=${base_rrd}.rrd:uptime:AVERAGE",
                       "CDEF:duptime=uptime,86400,/", 
                       'GPRINT:duptime:LAST: %0.1lf days  (');
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
                #   map {print "$_<br/>"} @upargs;
            };
            my @log = ();
            push @log, "--logarithmic" if  $cfg->{Presentation}{detail}{logarithmic} and
            $cfg->{Presentation}{detail}{logarithmic} eq 'yes';
        
            my @lazy =();
            @lazy = ('--lazy') if $mode eq 's' and $lastheight{$s} and $lastheight{$s}{$start} and $lastheight{$s}{$start} == $max->{$s}{$start};
            my $timer_start = time();
            my $title = "";
            if ($cfg->{Presentation}{htmltitle} ne 'yes') {
                $title = "$desc from " . ($s ? $cfg->{Slaves}{$slave}{display_name}: $cfg->{General}{display_name} || hostname);
            }
            my @task =
               ("${imgbase}${s}_${end}_${start}.png",
               @lazy,
               '--start',$realstart,
               ($end ne 'last' ? ('--end',$end) : ()),
               '--height',$cfg->{Presentation}{detail}{height},
               '--width',$cfg->{Presentation}{detail}{width},
               '--title',$title,
               '--rigid',
               '--upper-limit', $max->{$s}{$start},
               @log,
               '--lower-limit',(@log ? ($max->{$s}{$start} > 0.01) ? '0.001' : '0.0001' : '0'),
               '--vertical-label',$ProbeUnit,
               '--imgformat','PNG',
               Smokeping::Graphs::get_colors($cfg),
               (map {"DEF:ping${_}=${rrd}:ping${_}:AVERAGE"} 1..$pings),
               (map {"CDEF:cp${_}=ping${_},$max->{$s}{$start},LT,ping${_},INF,IF"} 1..$pings),
               ("DEF:loss=${rrd}:loss:AVERAGE"),
               @upargs,# draw the uptime bg color
               @lossargs, # draw the loss bg color
               @$smoke,
               @upsmoke, # draw the rest of the uptime bg color
               @losssmoke, # draw the rest of the loss bg color
               @median,'COMMENT: \l',
               # Gray background for times when no data was collected, so they can
               # be distinguished from network being down.
               ( $cfg->{Presentation}{detail}{nodata_color} ? (
                 'CDEF:nodata=loss,UN,INF,UNKN,IF',
                 "AREA:nodata#$cfg->{Presentation}{detail}{nodata_color}" ):
                 ()),
                 'HRULE:0#000000',
                 "COMMENT:probe${BS}:       $pings $ProbeDesc every ${step}s",
                 'COMMENT:end\: '.$date.'\j' );
#       do_log ("***** begin task ***** <br />");
#       do_log (@task);
#       do_log ("***** end task ***** <br />");
                
              my $graphret;
              ($graphret,$xs{$s},$ys{$s}) = RRDs::graph @task;
 #             die "<div>INFO:".join("<br/>",@task)."</div>";
              my $ERROR = RRDs::error();
              if ($ERROR) {
                  return "<div>ERROR: $ERROR</div><div>".join("<br/>",@task)."</div>";
              };
        }

        if ($mode eq 'a'){ # ajax mode
             open my $img, "${imgbase}_${end}_${start}.png" or die "${imgbase}_${end}_${start}.png: $!";
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
#           $page .= qq|<div class="zoom" style="cursor: crosshair;">|;
           $page .= qq|<IMG id="zoom" BORDER="0" width="$xs{''}" height="$ys{''}" SRC="${imghref}_${end}_${start}.png">| ;
#           $page .= "</div>";
           $page .= $q->start_form(-method=>'POST', -id=>'range_form')
              . "<p>Time range: "		
              . $q->hidden(-name=>'epoch_start',-id=>'epoch_start')
              . $q->hidden(-name=>'hierarchy',-id=>'hierarchy')
              . $q->hidden(-name=>'epoch_end',-id=>'epoch_end')
              . $q->hidden(-name=>'target',-id=>'target' )
              . $q->hidden(-name=>'displaymode',-default=>$mode )
              . $q->textfield(-name=>'start',-default=>$startstr)
              . "&nbsp;&nbsp;to&nbsp;&nbsp;".$q->textfield(-name=>'end',-default=>$endstr)
              . "&nbsp;"
              . $q->submit(-name=>'Generate!')
              . "</p>"
              . $q->end_form();
        } elsif ($mode eq 's') { # classic mode
            $startstr =~ s/\s/%20/g;
            $endstr =~ s/\s/%20/g;
            my $t = $q->param('target');
            $t =~ s/$xssBadRx/_/g; 
            for my $slave (@slaves){
                my $s = $slave ? "~$slave" : "";
                $page .= "<div class=\"panel\">";
#           $page .= (time-$timer_start)."<br/>";
#           $page .= join " ",map {"'$_'"} @task;
                if ($cfg->{Presentation}{htmltitle} eq 'yes') {
                    # TODO we generate this above to, maybe share code or store variable ?
                    my $title = "$desc from " . ($s ? $cfg->{Slaves}{$slave}{display_name}: $cfg->{General}{display_name} || hostname);
                    $page .= "<div class=\"panel-heading\"><h2>$title</h2></div>";
                }
                $page .= "<div class=\"panel-body\">";
                $page .= ( qq{<a href="}.cgiurl($q,$cfg)."?".hierarchy($q).qq{displaymode=n;start=$startstr;end=now;}."target=".$t.$s.'">'
                      . qq{<IMG BORDER="0" SRC="${imghref}${s}_${end}_${start}.png">}."</a>" ); #"
                $page .= "</div></div>\n";
            }
        } else { # chart mode
            $page .= qq{<div class="panel-body">};
            my $href= (split /~/, (join ".", @$open))[0]; #/ # the link is 'slave free'            
            $page .= (  qq{<a href="}.lnk($q, $href).qq{">}
                      . qq{<IMG BORDER="0" SRC="${imghref}_${end}_${start}.png">}."</a>" ); #"
            $page .= "</div>";
            
        }

    }
    return $page;
}

sub get_charts ($$$){
    my $cfg = shift;
    my $q = shift;
    my $open = shift;
    my $cache = $cfg->{__sortercache};
    
    my $page = "<h1>$cfg->{Presentation}{charts}{title}</h1>";   
    return $page."<p>Waiting for initial data ...</p>" unless $cache;
 
    my %charts;
    for my $chart ( keys %{$cfg->{Presentation}{charts}} ) {
        next unless ref $cfg->{Presentation}{charts}{$chart} eq 'HASH';
        $charts{$chart} = $cfg->{Presentation}{charts}{$chart}{__obj}->SortTree($cache->{$chart});
    }
    if (not defined $open->[1]){
        for my $chart ( keys %charts ){
            $page .= "<div class=\"panel\">";
            $page .= "<div class=\"panel-heading\"><h2>$cfg->{Presentation}{charts}{$chart}{title}</h2></div>\n";
            if (not defined $charts{$chart}[0]){
                $page .= "<p>No targets returned by the sorter.</p>"
            } else {
                my $tree = $cfg->{Targets};
                my $chartentry = $charts{$chart}[0];
                for (@{$chartentry->{open}}) {
                   my ($host,$slave) = split(/~/, $_);
                   die "ERROR: Section '$host' does not exist.\n"
                       unless exists $tree->{$host};
                   last unless  ref $tree->{$host} eq 'HASH';
                   $tree = $tree->{$host};
                }
                $page .= get_detail($cfg,$q,$tree,$chartentry->{open},'c');
            }
            $page .= "</div>\n";
         }
     } else {
        my $chart = $open->[1];
        $page = "<h1>$cfg->{Presentation}{charts}{$chart}{title}</h1>\n";
        if (not defined $charts{$chart}[0]){
                $page .= "<p>No targets returned by the sorter.</p>"
        } else {
          my $rank =1;
          for my $chartentry (@{$charts{$chart}}){
            my $tree = $cfg->{Targets};
            for (@{$chartentry->{open}}) {
                my ($host,$slave) = split(/~/, $_);
                die "ERROR: Section '$_' does not exist.\n"
                    unless exists $tree->{$host};
                last unless ref $tree->{$host} eq 'HASH';
                $tree = $tree->{$host};
            }       
            $page .= "<div class=\"panel\">";
            $page .= "<div class=\"panel-heading\"><h2>$rank."; 
            $page .= " ".sprintf($cfg->{Presentation}{charts}{$chart}{format},$chartentry->{value})
                if ($cfg->{Presentation}{charts}{$chart}{format});
            $page .= "</h2></div>";
            $rank++;
            $page .= get_detail($cfg,$q,$tree,$chartentry->{open},'c');
            $page .= "</div>\n";
          }
       }
     }   
     return $page;
}

sub load_sortercache($){
    my $cfg = shift;
    my %cache;
    my $found;
    for (glob "$cfg->{General}{datadir}/__sortercache/data*.storable"){
        # kill old caches ...
        if ((time - (stat "$_")[9]) > $cfg->{Database}{step}*2){
           unlink $_;
           next;
        }
        my $data = Storable::retrieve("$_");
        for my $chart (keys %$data){
            PATH:
            for my $path (keys %{$data->{$chart}}){
                warn "Warning: Duplicate entry $chart/$path in sortercache\n" if defined $cache{$chart}{$path};
                my $root = $cfg->{Targets};
                for my $element (split /\//, $path){
                    if (ref $root eq 'HASH' and defined $root->{$element}){
                        $root = $root->{$element}
                    }
                    else {
                        warn "Warning: Dropping $chart/$path from sortercache\n";
                        next PATH;
                    }
                }                
                $cache{$chart}{$path} = $data->{$chart}{$path}
            }
        }
        $found = 1;
    }
    return ( $found ? \%cache : undef )
}

sub hierarchy_switcher($$){
    my $q = shift;
    my $cfg = shift;
    my $print =$q->start_form(-name=>'hswitch',-method=>'get',-action=>$q->url(-relative=>1));    
    if ($cfg->{Presentation}{hierarchies}){
            $print .= "<div class=\"hierarchy\">";
            $print .= "<label for=\"hierarchy\" class=\"hierarchy-label\">Hierarchy:</label>";
	    $print .= "<div class=\"hierarchy-popup\">";
	    $print .= $q->popup_menu(-name=>'hierarchy',
			             -onChange=>'hswitch.submit()',
                         -id=>'hierarchy',
            		             -values=>[0, sort map {ref $cfg->{Presentation}{hierarchies}{$_} eq 'HASH' 
                                                 ? $_ : () } keys %{$cfg->{Presentation}{hierarchies}}],
            		             -labels=>{0=>'Default Hierarchy',
					       map {ref $cfg->{Presentation}{hierarchies}{$_} eq 'HASH' 
                                                    ? ($_ => $cfg->{Presentation}{hierarchies}{$_}{title} )
                                                    : () } keys %{$cfg->{Presentation}{hierarchies}}
					      }
				    );
             $print .= "</div></div>";
     }
     $print .= "<div class=\"filter\">";
     $print .= "<label for=\"filter\" class=\"filter-label\">Filter:</label>";
     $print .= "<div class=\"filter-text\">";
     $print .= $q->textfield (-name=>'filter',
                     -id=>'filter',
                     -placeholder=>'Filter menu...',
                     -onChange=>'hswitch.submit()',
		             -size=>15,
			    );
     $print .= '</div></div>'.$q->end_form();
     return $print;
}

sub display_webpage($$){
    my $cfg = shift;
    my $q = shift;
    my $targ = '';
    my $t = $q->param('target');
    if ( $t and $t !~ /\.\./ and $t =~ /(\S+)/){
        $targ = $1;
        $targ =~ s/$xssBadRx/_/g;
    }
    my ($path,$slave) = split(/~/,$targ);
    if ($slave and $slave =~ /(\S+)/){
        die "ERROR: slave '$slave' is not defined in the '*** Slaves ***' section!\n"
            unless defined $cfg->{Slaves}{$slave};
        $slave = $1;
    }
    my $hierarchy = $q->param('hierarchy');
    $hierarchy =~ s/$xssBadRx/_/g;
    die "ERROR: unknown hierarchy $hierarchy\n" 
        if $hierarchy and not $cfg->{Presentation}{hierarchies}{$hierarchy};
    my $open = [ (split /\./,$path||'') ];
    my $open_orig = [@$open];
    $open_orig->[-1] .= '~'.$slave if $slave;

    my($filter) = ($q->param('filter') and $q->param('filter') =~ m{([- _0-9a-zA-Z\+\*\(\)\|\^\[\]\.\$]+)});

    my $tree = $cfg->{Targets};
    if ($hierarchy){
        $tree = $cfg->{__hierarchies}{$hierarchy};
    };
    my $menu_root = $tree;
    my $targets = $cfg->{Targets};
    my $step = $cfg->{__probes}{$targets->{probe}}->step();
    # lets see if the charts are opened
    my $charts = 0;
    $charts = 1 if defined $cfg->{Presentation}{charts} and $open->[0] and $open->[0] eq '_charts';
    if ($charts and ( not defined $cfg->{__sortercache} 
                      or $cfg->{__sortercachekeeptime} < time )){
       # die "ERROR: Chart $open->[1] does not exit.\n"
       #           unless $cfg->{Presentation}{charts}{$open->[1]};            
       $cfg->{__sortercache} = load_sortercache $cfg;
       $cfg->{__sortercachekeeptime} = time + 60;
    };
    if (not $charts){
       for (@$open) {
         die "ERROR: Section '$_' does not exist (display webpage)."  # .(join "", map {"$_=$ENV{$_}"} keys %ENV)."\n"
                 unless exists $tree->{$_};
         last unless  ref $tree->{$_} eq 'HASH';
         $tree = $tree->{$_};
       }
    }
    gen_imgs($cfg); # create logos in imgcache
    my $readversion = "?";
    $VERSION =~ /(\d+)\.(\d{3})(\d{3})/ and $readversion = sprintf("%d.%d.%d",$1,$2,$3);
    my $menu = $targets;

        
    if (defined $cfg->{Presentation}{charts} and not $hierarchy){
        my $order = 1;
        $menu_root = { %{$menu_root},
                       _charts => {
                        _order => -99,
                        menu => $cfg->{Presentation}{charts}{menu},
                        map { $_ => { menu => $cfg->{Presentation}{charts}{$_}{menu}, _order => $order++ } } 
                            sort
                               grep { ref $cfg->{Presentation}{charts}{$_} eq 'HASH' } keys %{$cfg->{Presentation}{charts}}
                   }
                 };
    }                    

    my $hierarchy_arg = '';
    if ($hierarchy){
        $hierarchy_arg = 'hierarchy='.uri_escape($hierarchy).';';

    };
    my $filter_arg ='';
    if ($filter){
        $filter_arg = 'filter='.uri_escape($filter).';';

    };
    # if we are in a hierarchy, recover the original path

    my $display_tree = $tree->{__tree_link} ? $tree->{__tree_link} : $tree;

    my $authuser = $ENV{REMOTE_USER} || 'Guest';
    my $page = fill_template
      ($cfg->{Presentation}{template},
       {
        menu => hierarchy_switcher($q,$cfg).
		target_menu( $menu_root,
                             [@$open], #copy this because it gets changed
                             cgiurl($q, $cfg) ."?${hierarchy_arg}${filter_arg}target=",
		             $filter
			   ),
        title => $charts ? "" : $display_tree->{title},
        remark => $charts ? "" : ($display_tree->{remark} || ''),
        overview => $charts ? get_charts($cfg,$q,$open) : get_overview( $cfg,$q,$tree,$open),
        body => $charts ? "" : get_detail( $cfg,$q,$tree,$open_orig ),
        target_ip => $charts ? "" : ($display_tree->{host} || ''),
        owner => $cfg->{General}{owner},
        contact => $cfg->{General}{contact},

        author => '<A HREF="http://tobi.oetiker.ch/">Tobi&nbsp;Oetiker</A> and Niko&nbsp;Tyni',
        smokeping => '<A HREF="http://oss.oetiker.ch/smokeping/counter.cgi/'.$VERSION.'">SmokePing-'.$readversion.'</A>',

        step => $step,
        rrdlogo => '<A HREF="http://oss.oetiker.ch/rrdtool/"><img border="0" alt="RRDtool" src="'.$cfg->{General}{imgurl}.'/rrdtool.png"></a>',
        smokelogo => '<A HREF="http://oss.oetiker.ch/smokeping/counter.cgi/'.$VERSION.'"><img border="0" alt="Smokeping" src="'.$cfg->{General}{imgurl}.'/smokeping.png"></a>',
        authuser => $authuser,
       }
       );
    my $expi = $cfg->{Database}{step} > 120 ? $cfg->{Database}{step} : 120;
    print $q->header(-type=>'text/html',
                     -expires=>'+'.$expi.'s',
                     -charset=> ( $cfg->{Presentation}{charset} || 'utf-8'),
                     -Content_length => length($page),
                     );
    print $page || "<HTML><BODY>ERROR: Reading page template".$cfg->{Presentation}{template}."</BODY></HTML>";

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

sub load_sorters($){
    my $subcfg = shift;
    foreach my $key ( keys %{$subcfg} ) {
        my $x = $subcfg->{$key};
        next unless ref $x eq 'HASH';
        $x->{sorter} =~  /(\S+)\((.+)\)/;
        my $sorter = $1;
        my $arg = $2;
        die "ERROR: sorter $sorter: all sorters start with a capital letter\n"
            unless $sorter =~ /^[A-Z]/;
        eval 'require Smokeping::sorters::'.$sorter;
        die "Sorter '$sorter' could not be loaded: $@\n" if $@;
        $x->{__obj} = eval "Smokeping::sorters::$sorter->new($arg)";
        die "ERROR: sorter $sorter: instantiation with Smokeping::sorters::$sorter->new($arg): $@\n"
           if $@;
    }
}


    
sub update_sortercache($$$$$){
    my $cfg = shift;
    return unless $cfg->{Presentation}{charts};
    my $cache = shift;
    my $path = shift;
    my $base = $cfg->{General}{datadir};
    $path =~ s/^$base\/?//;
    my @updates = map {/U/ ? undef : 0.0+$_ } split /:/, shift;
    my $alert = shift;
    my %info;
    $info{uptime} = shift @updates;
    $info{loss} = shift @updates;
    $info{median} = shift @updates;
    $info{alert} = $alert;
    $info{pings} = \@updates;
    foreach my $chart ( keys %{$cfg->{Presentation}{charts}} ) {    
        next unless ref $cfg->{Presentation}{charts}{$chart} eq 'HASH';
        $cache->{$chart}{$path} = $cfg->{Presentation}{charts}{$chart}{__obj}->CalcValue(\%info);
    }   
}

sub save_sortercache($$$){
    my $cfg = shift;
    my $cache = shift;
    my $probe = shift;
    return unless $cfg->{Presentation}{charts};
    my $dir = $cfg->{General}{datadir}."/__sortercache";
    my $ext = '';
    $ext .= $probe if $probe;
    $ext .= join "",@{$opt{filter}} if @{$opt{filter}};
    $ext =~ s/[^-_=0-9a-z]/_/gi;
    $ext = ".$ext" if $ext;
    mkdir $dir,0755  unless -d $dir;
    Storable::store ($cache, "$dir/new$ext"); 
    rename "$dir/new$ext","$dir/data$ext.storable"
}

sub check_alerts {
    my $cfg = shift;
    my $tree = shift;
    my $pings = shift;
    my $name = shift;
    my $prop = shift;
    my $loss = shift;
    my $rtt = shift;
    my $slave = shift;
    my $gotalert;
    my $s = "";
    if ($slave) {
        $s = '~'.$slave
    } 
    if ( $tree->{alerts} ) {
                my $priority_done;
        $tree->{'stack'.$s} = {loss=>['S'],rtt=>['S']} unless defined $tree->{'stack'.$s};
        my $x = $tree->{'stack'.$s};
            $loss = undef if $loss eq 'U';
        my $lossprct = $loss * 100 / $pings;
            $rtt = undef if $rtt eq 'U';
            push @{$x->{loss}}, $lossprct;
        push @{$x->{rtt}}, $rtt;
            if (scalar @{$x->{loss}} > $tree->{fetchlength}){
            shift @{$x->{loss}};
            shift @{$x->{rtt}};
            }
        for (sort { ($cfg->{Alerts}{$a}{priority}||0)  
                    <=> ($cfg->{Alerts}{$b}{priority}||0)} @{$tree->{alerts}}) {
            my $alert = $cfg->{Alerts}{$_};
            if ( not $alert ) {
                do_log "WARNING: Empty alert in ".(join ",", @{$tree->{alerts}})." ($name)\n";
                next;
            };
            if ( ref $alert->{sub} ne 'CODE' ) {
                    do_log "WARNING: Alert '$_' did not resolve to a Sub Ref. Skipping\n";
                next;
            };
            my $prevmatch = $tree->{'prevmatch'.$s}{$_} || 0;

            # add the current state of an edge triggered alert to the
                    # data passed into a matcher, which allows for somewhat 
                # more intelligent alerting due to state awareness.
                $x->{prevmatch} = $prevmatch;
                my $priority = $alert->{priority};
            my $match = &{$alert->{sub}}($x) || 0; # Avgratio returns undef
                $gotalert = $match unless $gotalert;
            my $edgetrigger = $alert->{edgetrigger} eq 'yes';
            my $what;
            if ($edgetrigger and $prevmatch != $match) {
                $what = ($prevmatch == 0 ? "was raised" : "was cleared");
            }
            if (not $edgetrigger and $match) {
                $what = "is active";
            }
            if ($what and (not defined $priority or not defined $priority_done )) {
                        $priority_done = $priority if $priority and not $priority_done;
                        # send something
                        my $from;
                my $line = "$name/$prop";
                my $base = $cfg->{General}{datadir};
                $line =~ s|^$base/||;
                $line =~ s|/host$||;
                $line =~ s|/|.|g;
                my $urlline = $cfg->{General}{cgiurl}."?target=".$line;
                $line .= " [from $slave]" if $slave;
                my $lossratio = "$loss/$pings";
                my $loss = "loss: ".join ", ",map {defined $_ ? (/^\d/ ? sprintf "%.0f%%", $_ :$_):"U" } @{$x->{loss}};
                my $rtt = "rtt: ".join ", ",map {defined $_ ? (/^\d/ ? sprintf "%.0fms", $_*1000 :$_):"U" } @{$x->{rtt}}; 
                        my $time = time;
                do_log("Alert $_ $what for $line $loss(${lossratio})  $rtt prevmatch: $prevmatch comment: $alert->{comment}");
                my @stamp = localtime($time);
                my $stamp = localtime($time);
                my @to;
                foreach my $addr (map {$_ ? (split /\s*,\s*/,$_) : ()} $cfg->{Alerts}{to},$tree->{alertee},$alert->{to}){
                    next unless $addr;
                    if ( $addr =~ /^\|(.+)/) {
                        my $cmd = $1;
                        # fork them in case they take a long time
                        my $pid;
                        unless ($pid = fork) {
                            unless (fork) {
                                $SIG{CHLD} = 'DEFAULT';
                                if ($edgetrigger) {
                                   exec $cmd,$_,$line,$loss,$rtt,$tree->{host}, ($what =~/raise/);
                                } else {
                                   exec $cmd,$_,$line,$loss,$rtt,$tree->{host};
                                }
                                die "exec failed!";
                            }
                            exit 0;
                        }
                        waitpid($pid, 0);
                    }
                    elsif ( $addr =~ /^snpp:(.+)/ ) {
                                    sendsnpp $1, <<SNPPALERT;
$alert->{comment}
$_ $what on $line
$loss
$rtt
SNPPALERT
                    } 
                    elsif ( $addr =~ /^xmpp:(.+)/ ) {
                        my $xmpparg = "$1 -s '[Smokeping] Alert'";
                        my $xmppalert = <<XMPPALERT;
$stamp
$_ $what on $line
$urlline

Pattern: $alert->{pattern}

Data (old --> now)
$loss
$rtt

Comment: $alert->{comment}

**************************************************





XMPPALERT
                        if (-x "/usr/bin/sendxmpp"){
                            open (M, "|-") || exec ("/usr/bin/sendxmpp $xmpparg");
                            print M $xmppalert;
                            close M;
                        }
                        else {
                            warn "Command sendxmpp not found. Try 'apt-get install sendxmpp' to install it. xmpp message with arg line $xmpparg could not be sent";
                        }
                    }
                    else {
                                    push @to, $addr;
                    }
                };
		if (@to){
                    my $default_mail = <<DOC;
Subject: [SmokeAlert] <##ALERT##> <##WHAT##> on <##LINE##>

<##STAMP##>

Alert "<##ALERT##>" <##WHAT##> for <##URL##>

Pattern
-------
<##PAT##>

Data (old --> now)
------------------
<##LOSS##>
<##RTT##>

Comment
-------
<##COMMENT##>

DOC

                            my $mail = fill_template($alert->{mailtemplate},
                              {
                                          ALERT => $_,
                                          WHAT  => $what,
                                          LINE  => $line,
                                          URL   => $urlline,
                                              STAMP => $stamp,
                                  PAT   => $alert->{pattern},
                              LOSS  => $loss,
                              RTT   => $rtt,
                              COMMENT => $alert->{comment}
                                      },$default_mail) || "Subject: smokeping failed to open mailtemplate '$alert->{mailtemplate}'\n\nsee subject\n";
                    my $oldLocale = POSIX::setlocale(LC_TIME);
                    POSIX::setlocale(LC_TIME,"en_US");
                    my $rfc2822stamp =  POSIX::strftime("%a, %e %b %Y %H:%M:%S %z", @stamp);
                    POSIX::setlocale(LC_TIME,$oldLocale);
                                my $to = join ",",@to;
                                    sendmail $cfg->{Alerts}{from},$to, <<ALERT;
To: $to
From: $cfg->{Alerts}{from}
Date: $rfc2822stamp
$mail
ALERT
                            }
            } else {
                        do_debuglog("Alert \"$_\": no match for target $name\n");
            }
            if ($match == 0) {
                $tree->{'prevmatch'.$s}{$_} = $match;
            } else {
                $tree->{'prevmatch'.$s}{$_} += $match;
            }
        }
    } # end alerts
    return $gotalert;
}


sub update_rrds($$$$$$);
sub update_rrds($$$$$$) {
    my $cfg = shift;
    my $probes = shift;
    my $tree = shift;
    my $name = shift;
    my $justthisprobe = shift; # if defined, update only the targets probed by this probe
    my $sortercache = shift;

    my $probe = $tree->{probe};
    foreach my $prop (keys %{$tree}) {
        if (ref $tree->{$prop} eq 'HASH'){
            update_rrds $cfg, $probes, $tree->{$prop}, $name."/$prop", $justthisprobe, $sortercache;
        } 
            # if we are looking down a branche where no probe property is set there is no sense
        # in further exploring it
        next unless defined $probe;
        next if defined $justthisprobe and $probe ne $justthisprobe;
        my $probeobj = $probes->{$probe};
        my $pings = $probeobj->_pings($tree);
        if ($prop eq 'host' and check_filter($cfg,$name) and $tree->{$prop} !~ m|^/|) { # skip multihost
            my @updates;
            if (not $tree->{nomasterpoll} or $tree->{nomasterpoll} eq 'no'){
                @updates = ([ "", time, $probeobj->rrdupdate_string($tree) ]);
            }
            if ($tree->{slaves}){
                my @slaves = split(/\s+/, $tree->{slaves});
                foreach my $slave (@slaves) {
	            my $lines = Smokeping::Master::get_slaveupdates($cfg, $name, $slave);
                    push @updates, @$lines;
                } #foreach my $checkslave
            }
            for my $update (sort {$a->[1] <=> $b->[1]}  @updates){ # make sure we put the updates in chronological order in
                my $s = $update->[0] ? "~".$update->[0] : "";
                if ( $tree->{rawlog} ){
                        my $file =  POSIX::strftime $tree->{rawlog},localtime($update->[1]);
                    if (open LOG,">>$name$s.$file.csv"){
                            print LOG time,"\t",join("\t",split /:/,$update->[2]),"\n";
                                close LOG;
                            } else {
                                do_log "Warning: failed to open $name$s.$file for logging: $!\n";
                            }
                }       
                my @rrdupdate = ( 
                   $name.$s.".rrd", 
                   '--template', (
                       join ":", "uptime", "loss", "median",
                             map { "ping${_}" } 1..$pings
                   ),
                       $update->[1].":".$update->[2]
                    );     
                do_debuglog("Calling RRDs::update(@rrdupdate)");
                RRDs::update ( @rrdupdate );
                my $ERROR = RRDs::error();
                do_log "RRDs::update ERROR: $ERROR\n" if $ERROR;
                    # check alerts
                my ($loss,$rtt) = (split /:/, $update->[2])[1,2];
                    my $gotalert = check_alerts $cfg,$tree,$pings,$name,$prop,$loss,$rtt,$update->[0];
                    update_sortercache $cfg,$sortercache,$name.$s,$update->[2],$gotalert;
                }
        }
    }
}

sub _deepcopy {
        # this handles circular references on consecutive levels,
        # but breaks if there are any levels in between
        my $what = shift;
        return $what unless ref $what;
        for (ref $what) {
                /^ARRAY$/ and return [ map { $_ eq $what ? $_ : _deepcopy($_) } @$what ];
                /^HASH$/ and return { map { $_ => $what->{$_} eq $what ? 
                                            $what->{$_} : _deepcopy($what->{$_}) } keys %$what };
                /^CODE$/ and return $what; # we don't need to copy the subs
        }
        die "Cannot _deepcopy reference type @{[ref $what]}";
}

sub get_parser () {
    # The _dyn() stuff here is quite confusing, so here's a walkthrough:
    # 1   Probe is defined in the Probes section
    # 1.1 _dyn is called for the section to add the probe- and target-specific
    #     vars into the grammar for this section and its subsections (subprobes)
    # 1.2 A _dyn sub is installed for all mandatory target-specific variables so 
    #     that they are made non-mandatory in the Targets section if they are
    #     specified here. The %storedtargetvars hash holds this information.
    # 1.3 If a probe section has any subsections (subprobes) defined, the main
    #     section turns into a template that just offers default values for
    #     the subprobes. Because of this a _dyn sub is installed for subprobe
    #     sections that makes any mandatory variables in the main section non-mandatory.
    # 1.4 A similar _dyn sub as in 1.2 is installed for the subprobe target-specific
    #     variables as well.
    # 2   Probe is selected in the Targets section top
    # 2.1 _dyn is called for the section to add the probe- and target-specific
    #     vars into the grammar for this section and its subsections. Any _default
    #     values for the vars are removed, as they will be propagated from the Probes
    #     section.
    # 2.2 Another _dyn sub is installed for the 'probe' variable in target subsections
    #     that behaves as 2.1
    # 2.3 A _dyn sub is installed for the 'host' variable that makes the mandatory
    #     variables mandatory only in those sections that have a 'host' setting.
    # 2.4 A _sub sub is installed for the 'probe' variable in target subsections that
    #     bombs out if 'probe' is defined after any variables that depend on the
    #     current 'probe' setting.


    my $KEYD_RE = '[-_0-9a-zA-Z]+';
    my $KEYDD_RE = '[-_0-9a-zA-Z.]+';
    my $PROBE_RE = '[A-Z][a-zA-Z]+';
    my $e = "=";
    my %knownprobes; # the probes encountered so far

    # get a list of available probes for _dyndoc sections
    my $libdir = find_libdir();
    my $probedir = $libdir . "/Smokeping/probes";
    my $matcherdir = $libdir . "/Smokeping/matchers";
    my $sorterdir = $libdir . "/Smokeping/sorters";

    my $probelist;
    my @matcherlist;
    my @sorterlist;

    die("Can't find probe module directory") unless defined $probedir;
    opendir(D, $probedir) or die("opendir $probedir: $!");
    for (readdir D) {
        next unless s/\.pm$//;
        next unless /^$PROBE_RE/;
        $probelist->{$_} = "(See the L<separate module documentation|Smokeping::probes::$_> for details about each variable.)";
    }
    closedir D;

    die("Can't find matcher module directory") unless defined $matcherdir;
    opendir(D, $matcherdir) or die("opendir $matcherdir: $!");
    for (sort readdir D) {
        next unless /[A-Z]/;
        next unless s/\.pm$//;
        push @matcherlist, $_;
    }

    die("Can't find sorter module directory") unless defined $sorterdir;
    opendir(D, $sorterdir) or die("opendir $sorterdir: $!");
    for (sort readdir D) {
        next unless /[A-Z]/;
        next unless s/\.pm$//;
        push @sorterlist, $_;
    }

    # The target-specific vars of each probe
    # We need to store them to relay information from Probes section to Target section
    # see 1.2 above
    my %storedtargetvars; 

    # the part of target section syntax that doesn't depend on the selected probe
    my $TARGETCOMMON; # predeclare self-referencing structures
    # the common variables
    my $TARGETCOMMONVARS = [ qw (probe menu title alerts note email host remark rawlog alertee slaves menuextra parents hide nomasterpoll) ];
    $TARGETCOMMON = 
      {
       _vars     => $TARGETCOMMONVARS,
       _inherited=> [ qw (probe alerts alertee slaves menuextra nomasterpoll) ],
       _sections => [ "/$KEYD_RE/" ],
       _recursive=> [ "/$KEYD_RE/" ],
       _sub => sub {
           my $val = shift;
           return "PROBE_CONF sections are neither needed nor supported any longer. Please see the smokeping_upgrade document."
                if $val eq 'PROBE_CONF';
           return undef;
       },
       "/$KEYD_RE/" => {},
       _order    => 1,
       _varlist  => 1,
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
       hide      => {
                     _doc => <<DOC,
Set the hide property to 'yes' to hide this host from the navigation menu
and from search results. Note that if you set the hide property on a non
leaf entry all subordinate entries will also disapear in the menu structure.
If you know a direct link to a page it is still accessible. Pages which are
hidden from the menu due to a parent being hidden will still show up in
search results and in alternate hierarchies where they are below a non
hidden parent.
DOC
                     _re => '(yes|no)',
                     _default => 'no',
                    },

       nomasterpoll=> {
                     _doc => <<DOC,
Use this in a master/slave setup where the master must not poll a particular
target. The master will now skip this entry in its polling cycle.
Note that if you set the hide property on a non leaf entry
all subordinate entries will also disapear in the menu structure. You can
still access them via direct link or via an alternate hierarchy.

If you have no master/slave setup this will have a similar effect to the
hide property, except that the menu entry will still show up, but will not
contain any graphs.

DOC
                     _re => '(yes|no)',
                     _default => 'no',
                    },

       host      => 
       {
        _doc => <<DOC,
There are three types of "hosts" in smokeping.

${e}over

${e}item 1

The 'hostname' is a name of a host you want to target from smokeping

${e}item 2

The string B<DYNAMIC>. Is for machines that have a dynamic IP address. These boxes
are required to regularly contact the SmokePing server to confirm their IP address.
 When starting SmokePing with the commandline argument
B<--email> it will add a secret password to each of the B<DYNAMIC>
host lines and send a script to the owner of each host. This script
must be started periodically (cron) on the host in question to let smokeping know
where the host is curently located. If the target machine supports
SNMP SmokePing will also query the hosts
sysContact, sysName and sysLocation properties to make sure it is
still the same host.

${e}item 3

A space separated list of 'target-path' entries (multihost target). All
targets mentioned in this list will be displayed in one graph. Note that the
graph will look different from the normal smokeping graphs. The syntax for
multihost targets is as follows:

 host = /world/town/host1 /world/town2/host33 /world/town2/host1~slave

${e}back

DOC

        _sub => sub {
            for ( shift ) {
                m|^DYNAMIC| && return undef;
                /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/ && return undef;
                /^[0-9a-f]{0,4}(\:[0-9a-f]{0,4}){0,6}\:[0-9a-f]{0,4}$/i && return undef;
                m|(?:/$KEYD_RE)+(?:~$KEYD_RE)?(?: (?:/$KEYD_RE)+(?:~$KEYD_RE))*| && return undef;
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
           parents => {
                        _re => "${KEYD_RE}:/(?:${KEYD_RE}(?:/${KEYD_RE})*)?(?: ${KEYD_RE}:/(?:${KEYD_RE}(?:/${KEYD_RE})*)?)*",
                        _re_error => "Use hierarcy:/parent/path syntax",
                        _doc => <<DOC
After setting up a hierarchy in the Presentation section of the
configuration file you can use this property to assign an entry to alternate
hierarchies. The format for parent entries is.

 hierarchyA:/Node1/Node2 hierarchyB:/Node3
      
The entries from all parent properties together will build a new tree for
each hierarchy. With this method it is possible to make a single target show
up multiple times in a tree. If you think this is a good thing, go ahead,
nothing is stopping you. Since you do not only define the parent but the full path
of the parent node, circular dependencies are not possible.

DOC
           },

           alertee => { _re => '^(?:\|.+|.+@\S+|snpp:.+|xmpp:.+)(?:\s*,\s*(?:\|.+|.+@\S+|snpp:.+|xmpp:.+))*$',
                        _re_error => 'the alertee must be an email address here',
                        _doc => <<DOC },
If you want to have alerts for this target and all targets below it go to a particular address
on top of the address already specified in the alert, you can add it here. This can be a comma separated list of items.
DOC
           slaves => {  _re => "(${KEYDD_RE}(?:\\s+${KEYDD_RE})*)?",
                        _re_error => 'Use the format: slaves='.${KEYDD_RE}.' [slave2]',
                        _doc => <<DOC },
The slave names must match the slaves you have setup in the slaves section.
DOC
           menuextra => { 
                        _doc => <<'DOC' },
HTML String to be added to the end of each menu entry. The following tags will be replaced:

  {HOST}     -> #$hostname
  {HOSTNAME} -> $hostname
  {CLASS}    -> same class as the other tags in the menu line
  {HASH}     -> #

DOC
           probe => {
                        _sub => sub {
                                my $val = shift;
                                my $varlist = shift;
                                return "probe $val missing from the Probes section"
                                        unless $knownprobes{$val};
                                my %commonvars;
                                $commonvars{$_} = 1 for @{$TARGETCOMMONVARS};
                                delete $commonvars{host};
                                # see 2.4 above
                                return "probe must be defined before the host or any probe variables"
                                        if grep { not exists $commonvars{$_} } @$varlist;
                                        
                                return undef;
                        },
                        _dyn => sub {
                                # this generates the new syntax whenever a new probe is selected
                                # see 2.2 above
                                my ($name, $val, $grammar) = @_;

                                my $targetvars = _deepcopy($storedtargetvars{$val});
                                my @mandatory = @{$targetvars->{_mandatory}};
                                delete $targetvars->{_mandatory};
                                my @targetvars = sort keys %$targetvars;

                                # the default values for targetvars are only used in the Probes section
                                delete $targetvars->{$_}{_default} for @targetvars;

                                # we replace the current grammar altogether
                                %$grammar = ( %{_deepcopy($TARGETCOMMON)}, %$targetvars ); 
                                $grammar->{_vars} = [ @{$grammar->{_vars}}, @targetvars ];

                                # the subsections differ only in that they inherit their vars from here
                                my $g = _deepcopy($grammar);
                                $grammar->{"/$KEYD_RE/"} = $g;
                                push @{$g->{_inherited}}, @targetvars;

                                # this makes the variables mandatory only in those sections
                                # where 'host' is defined. (We must generate this dynamically
                                # as the mandatory list isn't visible earlier.)
                                # see 2.3 above
                                
                                my $mandatorysub =  sub {
                                        my ($name, $val, $grammar) = @_;
                                        $grammar->{_mandatory} = [ @mandatory ];
                                };
                                $grammar->{host} = _deepcopy($grammar->{host});
                                $grammar->{host}{_dyn} = $mandatorysub;
                                $g->{host}{_dyn} = $mandatorysub;
                        },
           },
    };

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

    # grammar for the ***Probes*** section
    my $PROBES = {
        _doc => <<DOC,
Each module can take specific configuration information from this
area. The jumble of letters above is a regular expression defining legal
module names.

See the documentation of each module for details about its variables.
DOC
        _sections => [ "/$PROBE_RE/" ],

        # this adds the probe-specific variables to the grammar
        # see 1.1 above
        _dyn => sub {
                my ($re, $name, $grammar) = @_;

                # load the probe module
                my $class = "Smokeping::probes::$name";
                Smokeping::maybe_require $class;

                # modify the grammar
                my $probevars = $class->probevars;
                my $targetvars = $class->targetvars;
                $storedtargetvars{$name} = $targetvars;
                
                my @mandatory = @{$probevars->{_mandatory}};
                my @targetvars = sort grep { $_ ne '_mandatory' } keys %$targetvars;
                for (@targetvars) {
                        next if $_ eq '_mandatory';
                        delete $probevars->{$_};
                }
                my @probevars = sort grep { $_ ne '_mandatory' } keys %$probevars;

                $grammar->{_vars} = [ @probevars , @targetvars ];
                $grammar->{_mandatory} = [ @mandatory ];

                # do it for probe instances in subsections too
                my $g = $grammar->{"/$KEYD_RE/"};
                for (@probevars) {
                        $grammar->{$_} = $probevars->{$_};
                        %{$g->{$_}} = %{$probevars->{$_}};
                        # this makes the reference manual a bit less cluttered 
                        $g->{$_}{_doc} = 'see above';
                        delete $g->{$_}{_example};
                        $grammar->{$_}{_doc} = 'see above';
                        delete $grammar->{$_}{_example};
                }
                # make any mandatory variable specified here non-mandatory in the Targets section
                # see 1.2 above
                my $sub = sub {
                        my ($name, $val, $grammar) = shift;
                        $targetvars->{_mandatory} = [ grep { $_ ne $name } @{$targetvars->{_mandatory}} ];
                };
                for my $var (@targetvars) {
                        %{$grammar->{$var}} = %{$targetvars->{$var}};
                        %{$g->{$var}} = %{$targetvars->{$var}};
                        # this makes the reference manual a bit less cluttered 
                        delete $grammar->{$var}{_example};
                        delete $g->{$var}{_doc};
                        delete $g->{$var}{_example};
                        # (note: intentionally overwrite _doc)
                        $grammar->{$var}{_doc} = "(This variable can be overridden target-specifically in the Targets section.)";
                        $grammar->{$var}{_dyn} = $sub 
                                if grep { $_ eq $var } @{$targetvars->{_mandatory}};
                }
                $g->{_vars} = [ @probevars, @targetvars ];
                $g->{_inherited} = $g->{_vars};
                $g->{_mandatory} = [ @mandatory ];

                # the special value "_template" means we don't know yet if
                # there will be any instances of this probe
                $knownprobes{$name} = "_template";

                $g->{_dyn} = sub {
                        # if there is a subprobe, the top-level section
                        # of this probe turns into a template, and we
                        # need to delete its _mandatory list.
                        # Note that Config::Grammar does mandatory checking 
                        # after the whole config tree is read, so we can fiddle 
                        # here with "_mandatory" all we want.
                        # see 1.3 above

                        my ($re, $subprobename, $subprobegrammar) = @_;
                        delete $grammar->{_mandatory};
                        # the parent section doesn't define a valid probe anymore
                        delete $knownprobes{$name}
                                if exists $knownprobes{$name} 
                                   and $knownprobes{$name} eq '_template';
                        # this also keeps track of the real module name for each subprobe,
                        # should we ever need it
                        $knownprobes{$subprobename} = $name;
                        my $subtargetvars = _deepcopy($targetvars);
                        $storedtargetvars{$subprobename} = $subtargetvars;
                        # make any mandatory variable specified here non-mandatory in the Targets section
                        # see 1.4 above
                        my $sub = sub {
                                my ($name, $val, $grammar) = shift;
                                $subtargetvars->{_mandatory} = [ grep { $_ ne $name } @{$subtargetvars->{_mandatory}} ];
                        };
                        for my $var (@targetvars) {
                                $subprobegrammar->{$var}{_dyn} = $sub 
                                        if grep { $_ eq $var } @{$subtargetvars->{_mandatory}};
                        }
                }
        },
        _dyndoc => $probelist, # all available probes
        _sections => [ "/$KEYD_RE/" ],
        "/$KEYD_RE/" => {
                _doc => <<DOC,
You can define multiple instances of the same probe with subsections. 
These instances can have different values for their variables, so you
can eg. have one instance of the FPing probe with packet size 1000 and
step 300 and another instance with packet size 64 and step 30.
The name of the subsection determines what the probe will be called, so
you can write descriptive names for the probes.

If there are any subsections defined, the main section for this probe
will just provide default parameter values for the probe instances, ie.
it will not become a probe instance itself.

The example above would be written like this:

 *** Probes ***

 + FPing
 # this value is common for the two subprobes
 binary = /usr/bin/fping 

 ++ FPingLarge
 packetsize = 1000
 step = 300

 ++ FPingSmall
 packetsize = 64
 step = 30

DOC
        },
    }; # $PROBES

    my $parser = Smokeping::Config->new 
      (
       {
        _sections  => [ qw(General Database Presentation Probes Targets Alerts Slaves) ],
        _mandatory => [ qw(General Database Presentation Probes Targets) ],
        General => 
        {
         _doc => <<DOC,
General configuration values valid for the whole SmokePing setup.
DOC
         _vars =>
         [ qw(owner imgcache imgurl datadir dyndir pagedir piddir sendmail offset
              smokemail cgiurl mailhost mailuser mailpass snpphost contact display_name
              syslogfacility syslogpriority concurrentprobes changeprocessnames tmail
              changecgiprogramname linkstyle precreateperms ) ],

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

         display_name => 
         {
          _doc => <<DOC,
What should the master host be called when working in master/slave mode. This is used in the overview
graph for example.
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

Instead of using sendmail, you can specify the name of an smtp server and
use perl's Net::SMTP module to send mail (for alerts and DYNAMIC client
script). Several comma separated mailhosts can be specified. SmokePing will
try one after the other if one does not answer for 5 seconds.
DOC
          _sub => sub { require Net::SMTP ||return "ERROR: loading Net::SMTP"; return undef; }
         },
	 
	 mailuser  => 
         {
          _doc => <<DOC,
username on mailhost, SmokePing will use this user to send mail (Net::SMTP).
DOC
         },
	 
	 mailpass  => 
         {
          _doc => <<DOC,
password of username on mailhost, SmokePing will use this password to send mail (Net::SMTP).
DOC
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
        dyndir =>
        {
         %$DIRCHECK_SUB,
         _doc => <<DOC,
The base directory where SmokePing keeps the files related to the DYNAMIC function.
This directory must be writeable by the WWW server. It is also used for temporary
storage of slave polling results by the master in 
L<the masterE<sol>slave mode|smokeping_master_slave>.

If this variable is not specified, the value of C<datadir> will be used instead.
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
         precreateperms =>
         {
            _re => '[0-7]+',
            _re_error => 'please specify the permissions in octal',
            _example => '2755',
            _doc => <<DOC,
If this variable is set, the Smokeping daemon will create its directory
hierarchy under 'dyndir' (the CGI-writable tree) at startup with the
specified directory permission bits. The value is interpreted as an
octal value, eg. 775 for rwxrwxr-x etc.

If unset, the directories will be created dynamically with umask 022.
DOC
         },
     linkstyle =>
     {
      _re => '(?:absolute|relative|original)',
      _default => 'relative',
      _re_error =>
      'linkstyle must be one of "absolute", "relative" or "original"',
      _doc => <<DOC,
How the CGI self-referring links are created. The possible values are 

${e}over

${e}item absolute 

Full hostname and path derived from the 'cgiurl' variable 

S<\<a href="http://hostname/path/smokeping.cgi?foo=bar"\>>

${e}item relative 

Only the parameter part is specified 

S<\<a href="?foo=bar"\>>

${e}item original 

The way the links were generated before Smokeping version 2.0.4:
no hostname, only the path 

S<\<a href="/path/smokeping.cgi?foo=bar"\>>

${e}back

The default is "relative", which hopefully works for everybody.
DOC
    },
         syslogfacility =>
         {
          _re => '\w+',
          _re_error => 
          "syslogfacility must be alphanumeric",
          _doc => <<DOC,
The syslog facility to use, eg. local0...local7. 
Note: syslog logging is only used if you specify this.
DOC
         },
         syslogpriority =>
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
          _default => 'yes',
         },
         changecgiprogramname => {
          _re => '(yes|no)',
          _re_error =>"this must either be 'yes' or 'no'",
          _doc => <<DOC,
Usually the Smokeping CGI tries to log any possible errors with an extended
program name that includes the IP address of the remote client for easier
debugging. If this variable is set to 'no', the program name will not be 
modified. The only reason you would want this is if you have a very old
version of the CGI::Carp module. See 
L<the installation document|smokeping_install> for details.
DOC
          _default => 'yes',
         },
     tmail => 
      {
        %$FILECHECK_SUB,
        _doc => <<DOC,
Path to your tSmoke HTML mail template file. See the tSmoke documentation for details.
DOC
      }
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
         { 
          %$INTEGER_SUB,
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
           _re => '\d+',
           _sub => sub {
                my $val = shift;
                return "ERROR: The pings value must be at least 3."
                        if $val < 3;
                return undef;
           },
          _doc => <<DOC,
How many pings should be sent to each target. Suggested: 20 pings. Minimum value: 3 pings.
This can be overridden by each probe. Some probes (those derived from
basefork.pm, ie. most except the FPing variants) will even let this
be overridden target-specifically. Note that the number of pings in
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
          _sections => [ qw(overview detail charts multihost hierarchies) ],
          _mandatory => [ qw(overview template detail) ],
          _vars      => [ qw (template charset htmltitle graphborders) ],
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
By default, SmokePing assumes the 'utf-8' character set. If you use
something else, this is the place to speak up.
DOC
         },
         htmltitle => {
           _doc => <<DOC,
By default, SmokePing will render the title of the graph in the image,
when set to 'yes' the title is inserted in the html page.
DOC
           _re  => '(yes|no)',
           _re_error =>"this must either be 'yes' or 'no'",
         },
         graphborders => {
           _doc => <<DOC,
By default, SmokePing will render gray border on a light gray background,
if set to 'no' borders will be hidden and the background and canvas
will be transparent.
DOC
           _re  => '(yes|no)',
           _re_error =>"this must either be 'yes' or 'no'",
         },
         charts => {
           _doc => <<DOC,
The SmokePing Charts feature allow you to have Top X lists created according
to various criteria.

Each type of Chart must live in its own subsection.

 + charts
 menu = Charts
 title = The most interesting destinations
 ++ median
 sorter = Median(entries=>10)
 title = Sorted by Median Roundtrip Time
 menu = Top Median RTT
 format = Median RTT %e s

DOC
           _vars => [ qw(menu title) ],
           _sections => [ "/$KEYD_RE/" ],
           _mandatory => [ qw(menu title) ],

           menu => { _doc => 'Menu entry for the Charts Section.' },
           title => { _doc => 'Page title for the Charts Section.' },
           "/$KEYD_RE/" =>
           {
               _vars => [ qw(menu title sorter format) ],
               _mandatory => [ qw(menu title sorter) ],
               menu => { _doc => 'Menu entry' },
               title => { _doc => 'Page title' },
               format => { _doc => 'sprintf format string to format curent value' },
               sorter => { _re => '\S+\(\S+\)',
                           _re_error => 'use a sorter call here: Sorter(arg1=>val1,arg2=>val2)',
                           _doc => 'sorter for this charts sections',
                        }
           }
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
in the format I<rrggbb>. Note that if you work with slaves, the slaves medians will
be drawn in the slave color in the overview graph.
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
          _vars => [ qw(width height loss_background logarithmic unison_tolerance max_rtt strftime nodata_color) ],
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
         loss_background      => { _doc => <<EOF,
Should the graphs be shown with a background showing loss data for emphasis (yes/no)?

If this option is enabled, uptime data is no longer displayed in the graph background.
EOF
                       _re  => '(yes|no)',
                       _re_error =>"this must either be 'yes' or 'no'",
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
 1000 ff0000    ">=3"

DOC
                          0 => 
                          {
                           _doc => <<DOC,
Activate when the number of losst pings is larger or equal to this number
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
Color for this uptime range.
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
           multihost => {
              _vars => [ qw(colors) ],
              _doc => "Settings for the multihost graphs. At the moment this is only used for the color setting. Check the documentation on the host property of the target section for more.",
              colors => {
                 _doc => "Space separated list of colors for multihost graphs",
                 _example => "ff0000 00ff00 0000ff",
                 _re => '[0-9a-z]{6}(?: [0-9a-z]{6})*',
                
              }
           }, #multi host
           hierarchies => {
              _doc => <<DOC,
Provide an alternative presentation hierarchy for your smokeping data. After setting up a hierarchy in this
section. You can use it in each tagets parent property. A drop-down menu in the smokeping website lets
the user switch presentation hierarchy.
DOC
              _sections => [ "/$KEYD_RE/" ],
              "/$KEYD_RE/" => {
                  _doc => "Identifier of the hierarchie. Use this as prefix in the targets parent property",
                  _vars => [ qw(title) ],
                  _mandatory => [ qw(title) ],
                  title => {
                     _doc => "Title for this hierarchy",
                  }
              }
           }, #hierarchies
        }, #present
        Probes => { _sections => [ "/$KEYD_RE/" ],
                    _doc => <<DOC,
The Probes Section configures Probe modules. Probe modules integrate
an external ping command into SmokePing. Check the documentation of each
module for more information about it.
DOC
                  "/$KEYD_RE/" => $PROBES,
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

If you want to make sure a value within a certain range you can use two conditions
in one element

 >45%<=55%

Sometimes it may be that conditions occur at irregular intervals. But still
you only want to throw an alert if they occur several times within a certain
amount of times. The operator B<*X*> will ignore up to I<X> values and still
let the pattern match:

  >10%,*10*,>10%

will fire if more than 10% of the packets have been lost at least twice over the
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
             _vars => [ qw(to from edgetrigger mailtemplate) ],
             _mandatory => [ qw(to from)],
             to => { _doc => <<DOC,
Either an email address to send alerts to, or the name of a program to
execute when an alert matches. To call a program, the first character of the
B<to> value must be a pipe symbol "|". The program will the be called
whenever an alert matches, using the following 5 arguments 
(except if B<edgetrigger> is 'yes'; see below):
B<name-of-alert>, B<target>, B<loss-pattern>, B<rtt-pattern>, B<hostname>.
You can also provide a comma separated list of addresses and programs.
DOC
                        _re => '(\|.+|.+@\S+|snpp:|xmpp:)',
                        _re_error => 'put an email address or the name of a program here',
                      },
             from => { _doc => 'who should alerts appear to be coming from ?',
                       _re => '.+@\S+',
                       _re_error => 'put an email address here',
                      },
             edgetrigger => { _doc => <<DOC,
The alert notifications and/or the programs executed are normally triggered every
time the alert matches. If this variable is set to 'yes', they will be triggered
only when the alert's state is changed, ie. when it's raised and when it's cleared.
Subsequent matches of the same alert will thus not trigger a notification.

When this variable is set to 'yes', a notification program (see the B<to> variable
documentation above) will get a sixth argument, B<raise>, which has the value 1 if the alert
was just raised and 0 if it was cleared.
DOC
                       _re => '(yes|no)',
                       _re_error =>"this must either be 'yes' or 'no'",
                       _default => 'no',
              },
              mailtemplate => {
                      _doc => <<DOC,
When sending out mails for alerts, smokeping normally uses an internally
generated message. With the mailtemplate you can specify a filename for 
a custom template. The file should contain a 'Subject: ...' line. The
rest of the file should contain text. The all B<E<lt>##>I<keyword>B<##E<gt>> type
strings will get replaced in the template before it is sent out. the
following keywords are supported:

 <##ALERT##>    - target name
 <##WHAT##>     - status (is active, was raised, was celared)
 <##LINE##>     - path in the config tree
 <##URL##>      - webpage for graph
 <##STAMP##>    - date and time 
 <##PAT##>      - pattern that matched the alert
 <##LOSS##>     - loss history
 <##RTT##>      - rtt history
 <##COMMENT##>  - comment


DOC

                        _sub => sub {
                             open (my $tmpl, $_[0]) or
                                     return "mailtemplate '$_[0]' not readable";
                             my $subj;
                             while (<$tmpl>){
                                $subj =1 if /^Subject: /;
                                next if /^\S+: /;
                                last if /^$/;
                                return "mailtemplate '$_[0]' should start with mail header lines";
                             }
                             return "mailtemplate '$_[0]' has no Subject: line" unless $subj;
                             return undef;
                          },
                       },
             '/[^\s,]+/' => {
                  _vars => [ qw(type pattern comment to edgetrigger mailtemplate priority) ],
                  _inherited => [ qw(edgetrigger mailtemplate) ],
                  _mandatory => [ qw(type pattern comment) ],
                  to => { _doc => 'Similar to the "to" parameter on the top-level except that  it will only be used IN ADDITION to the value of the toplevel parameter. Same rules apply.',
                        _re => '(\|.+|.+@\S+|snpp:|xmpp:)',
                        _re_error => 'put an email address or the name of a program here',
                          },
                  
                  type => {
                     _doc => <<DOC,
Currently the pattern types B<rtt> and B<loss> and B<matcher> are known. 

Matchers are plugin modules that extend the alert conditions.  Known
matchers are @{[join (", ", map { "L<$_|Smokeping::matchers::$_>" }
@matcherlist)]}.

See the documentation of the corresponding matcher module
(eg. L<Smokeping::matchers::$matcherlist[0]>) for instructions on
configuring it.
DOC
                     _re => '(rtt|loss|matcher)',
                     _re_error => 'Use loss, rtt or matcher'
                          },
                  pattern => {
                     _doc => "a comma separated list of comparison operators and numbers. rtt patterns are in milliseconds, loss patterns are in percents",
                     _re => '(?:([^,]+)(,[^,]+)*|\S+\(.+\s)',
                     _re_error => 'Could not parse pattern or matcher',
                             },
                  edgetrigger => {
                       _re => '(yes|no)',
                       _re_error =>"this must either be 'yes' or 'no'",
                        _default => 'no',
                  },
                  priority => {
                       _re => '[1-9]\d*',
                       _re_error =>"priority must be between 1 and oo",
                       _doc => <<DOC,
if multiple alerts 'match' only the one with the highest priority (lowest number) will cause and
alert to be sent. Alerts without priority will be sent in any case.
DOC
                  },
                  mailtemplate => {
                        _sub => sub {
                             open (my $tmpl, $_[0]) or
                                     return "mailtemplate '$_[0]' not readable";
                             my $subj;
                             while (<$tmpl>){
                                $subj =1 if /^Subject: /;
                                next if /^\S+: /;
                                last if /^$/;
                                return "mailtemplate '$_[0]' should start with mail header lines";
                             }
                             return "mailtemplate '$_[0]' has no Subject: line" unless $subj;
                             return undef;
                          },
                       },
              },
        },
       Slaves => {_doc         => <<END_DOC,
Your smokeping can remote control other somkeping instances running in slave
mode on different hosts. Use this section to tell your master smokeping about the
slaves you are going to use.
END_DOC
          _vars        => [ qw(secrets) ],
          _mandatory   => [ qw(secrets) ],
          _sections    => [ "/$KEYDD_RE/" ],
          secrets => {              
              _sub => sub {
                 return "File '$_[0]' does not exist" unless -f $_[ 0 ];
                 return "File '$_[0]' is world-readable or writable, refusing it" 
                    if ((stat(_))[2] & 6);
                 return undef;
              },
              _doc => <<END_DOC,
The slave secrets file contines one line per slave with the name of the slave followed by a colon
and the secret:

 slave1:secret1
 slave2:secret2
 ...

Note that these secrets combined with a man-in-the-middle attack
effectively give shell access to the corresponding slaves (see
L<smokeping_master_slave>), so the file should be appropriately protected
and the secrets should not be easily crackable.
END_DOC

          },
          timeout => {
              %$INTEGER_SUB,
              _doc => <<END_DOC,
How long should the master wait for its slave to answer?
END_DOC
          },     
          "/$KEYDD_RE/" => {
              _vars => [ qw(display_name location color) ],
              _mandatory => [ qw(display_name color) ],
              _sections => [ qw(override) ],
              _doc => <<END_DOC,
Define some basic properties for the slave.
END_DOC
              display_name => {
                  _doc => <<END_DOC,
Name of the Slave host.
END_DOC
              },
              location => {
                  _doc => <<END_DOC,
Where is the slave located.
END_DOC
              },
              color => {
                  _doc => <<END_DOC,
Color for the slave in graphs where input from multiple hosts is presented.
END_DOC
                  _re       => '[0-9a-f]{6}',
                  _re_error => "I was expecting a color of the form rrggbb",
              },
              override => {
                  _doc => <<END_DOC,
If part of the configuration information must be overwritten to match the
settings of the you can specify this in this section. A setting is
overwritten by giveing the full path of the configuration variable. If you
have this configuration in the Probes section:

 *** Probes ***
 +FPing
 binary = /usr/sepp/bin/fping

You can override it for a particular slave like this:

 ++override
 Probes.FPing.binary = /usr/bin/fping
END_DOC
                    _vars   => [ '/\S+/' ],
               }
           }          
       },
       Targets => {_doc        => <<DOC,
The Target Section defines the actual work of SmokePing. It contains a
hierarchical list of hosts which mark the endpoints of the network
connections the system should monitor. Each section can contain one host as
well as other sections. By adding slaves you can measure the connection to
an endpoint from multiple locations.
DOC
                   _vars       => [ qw(probe menu title remark alerts slaves menuextra parents) ],
                   _mandatory  => [ qw(probe menu title) ],
                   _order => 1,
                   _sections   => [ "/$KEYD_RE/" ],
                   _recursive  => [ "/$KEYD_RE/" ],
                   "/$KEYD_RE/" => $TARGETCOMMON, # this is just for documentation, _dyn() below replaces it
                   probe => { 
                        _doc => <<DOC,
The name of the probe module to be used for this host. The value of
this variable gets propagated
DOC
                        _sub => sub {
                                my $val = shift;
                                return "probe $val missing from the Probes section"
                                        unless $knownprobes{$val};
                                return undef;
                        },
                        # create the syntax based on the selected probe.
                        # see 2.1 above
                        _dyn => sub {
                                my ($name, $val, $grammar) = @_;

                                my $targetvars = _deepcopy($storedtargetvars{$val});
                                my @mandatory = @{$targetvars->{_mandatory}};
                                delete $targetvars->{_mandatory};
                                my @targetvars = sort keys %$targetvars;
                                for (@targetvars) {
                                        # the default values for targetvars are only used in the Probes section
                                        delete $targetvars->{$_}{_default};
                                        $grammar->{$_} = $targetvars->{$_};
                                }
                                push @{$grammar->{_vars}}, @targetvars;
                                my $g = { %{_deepcopy($TARGETCOMMON)}, %{_deepcopy($targetvars)} };
                                $grammar->{"/$KEYD_RE/"} = $g;
                                $g->{_vars} = [ @{$g->{_vars}}, @targetvars ];
                                $g->{_inherited} = [ @{$g->{_inherited}}, @targetvars ];
                                # this makes the reference manual a bit less cluttered 
                                for (@targetvars){
                                    $g->{$_}{_doc} = 'see above';
                                    $grammar->{$_}{_doc} = 'see above';
                                    delete $grammar->{$_}{_example};
                                    delete $g->{$_}{_example};
                                }
                                # make the mandatory variables mandatory only in sections
                                # with 'host' defined
                                # see 2.3 above
                                $g->{host}{_dyn} = sub {
                                        my ($name, $val, $grammar) = @_;
                                        $grammar->{_mandatory} = [ @mandatory ];
                                };
                        }, # _dyn
                        _dyndoc => $probelist, # all available probes
                }, #probe
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
                   slaves => { _doc => <<DOC },
List of slave servers. It gets inherited by all targets.
DOC
                   menuextra => { _doc => <<DOC },
HTML String to be added to the end of each menu entry. The C<{HOST}> entry will be replaced by the
host property of the relevant section. The C<{CLASS}> entry will be replaced by the same
class as the other tags in the manu line.
DOC

           }

      }
    );
    return $parser;
}

sub get_config ($$){
    my $parser = shift;
    my $cfgfile = shift;

    my $cfg = $parser->parse( $cfgfile ) or die "ERROR: $parser->{err}\n";
    # lets have defaults for multihost colors
    if (not $cfg->{Presentation}{multihost} or not $cfg->{Presentation}{multihost}{colors}){
       $cfg->{Presentation}{multihost}{colors} = "004586 ff420e ffde20 579d1c 7e0021 83caff 314004 aecf00 4b1f6f ff950e c5000b 0084d1";
    }
    return $cfg;


}

sub kill_smoke ($$) { 
  my $pidfile = shift;
  my $signal = shift;
    if (defined $pidfile){ 
        if ( -f $pidfile && open PIDFILE, "<$pidfile" ) {
            <PIDFILE> =~ /(\d+)/;
            my $pid = $1;
            if ($signal == SIGINT || $signal == SIGTERM) {
                kill $signal, $pid if kill 0, $pid;
                sleep 3; # let it die
                die "ERROR: Can not stop running instance of SmokePing ($pid)\n"
                        if kill 0, $pid;
            } else {
                die "ERROR: no instance of SmokePing running (pid $pid)?\n"
                        unless kill 0, $pid;
                kill $signal, $pid;
            }
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
        require POSIX;
        &POSIX::setsid or die "Can't start a new session: $!";
        open STDOUT,'>/dev/null' or die "ERROR: Redirecting STDOUT to /dev/null: $!";
        open STDIN, '</dev/null' or die "ERROR: Redirecting STDIN from /dev/null: $!";
        open STDERR, '>/dev/null' or die "ERROR: Redirecting STDERR to /dev/null: $!";
        # send warnings and die messages to log
        $SIG{__WARN__} = sub { do_log ((shift)."\n") };
        $SIG{__DIE__} = sub { return if $^S; do_log ((shift)."\n"); exit 1 }; 
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
                return if $cfg->{General}{changecgiprogramname} eq 'no';
                # set_progname() is available starting with CGI.pm-2.82 / Perl 5.8.1
                # so trap this inside 'eval'
                # even this apparently isn't enough for older versions that try to
                # find out whether they are inside an eval...oh well.
                eval 'CGI::Carp::set_progname($0 . " [client " . ($ENV{REMOTE_ADDR}||"(unknown)") . "]")';
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
                eval {
                        syslog($syslog_priority, 'Starting syslog logging');
                };
                if ($@) {
                        print "Warning: can't connect to syslog. Messages will be lost.\n";
                        print "Error message was: $@";
                }
        }

        sub do_syslog ($){
                my $str = shift;
                $str =~ s,%,%%,g;
                eval {
                        syslog("$syslog_facility|$syslog_priority", $str);
                };
                # syslogd is probably dead if that failed
                # this message is most probably lost too, if we have daemonized
                # let's try anyway, it shouldn't hurt
                print STDERR qq(Can't log "$str" to syslog: $@) if $@;
        }

        sub do_cgilog ($){
                my $str = shift;
                print "<p>" , $str, "</p>\n";
                warn $str, "\n"; # for the webserver log
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

sub load_cfg ($;$) { 
    my $cfgfile = shift;
    my $noinit = shift;
    my $cfmod = (stat $cfgfile)[9] || die "ERROR: loading smokeping configuration file $cfgfile: $!\n";
    # when running under speedy this will prevent reloading on every run
    # if cfgfile has been modified we will still run.
    if (not defined $cfg or not defined $probes # or $cfg->{__last} < $cfmod
        ){
        $cfg = undef;
        my $parser = get_parser;
        $cfg = get_config $parser, $cfgfile;       

        if (defined $cfg->{Presentation}{charts}){
               require Storable;
               die "ERROR: Could not load Storable Support. This is required for the Charts feature - $@\n" if $@;
           load_sorters $cfg->{Presentation}{charts};
        }
        $cfg->{__parser} = $parser;
        $cfg->{__last} = $cfmod;
        $cfg->{__cfgfile} = $cfgfile;
        $probes = undef;
        $probes = load_probes $cfg;
        $cfg->{__probes} = $probes;
        $cfg->{__hierarchies} = {};
        return if $noinit;
        init_alerts $cfg if $cfg->{Alerts};
        add_targets $cfg, $probes, $cfg->{Targets}, $cfg->{General}{datadir};   
        init_target_tree $cfg, $probes, $cfg->{Targets}, $cfg->{General}{datadir};
        if (defined $cfg->{General}{precreateperms} && !$cgimode) {
            make_cgi_directories($cfg->{Targets}, dyndir($cfg),
                                 $cfg->{General}{precreateperms});
        }
        #use Data::Dumper;
        #die Dumper $cfg->{__hierarchies};
    } else {
        do_log("Config file unmodified, skipping reload") unless $cgimode;
    }
}


sub makepod ($){
    my $parser = shift;
    my $e='=';
    my $a='@';
    my $retval = <<POD;

${e}head1 NAME

smokeping_config - Reference for the SmokePing Config File

${e}head1 OVERVIEW

SmokePing takes its configuration from a single central configuration file.
Its location must be hardcoded in the smokeping script and smokeping.cgi.

The contents of this manual is generated directly from the configuration
file parser.

The Parser for the Configuration file is written using David Schweikers
Config::Grammar module. Read all about it in L<Config::Grammar>.

The Configuration file has a tree-like structure with section headings at
various levels. It also contains variable assignments and tables.

Warning: this manual is rather long. See L<smokeping_examples>
for simple configuration examples.

${e}head1 REFERENCE

${e}head2 GENERAL SYNTAX

The text below describes the general syntax of the SmokePing configuration file.
It was copied from the Config::Grammar documentation.

'#' denotes a comment up to the end-of-line, empty lines are allowed and space
at the beginning and end of lines is trimmed.

'\\' at the end of the line marks a continued line on the next line. A single
space will be inserted between the concatenated lines.

'${a}include filename' is used to include another file.

'${a}define a some value' will replace all occurences of 'a' in the following text
with 'some value'.

Fields in tables that contain white space can be enclosed in either C<'> or C<">.
Whitespace can also be escaped with C<\\>. Quotes inside quotes are allowed but must
be escaped with a backslash as well.

${e}head2 SPECIFIC SYNTAX

The text below describes the specific syntax of the SmokePing configuration file.

POD

    $retval .= $parser->makepod;
    $retval .= <<POD;

${e}head1 COPYRIGHT

Copyright (c) 2001-2007 by Tobias Oetiker. All right reserved.

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

}
sub cgi ($$) {
    my $cfgfile = shift;
    my $q = shift;
    $cgimode = 'yes';
    umask 022;
    load_cfg $cfgfile;
    initialize_cgilog();
    if ($q->param(-name=>'slave')) { # a slave is calling in
        Smokeping::Master::answer_slave($cfg,$q);
    } elsif ($q->param(-name=>'secret') && $q->param(-name=>'target') ) {
        my $ret = update_dynaddr $cfg,$q;
        if (defined $ret and $ret ne "") {
                print $q->header(-status => "404 Not Found");
                do_cgilog("Updating DYNAMIC address failed: $ret");
        } else {
                print $q->header; # no HTML output on success
        }
    } else {     
        if (not $q->param('displaymode') or $q->param('displaymode') ne 'a'){ #in ayax mode we do not issue a header YET
        }
        display_webpage $cfg,$q;
    }
    if ((stat $cfgfile)[9] > $cfg->{__last}){
        # we die if the cfgfile is newer than our in memory copy
        kill -9, $$;
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
    my $readversion = "?";
    $VERSION =~ /(\d+)\.(\d{3})(\d{3})/ and $readversion = sprintf("%d.%d.%d",$1,$2,$3);
    my $authuser = $ENV{REMOTE_USER} || 'Guest';
    $page = fill_template
        ($cfg->{Presentation}{template},
         {
          menu => target_menu($cfg->{Targets},
                              [@$open], #copy this because it gets changed
                              "", '',".html"),
          title => $tree->{title},
          remark => ($tree->{remark} || ''),
          overview => get_overview( $cfg,$q,$tree,$open ),
          body => get_detail( $cfg,$q,$tree,$open ),
          target_ip => ($tree->{host} || ''),
          owner => $cfg->{General}{owner},
          contact => $cfg->{General}{contact},
          author => '<A HREF="http://tobi.oetiker.ch/">Tobi&nbsp;Oetiker</A> and Niko&nbsp;Tyni',
          smokeping => '<A HREF="http://oss.oetiker.ch/smokeping/counter.cgi/'.$VERSION.'">SmokePing-'.$readversion.'</A>',
          step => $step,
          rrdlogo => '<A HREF="http://oss.oetiker.ch/rrdtool/"><img border="0" alt="RRDtool" src="'.$cfg->{General}{imgurl}.'/rrdtool.png"></a>',
          smokelogo => '<A HREF="http://oss.oetiker.ch/smokeping/counter.cgi/'.$VERSION.'"><img border="0" alt="Smokeping" src="'.$cfg->{General}{imgurl}.'/smokeping.png"></a>',
          authuser => $authuser,
         });

    print PAGEFILE $page || "<HTML><BODY>ERROR: Reading page template ".$cfg->{Presentation}{template}."</BODY></HTML>";
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

sub pod2man {
        my $string = shift;
        my $pid = open(P, "-|");
        if ($pid) {
                pod2usage(-verbose => 2, -input => \*P);
                exit 0;
        } else {
                print $string;
                exit 0;
        }
}

sub maybe_require {
        # like eval "require $class", but tries to
        # fake missing classes by adding them to %INC.
        # This rocks when we're building the documentation
        # so we don't need to have the external modules 
        # installed.

        my $class = shift;

        # don't do the kludge unless we're building documentation
        unless (exists $opt{makepod} or exists $opt{man}) {
                eval "require $class";
                die  "require $class failed: $@" if $@;
                return;
        }

        my %faked;

        my $file = $class;
        $file =~ s,::,/,g;
        $file .= ".pm";

        eval "require $class";

        while ($@ =~ /Can't locate (\S+)\.pm/) {
                my $missing = $1;
                die("Can't fake missing class $missing, giving up. This shouldn't happen.") 
                        if $faked{$missing}++;
                $INC{"$missing.pm"} = "foobar";
                $missing =~ s,/,::,;

                delete $INC{"$file"}; # so we can redo the require()
                eval "require $class";
                last unless $@;
        }
        die "require $class failed: $@" if $@;
        my $libpath = find_libdir;
        $INC{$file} = "$libpath/$file";
}

sub probedoc {
        my $class = shift;
        my $do_man = shift;
        maybe_require($class);
        if ($do_man) {
                pod2man($class->pod);
        } else {
                print $class->pod;
        }
        exit 0;
}

sub verify_cfg {
    my $cfgfile = shift;
    get_config(get_parser, $cfgfile);
    print "Configuration file '$cfgfile' syntax OK.\n"; 
}
 
sub make_kid {
        my $sleep_count = 0;
        my $pid;
        do {
                $pid = fork;
                unless (defined $pid) {
                        do_log("Fatal: cannot fork: $!");
                        die "bailing out" 
                                if $sleep_count++ > 6;
                        sleep 10;
                }
        } until defined $pid;
        srand();
        return $pid;
}

sub start_probes {
        my $pids = shift;
        my $pid;
        my $myprobe;
        for my $p (keys %$probes) {
                if ($probes->{$p}->target_count == 0) {
                        do_log("No targets defined for probe $p, skipping.");
                        next;
                }
                $pid = make_kid();
                $myprobe = $p;
                $pids->{$pid} = $p;
                last unless $pid;
                do_log("Child process $pid started for probe $p.");
        }
        return $pid;
}

sub load_cfg_slave {
        my %opt = %{$_[0]};
        die "ERROR: no shared-secret defined along with master-url\n" unless $opt{'shared-secret'};
        die "ERROR: no cache-dir defined along with master-url\n" unless $opt{'cache-dir'};
        die "ERROR: no cache-dir ($opt{'cache-dir'}): $!\n" unless -d $opt{'cache-dir'};
        die "ERROR: the shared secret file ($opt{'shared-secret'}) is world-readable or writable"
            if ((stat($opt{'shared-secret'}))[2] & 6);
        open my $fd, "<$opt{'shared-secret'}" or die "ERROR: opening $opt{'shared-secret'} $!\n";
        chomp(my $secret = <$fd>);
        close $fd;
        my $slave_cfg = {
            master_url => $opt{'master-url'},
            cache_dir => $opt{'cache-dir'},
            pid_dir   => $opt{'pid-dir'} || $opt{'cache-dir'},
            shared_secret => $secret,
            slave_name => $opt{'slave-name'} || hostname(),
        };
        # this should get us an initial  config set from the server
        my $new_conf = Smokeping::Slave::submit_results($slave_cfg,{});
        if ($new_conf){
            $cfg=$new_conf;
            $probes = undef;
            $probes = load_probes $cfg;
            $cfg->{__probes} = $probes;
            add_targets($cfg, $probes, $cfg->{Targets}, $cfg->{General}{datadir});
        } else {
          die "ERROR: we did not get config from the master. Maybe we are not configured as a slave for any of the targets on the master ?\n";
        }
        return $slave_cfg;
}

sub main (;$) {
    $cgimode = 0;
    umask 022;
    my $defaultcfg = shift;
    $opt{filter}=[];
    GetOptions(\%opt, 'version', 'email', 'man:s','help','logfile=s','static-pages:s', 'debug-daemon',
                      'nosleep', 'makepod:s','debug','restart', 'filter=s', 'nodaemon|nodemon',
                      'config=s', 'check', 'gen-examples', 'reload', 
                      'master-url=s','cache-dir=s','shared-secret=s',
                      'slave-name=s','pid-dir=s') or pod2usage(2);
    if($opt{version})  { print "$VERSION\n"; exit(0) };
    if(exists $opt{man}) {
        if ($opt{man}) {
                if ($opt{man} eq 'smokeping_config') {
                        pod2man(makepod(get_parser));
                } else {
                        probedoc($opt{man}, 'do_man');
                }
        } else {
                pod2usage(-verbose => 2); 
        }
        exit 0;
    }
    if($opt{help})     {  pod2usage(-verbose => 1); exit 0 };
    if(exists $opt{makepod})  { 
        if ($opt{makepod} and $opt{makepod} ne 'smokeping_config') {
                probedoc($opt{makepod});
        } else {
                print makepod(get_parser);
        }
        exit 0; 
    }
    if (exists $opt{'gen-examples'}) {
        Smokeping::Examples::make($opt{check});
        exit 0;
    }
    initialize_debuglog if $opt{debug} or $opt{'debug-daemon'};
    my $slave_cfg;
    my $cfgfile = $opt{config} || $defaultcfg;
    my $slave_mode = exists $opt{'master-url'};
    if ($slave_mode){     # ok we go slave-mode
        $slave_cfg = load_cfg_slave(\%opt);
    } else {
        if(defined $opt{'check'}) { verify_cfg($cfgfile); exit 0; }
        if($opt{reload})  { 
            load_cfg $cfgfile, 'noinit'; # we need just the piddir
            kill_smoke $cfg->{General}{piddir}."/smokeping.pid", SIGHUP; 
            print "HUP signal sent to the running SmokePing process, exiting.\n";
            exit 0;
        };
        load_cfg $cfgfile;

        if(defined $opt{'static-pages'}) { makestaticpages $cfg, $opt{'static-pages'}; exit 0 };
        if($opt{email})    { enable_dynamic $cfg, $cfg->{Targets},"",""; exit 0 };
    }
    if($opt{restart})  { kill_smoke $cfg->{General}{piddir}."/smokeping.pid", SIGINT;};

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
    do_log "Smokeping version $VERSION successfully launched.";

RESTART:
    my $myprobe;
    my $multiprocessmode;
    my $forkprobes = $cfg->{General}{concurrentprobes} || 'yes';
    if ($forkprobes eq "yes" and keys %$probes > 1 and not $opt{debug}) {
        $multiprocessmode = 1;
        my %probepids;
        my $pid;
        do_log("Entering multiprocess mode.");
        $pid = start_probes(\%probepids);
        $myprobe = $probepids{$pid};
        goto KID unless $pid; # child skips rest of loop
        # parent
        do_log("All probe processes started successfully.");
        my $exiting = 0;
        my $reloading = 0;
        for my $sig (qw(INT TERM)) {
                $SIG{$sig} = sub {
                        do_log("Got $sig signal, terminating child processes.");
                        $exiting = 1;
                        kill $sig, $_ for keys %probepids;
                        my $now = time;
                        while(keys %probepids) { # SIGCHLD handler below removes the keys
                                if (time - $now > 2) {
                                        do_log("Fatal: can't terminate all child processes, giving up.");
                                        exit 1;
                                }
                                sleep 1;
                        }
                        do_log("All child processes successfully terminated, exiting.");
                        exit 0;
                }
        };
        $SIG{CHLD} = sub {
                while ((my $dead = waitpid(-1, WNOHANG)) > 0) {
                        my $p = $probepids{$dead};
                        $p = 'unknown' unless defined $p;
                        do_log("Child process $dead (probe $p) exited unexpectedly with status $?.")
                                unless $exiting or $reloading;
                        delete $probepids{$dead};
                }
        };
        my $gothup = 0;
        $SIG{HUP} = sub {
                do_debuglog("Got HUP signal.");
                $gothup = 1;
        };
        while (1) { # just wait for the signals
                sleep; #sleep until we get a signal
                next unless $gothup;
                $reloading = 1;
                $gothup = 0;
                my $oldprobes = $probes;
                if ($slave_mode) {
                    load_cfg_slave(\%opt);
                } else {
                    $reloading = 0, next unless reload_cfg($cfgfile);
                }
                do_debuglog("Restarting probe processes " . join(",", keys %probepids) . ".");
                kill SIGHUP, $_ for (keys %probepids);
                my $i=0;
                while (keys %probepids) {
                        sleep 1;
                        if ($i % 10 == 0) {
                                do_log("Waiting for child processes to terminate.");
                        }
                        $i++;
                        my %termsent;
                        for (keys %probepids) {
                                my $step = $oldprobes->{$probepids{$_}}->step;
                                if ($i > $step) {
                                        do_log("Child process $_ took over its step value to terminate, killing it with SIGTERM");
                                        if (kill SIGTERM, $_ == 0 and exists $probepids{$_}) {
                                                do_log("Fatal: Child process $_ has disappeared? This shouldn't happen. Giving up.");
                                                exit 1;
                                        } else {
                                                $termsent{$_} = time;
                                        }
                                }
                                for (keys %termsent) {
                                        if (exists $probepids{$_}) {
                                                if (time() - $termsent{$_} > 2) {
                                                        do_log("Fatal: Child process $_ took over 2 seconds to exit on TERM signal. Giving up.");
                                                        exit 1;
                                                }
                                        } else {
                                                delete $termsent{$_};
                                        }
                                }
                         }
                }
                $reloading = 0;
                do_log("Child processes terminated, restarting with new configuration.");
                $SIG{CHLD} = 'DEFAULT'; # restore
                goto RESTART;
        }
        do_log("Exiting abnormally - this should not happen.");
        exit 1; # not reached
    } else {
        $multiprocessmode = 0;
        if ($forkprobes ne "yes") {
                do_log("Not entering multiprocess mode because the 'concurrentprobes' variable is not set.");
                for my $p (keys %$probes) {
                        for my $what (qw(offset step)) {
                                do_log("Warning: probe-specific parameter '$what' ignored for probe $p in single-process mode." )
                                        if defined $cfg->{Probes}{$p}{$what};
                        }
                }
        } elsif ($opt{debug}) {
                do_debuglog("Not entering multiprocess mode with '--debug'. Use '--debug-daemon' for that.")
        } elsif (keys %$probes == 1) {
                do_log("Not entering multiprocess mode for just a single probe.");
                $myprobe = (keys %$probes)[0]; # this way we won't ignore a probe-specific step parameter
        }
    }
KID:
    my $offset;
    my $step; 
    my $gothup = 0;
    my $changeprocessnames = $cfg->{General}{changeprocessnames} ne "no";
    $SIG{HUP} = sub {
        do_log("Got HUP signal, " . ($multiprocessmode ? "exiting" : "restarting") . " gracefully.");
        $gothup = 1;
    };
    for my $sig (qw(INT TERM)) {
        $SIG{$sig} = sub {
                do_log("got $sig signal, terminating.");
                exit 1;
        }
    }
    if (defined $myprobe) {
        $offset = $probes->{$myprobe}->offset() || 'random';
        $step = $probes->{$myprobe}->step();
        $0 .= " [$myprobe]" if $changeprocessnames;
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

    my $now = Time::HiRes::time();
    my $longprobe = 0;
    while (1) {
        unless ($opt{nosleep} or $opt{debug}) {
                my $sleeptime = $step - fmod($now-$offset, $step);
                my $logmsg = "Sleeping $sleeptime seconds.";
                if ($longprobe && $step-$sleeptime < 0.3) {
                    $logmsg = "NOT sleeping $sleeptime seconds, running probes immediately.";
                    $sleeptime = 0;
                }
                if (defined $myprobe) {
                        $probes->{$myprobe}->do_debug($logmsg);
                } else {
                        do_debuglog($logmsg);
                }
                if ($sleeptime > 0) {
                    Time::HiRes::sleep($sleeptime);
                }
                last if checkhup($multiprocessmode, $gothup) && reload_cfg($cfgfile);
        }
        my $startts = Time::HiRes::time();
        run_probes $probes, $myprobe; # $myprobe is undef if running without 'concurrentprobes'
        my %sortercache;
        if ($opt{'master-url'}){            
            my $new_conf = Smokeping::Slave::submit_results $slave_cfg,$cfg,$myprobe,$probes;
            if ($new_conf && !$gothup){
                do_log('server has new config for me ... HUPing the parent');
                kill_smoke $cfg->{General}{piddir}."/smokeping.pid", SIGHUP; 
                # wait until the parent signals back if it didn't already
                sleep if (!$gothup);
                if (!$gothup) {
                    do_log("Got an unexpected signal while waiting for SIGHUP, exiting");
                    exit 1;
                }
                if (!$multiprocessmode) {
                    load_cfg_slave(\%opt);
                    last;
                }
             }
        } else {
            update_rrds $cfg, $probes, $cfg->{Targets}, $cfg->{General}{datadir}, $myprobe, \%sortercache;
            save_sortercache($cfg,\%sortercache,$myprobe);
        }
        exit 0 if $opt{debug};
        $now = Time::HiRes::time();
        my $runtime = $now - $startts;
        $longprobe = 0;
        if ($runtime > $step) {
                $longprobe = 1;
                my $warn = "WARNING: smokeping took $runtime seconds to complete 1 round of polling. ".
                "It should complete polling in $step seconds. ".
                "You may have unresponsive devices in your setup.\n";
                if (defined $myprobe) {
                        $probes->{$myprobe}->do_log($warn);
                } else {
                        do_log($warn);
                }
        }
        elsif ($runtime > $step * 0.8) {
                $longprobe = 1;
                my $warn = "NOTE: smokeping took $runtime seconds to complete 1 round of polling. ".
                "This is over 80% of the max time available for a polling cycle ($step seconds).\n";
                if (defined $myprobe) {
                        $probes->{$myprobe}->do_log($warn);
                } else {
                        do_log($warn);
                }
        }
        last if checkhup($multiprocessmode, $gothup) && reload_cfg($cfgfile);
    }
    $0 =~ s/ \[$myprobe\]$// if $changeprocessnames;
    goto RESTART;
}

sub checkhup ($$) {
        my $multiprocessmode = shift;
        my $gothup = shift;
        if ($gothup) {
                if ($multiprocessmode) {
                        do_log("Exiting due to HUP signal.");
                        exit 0;
                } else {
                        do_log("Restarting due to HUP signal.");
                        return 1;
                }
        }
        return 0;
}

sub reload_cfg ($) {
        my $cfgfile = shift;
        return 1 if exists $opt{'master-url'};
        my ($oldcfg, $oldprobes) = ($cfg, $probes);
        do_log("Reloading configuration.");
        $cfg = undef;
        $probes = undef;
        eval { load_cfg($cfgfile) };
        if ($@) {
                do_log("Reloading configuration from $cfgfile failed: $@");
                ($cfg, $probes) = ($oldcfg, $oldprobes);
                return 0;
        }
        return 1;
}
        

sub gen_imgs ($){

  my $cfg = shift;
  my $modulemodtime;
  for (@INC) {
        ( -f "$_/Smokeping.pm" ) or next;
        $modulemodtime = (stat _)[9];
        last;
  }
  if (not -r $cfg->{General}{imgcache}."/rrdtool.png" or
      (defined $modulemodtime and $modulemodtime > (stat _)[9])){
open W, ">".$cfg->{General}{imgcache}."/rrdtool.png" 
   or do { warn "WARNING: creating $cfg->{General}{imgcache}/rrdtool.png: $!\n"; return 0 };
binmode W;
print W unpack ('u', <<'UUENC');
&B5!.1PT*
"&@H`
M````#4E(1%(```!D````'@@#````[85+P0```;Q03%1%3$Q,;8_U;I#X2TM+
M2TI'34U-;Y/_;I'[145%3$M)1T=';8_W<)7_;I+]34U/6F^N2DI*;I#Z24E)
M/S\_:(3<6&F=5%QVX.#@9X+3;([S;(WQ5%142TI%7GK.R<G)6&:-4EIP4E)2
M4%!02DE$1T4\:8KLGY^?66>13D]02DA`L;&Q4&&3:(;@9X/9Q<7%;&QL7EY>
M0T-#2DA"M+2TF9F9AX>'9F9F4%1A8&!@/#P\K*RLJ:FII*2DG)R<46*6>WM[
M='1T248]2$0W-#0T:(?DVMK:U-349(#1E965BHJ*@8&!?GY^=W=W45=J:6EI
M8V-C3U)=65E93E!62TQ0M[>W7W.Q6VR@.3DY<9C_ZNKJ:8CG8'C`O;V]7G*L
MDI*2C8V-<7%Q;FYN7%Q<35!:;I+^\/#P9H;G9X7>W=W=U]?79'_.@X.#4%5D
M3$Y5]?7UXN+B6VZH56FE6VN;5V>5CX^/5%^!351GY^?G8GS+87K&87>Z7G2U
MK:VM5V2,3UV)3%!?5E965555_?W]Y.3DS\_/56*&3UM^3UEW:8OTR\O+56.0
M5F!^1T9"87[89X+5S<W-1T$P1T$N56ZV4V&-Q*CET```!GE)1$%42,><U,V+
<VD`4`/"9,68(F;A-<665E`;<H%)SR<7;@B)X"@``
MA$B"*)X4A47!#RRK8GO:#_:+;?L/]ST'=5NEAPY(,L_)_-Z;IR$PSAB5@PUB
MDB`D>6[L`S,%%J0^JW+JQ'Z28&#ST.9G3?+O<7G!*?L$-P=$U^'#A+U',$!9
MRSX@.#TO(E)0J?@/Q*G7<W@5(2(RD-T&)`(),`:L^J)`&A+1Y/.)A);`ZV%V
I&M';FW%ODH--^OX68>W'\;B;P^1M;8MDZ^DASKFOA:,9(.M1!:NR@@H`
MC-"2>VD?<!8TE1,(*]N6]A8#PK]())W):S\F64!^6HB8KO^6C[)8"XF'=08-
M<LN^1A+VTDVGW6A4Q+KRP9WK#MW&/$B=1*I>J4MU:OQ*2`0"7H3(%!%4%:U9
M9E"2O18,2^3"UI2",$Q598(6B$84?]DRN3"X&&;R)XZK6RC,AAQ:$,A*MH&V
J"8D'9(>06H?".)^@`9II7\X%W*Q6*N7.)DGR90[AJ,ZIZOK*4>.9*H0*
MF(C&B+P+=,<'Q)IA5P:C^8I3XV9>"'WD7KS4JTG5QM?2'+K*-M7;-J.B>XSH
M')*&_-<I(A'=Q(#N1(0<(35E`XV??/2\=18RO[=2!0$[9*I#-&LDO#:IL>H=
M'5?N^J(/2+I")`(!%Q16#]\C5=R4GGF[_TFI`_-<D6B+%J6M)\L%Q"F1H&%2
M-KBO_=WX^F+4X="`L2815KZM+#'0?(\\I[>-U_;(D@(2D@\+L4<&GD0>%D=(
M.5.-8:%Q'4H$]JQ%*J5F(R41T[5+M3BG;]T=XJVPDB1)S1%9Y'>5X'%U@LL3
MR.,#+.$'I'KE,&"3$F'.U;<&=D2?*EN$-RI5;XH]F9:*,63QZE>Q4`8]*3/:
M[Q9/()8205?$W1ZQO(X!ZE0BD#$08/1!101RSMJU`5[O%U!A*U:TG@.5-I[Q
8G/OGW@E$\2;X>S**.T0I13H&%(G(83@*
MOCR>!$Y46^EQ6,,89'?S72/6%)_@^%6W1/Y$?G=2]B]+0U$<OWF]>;T1K2U8
ML!AMUM`5<V,OZ#;3,LV7Y1`DD<2WBC1+^T%Z^D'JL:<7BB#ZC[LKS>JIH`[[
MX9SO[OE^[AF[-Q&+(/&+YTZ?BIU\'$%B9Q]2X?;5Q*E8XG$$B45Q]O[-.RD0
M0>[=/4GMZ(D']YXGHOD2=^]%],R;$S%:GKW\Y@:@$.JW@SR[=N7*"[J/U#N:
M7'NR%S)O:7*%)E2@;UZ\O'0]ONW)W#OS_.XSAF:IS/-;MYY^S'S3X8VWYQ\]
M^O`Y&5V=+ZY=N?9LVY",Q^/)71+_DT`EJNWC0NK"MDZE4A?V>I*6R1^-_S4@
M^/\@QXT@9(X[X@U@_N;#PJ^M[._V!>L_4`P91(':0?A]\1;(9)7!9.\(T*][
M:+:C=<)Q.QKD51X0C`E"F,5-CR$$M&NM^AC3#-->@G(K0E'DM2<6Y&\$0L)A
M#F,68<)B"%B,,9.?EG#4ZQ%(C5C:R>#`WT$><'+@NF,NWUC91SY;4D;>,%?2
M2Y.Y6Y?A7"GUF]%4N+_2;(2C%F=85!5]/AR2@6]90GI<\UVG_,DIN$4HU/&D
M/EJ7(*[;`[[V'9+7-451LV/-SBX%@P^<CCTQBY9F#9826=9"U\8`<=G*`S,-
MAW2F0]743=L0.S96[$;?!@71[GM86P\LWL@=T)79OI;+B8V`S^TAK5F742U'
MK)<6NC%M!-7F1"W6-+W<DXBHC%0+`Q)JA4*?`4<L@+*E.9T5%AN0Z/6YYI."
;5VYVVN*`=%]Q.9[+5O-ZO]BF=@_T'R#5,O(*
00&D$8T368=-A'+58J,E="@``
M>9]MZ!L(N,)1%KM*M04II%$;.4):'!%=;.N*SUI>?FX>OL\RW<57R.NRX#:0
M8@=C9@]Q^#91!W,W%(!A''!MA@TI9!!!<$]H0P0`5^L5.7Q0X0!@<J^+<AHC
,<81K6M>H*D11RTT*
M&<'OD,VZV>JT!,CN_RY87$P+K*,M>7Y67E9XWFQUFKXEEQ>2,:5E!P/(K@^F
MO4EEFJ:3#*G6'W\J,91:G4RY6F766Y5G)4@_5]CCQI7RH3G7-9Y?*F`;`@1H
6(Z0YLX%D;F$.&9050X32,H`24_0Q"@``
M9P8`,"T)&R@)=!)'[**16D((T%J"DF2Y4$!0HK4`D10]0,Z++2+GCWX]L!.Q
MX\]:K:KJN4UCI^)JQU.#GR^%0[/JJRL![FK)\HSC]T,P,_UJCF9?`'&L38BX
/N=]>`````$E%3D2N0F""
UUENC
close W;
}

  if (not -r $cfg->{General}{imgcache}."/smokeping.png" or
      (defined $modulemodtime and $modulemodtime > (stat _)[9])){
open W, ">".$cfg->{General}{imgcache}."/smokeping.png" 
   or do { warn "WARNING: creating $cfg->{General}{imgcache}/smokeping.png: $!\n"; return 0};
binmode W;
print W unpack ('u', <<'UUENC');
&B5!.1PT*
"&@H`
M````#4E(1%(```!D````'@@#````[85+P0```A-03%1%3$Q,____3DY._W\`
M2TM+2DI*CHZ.5555R<G)BHJ*^_O[<G)R2$A(_X``V=G9Y^?GU=75G)R<AH:'
M34U-GY^?_?W]24M-HJ*B='1T_WT`^/CXSL[.M[>W@H*"8F)B54Y(T='1?W]_
M<'!O:VML4U-34%!0NKJZM;6UJZRLD)"0>WQ\75U=6%A81DI.\GL&\O+RPL+"
M>7EY7EY>6EI:0DE0]/3TX.#@O[^_W=W=Q,3$IZ>HEY>7E)24DI*2=G9V_X$`
MXN+BFIJ:B8F)?7U];FYN965E<5<\BEXRS7(7Y>7EO+R\L+"PJ:FIGZ"AEI:6
M:6EI:&AH]O;V[^_O[N[NZ>GIYN;GU]?7T]/3R\O+QL;&KZ^OK:VMA86%A(2$
M4E)2E6$MX7<-_X,)^7T#]_?WZ^OKT-#0N;FYL[*RBXR->'AX65E92TY09U1"
M?%HXJV<DNVP=U7,2[7H(]GT&_]VYKJZNI*2D4$U)IF8GIF4FQ6X9]804_'\"
M__OURM'8C(>#N)1O9E]8\:!.K'U-E&D_=ED]A%TUW8,J_(\DLFHB_XP8W'4/
MZ7H,^OKZXN3EZ.+<U-?;T\W'WLJU]-.RT<"O_]:N\L.4_\B0=7R#I)*`RZ5_
M_[ETXJITCGYN8VAL\ZQFAW9FVYU@KH%4BV]2O(9/85=,@&9+B&='G'!$_Z!"
MM7I`S8$VHF4HQW8FUWXEZ84BL&DAOVT<R=ODT0``!-I)1$%42,?MU&>3TD`8
M!_!L-H%`@API$.K1.X(@13C@:'K5.\MU3SU[[[WWWGOOO7]$-X&[L8VCHX[C
1C/\7S.9)YOGMSBZ+_1M9%0H`
MK>*P/QJ"SHWX2S2)_<G@[&`R:581V)\,KFH"8)+B/_*;$1(/Q6WQ!%D_+@S#
M2",FT:@PX7@<QR;"<*%X/,217R,$@R(7Y8>PU),9U]T%!;_5P,^<(K>R65FK
)DR.4E9Q!KG@*
/>8..#8W/1SE%H<MNU2D*
M2N(+!.^ULFQ0V?BP9FWAN_F9;,TC/RI76)HFQ7R^855<$LL==HKO<8_Z4K,S
*(P62JPQ/FJT="@``
MN#$YU;RW23M[MK;)DG=]@?1T4W:J5)7M^96M%.7SCWAC759<>F9CR6@Z,*5B
M%0F)U/4!M=T0Z&H'`&1XFBYET&"6I4!*ZW#Q`R9@6C+'!!;;>1?Y*4($[$!8
MVJ*49:M/V]XYZA1S@^W>,BJ$N^>"E"Y!DC@R)$0+0+0CQW>D!&"REQP!2T8-
M!/.H]#;<,J`66M-=7>EV06W/K_H4$9='0<I07Y[8N40]S>KF\-[LW*@OR&&)
M;%)&T+L)I#5;L#E\<P#0&D2;Z$>5?A6.%K+2:P+:X4JMYNB<"TP6FIA`.&5+
4/YBS?*6\\9[\)!#U53D.53,@50H`
M8\J\71V-!6@E/H&H*2N#D>@]:$)3]*RP"Z@->LVL:`("Q<['<;?*+`![N;FY
MCK0:G*/>66JJ+.\<T>./@L4QMF:S.0V9Y!Q_#T949WH'^@<MW2H:'T<Z1!(C
%RW8`J`H`
M:FT=5-<1=ZX5S/+2.(J8-H'4#>/NM3*R>(CO[`-)+TW*B--B`L`<H%TN<45V
:Q*]:A6KA@LH0:U\RL,7!-)!E-$+F+05@:`H`
MAI$.ZFND("'[-7`!)R&S8OQP*S#%'/@$DNRP)L+A<`@ES,F'G[`I4".MH?<3
MA)AG!F#:9PBC&@#"8%FIYY2*O0`L91>\WX:KS@-PMMOEL$1!7_8NJ=?KB9ZN
MV6!)EPW[,E7TS>).U_<14D13G+O\U9M'#W<=WYQ<?G_]^NFK'Q^\MN?@IK8#
!"@``
MNW#E^*[#1]:?B)"!?A`=[OWT\NEUN4F<C9U!*ZE]'\$2>;3?Y\:,NXQ&:+P=
M>*J!,U8?@R_&C!!.=OKOH2)<""=/Q:I^K7JHS!!,C[C2*1T&U\PMND#).Q?,
MZ;"2""GU"29+'1&$<43HEQ'2IC,G]XS!DYLWCT'C@>EUQ'CKXCL(M^TSPI.7
M;D()\3@Z4WW>O%613?L4O1+"QZ9-,V=:S5M8I72ML#YJ6LY&8(28I2B^BCK3
MAB'*'ZQ?>[:`[\*8\6K[T@<0KI$0_5MHW.L_!#7-SS3P,H5&",$\4_@TE;:D
MS=0(FY"N%9IMX0W=,UEG_6C45@:#+FD8IH-!)X<&N#,8%.>/_UGI?;N-^W/L
MRP82:8.;KHN'-9KFM45XIQ)\CA!YS4&%SL"WC#H]C5W!/1X/CF,_F.9%\'3H
MR60T]P:R<2IVM*AIGEJ$D]<<V2TC*!R._TS7KY')Q2+4K-/+R,YQ1+].`XM%
M>>-_.0C1;-^Y\?0Z/;9F0]M:_?:VG1%L^H:V;5ADQX8-"];_-F0'%HE(0[U>
M^FF,(MO7O5Z-;X0+([\+^4;T)R#<M`EJ%F"_`SFU\-M]N!EM"T]]6!O!_DX^
5`F@QYX#.PQY?`````$E%3D2N0F""
UUENC
close W;
}
}


=head1 NAME

Smokeping.pm - SmokePing Perl Module

=head1 OVERVIEW

Almost all SmokePing functionality sits in this Module.
The programs L<smokeping|smokeping> and L<smokeping.cgi|smokeping.cgi> are merely
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

Tobias Oetiker E<lt>tobi@oetiker.chE<gt>

Niko Tyni E<lt>ntyni@iki.fiE<gt>

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
