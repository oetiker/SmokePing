package probes::base;

=head1 NAME

probes::base - Base Class for implementing SmokePing Probes

=head1 OVERVIEW
 
For the time being, please use the probes::FPing for
inspiration when implementing your own probes.

=head1 AUTHOR

Tobias Oetiker <tobi@oetiker.ch>

=cut

use vars qw($VERSION);
use Carp;
use lib qw(..);
use Smokeping;

$VERSION = 1.0;

use strict;

sub new($$)
{
    my $this   = shift;
    my $class   = ref($this) || $this;
    my $self = { properties => shift, cfg => shift, 
    name => shift,
    targets => {}, rtts => {}, addrlookup => {}};
    bless $self, $class;
    return $self;
}

sub add($$)
{
    my $self = shift;
    my $tree = shift;
    
    $self->{targets}{$tree} = shift;
}

sub ping($)
{
    croak "this must be overridden by the subclass";
}

sub round ($) {
    return sprintf "%.0f", $_[0];
}

sub ProbeDesc ($) {
    return "Probe which does not overrivd the ProbeDesc methode";
}    

sub rrdupdate_string($$)
{   my $self = shift;
    my $tree = shift;
#    print "$tree -> ", join ",", @{$self->{rtts}{$tree}};print "\n";    
    # skip invalid addresses
    my $pings = $self->_pings($tree);
    return "U:${pings}:".(join ":", map {"U"} 1..($pings+1)) 
        unless defined $self->{rtts}{$tree} and @{$self->{rtts}{$tree}} > 0;
    my $entries = scalar @{$self->{rtts}{$tree}};
    my @times = @{$self->{rtts}{$tree}};
    my $loss = $pings - $entries;
    my $median = $times[int($entries/2)] || 'U';
    # shift the data into the middle of the times array
    my $lowerloss = int($loss/2);
    my $upperloss = $loss - $lowerloss;
    @times = ((map {'U'} 1..$lowerloss),@times, (map {'U'} 1..$upperloss));
    my $age;
    if ( -f $self->{targets}{$tree}.".adr" ) {
      $age =  time - (stat($self->{targets}{$tree}.".adr"))[9];
    } else {
      $age = 'U';
    }
    if ( $entries == 0 ){
      $age = 'U';
      $loss = 'U';
      if ( -f $self->{targets}{$tree}.".adr"
	   and not -f $self->{targets}{$tree}.".snmp" ){
	unlink $self->{targets}{$tree}.".adr";
      }
    } ;
    return "${age}:${loss}:${median}:".(join ":", @times);
}

sub addresses($)
{
    my $self = shift;
    my $addresses = [];
    $self->{addrlookup} = {};
    foreach my $tree (keys %{$self->{targets}}){
        my $target = $self->{targets}{$tree};
        if ($target =~ m|/|) {
	   if ( open D, "<$target.adr" ) {
	       my $ip;
	       chomp($ip = <D>);
	       close D;
	       
	       if ( open D, "<$target.snmp" ) {
		   my $snmp = <D>;
		   chomp($snmp);
		   if ($snmp ne Smokeping::snmpget_ident $ip) {
		       # something fishy snmp properties do not match, skip this address
		       next;
		   }
                   close D;
	       }
	       $target = $ip;
	   } else {
	       # can't read address file skip
	       next;
	   }
	}
        $self->{addrlookup}{$target} = () 
                unless defined $self->{addrlookup}{$target};
        push @{$self->{addrlookup}{$target}}, $tree;
	push @{$addresses}, $target;
    };    
    return $addresses;
}

sub debug {
        my $self = shift;
        my $newval = shift;
        $self->{debug} = $newval if defined $newval;
        return $self->{debug};
}

sub do_debug {
        my $self = shift;
        return unless $self->debug;
        $self->do_log(@_);
}

sub do_fatal {
        my $self = shift;
        $self->do_log("Fatal:", @_);
        croak(@_);
}

sub do_log {
        my $self = shift;
        Smokeping::do_log("$self->{name}:", @_);
}

sub report {
	my $self = shift;
	my $count = $self->target_count;
	my $offset = $self->offset_in_seconds;
	my $step = $self->step;
	$self->do_log("probing $count targets with step $step s and offset $offset s.");
}

sub step {
	my $self = shift;
	my $rv = $self->{cfg}{Database}{step};
	unless (defined $self->{cfg}{General}{concurrentprobes}
	    and $self->{cfg}{General}{concurrentprobes} eq 'no') {
		$rv = $self->{properties}{step} if defined $self->{properties}{step};
	}
	return $rv;
}

sub offset {
	my $self = shift;
	my $rv = $self->{cfg}{General}{offset};
	unless (defined $self->{cfg}{General}{concurrentprobes}
	    and $self->{cfg}{General}{concurrentprobes} eq 'no') {
		$rv = $self->{properties}{offset} if defined $self->{properties}{offset};
	}
	return $rv;
}

sub offset_in_seconds {
	# returns the offset in seconds rather than as a percentage
	# this is filled in from the initialization in Smokeping::main
	my $self = shift;
	my $newval = shift;
	$self->{offset_in_seconds} = $newval if defined $newval;
	return $self->{offset_in_seconds};
}

# the "public" method that takes a "target" argument is used by the probes
# the "private" method that takes a "tree" argument is used by Smokeping.pm
# there's no difference between them here, but we have to provide both

sub pings {
	my $self = shift;
	my $target = shift;
	# $target is not used; basefork.pm overrides this method to provide a target-specific parameter
	my $rv = $self->{cfg}{Database}{pings};
	$rv = $self->{properties}{pings} if defined $self->{properties}{pings};
	return $rv;
}


sub _pings {
	my $self = shift;
	my $tree = shift;
	# $tree is not used; basefork.pm overrides this method to provide a target-specific parameter
	my $rv = $self->{cfg}{Database}{pings};
	$rv = $self->{properties}{pings} if defined $self->{properties}{pings};
	return $rv;
}

sub target_count {
	my $self = shift;
	return scalar keys %{$self->{targets}};
}

1;
