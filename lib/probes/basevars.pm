package probes::basevars;

=head1 NAME

probes::basevars - Another Base Class for implementing SmokePing Probes

=head1 OVERVIEW

Like probes::base, but supports host-specific variables for the probe.

=head1 SYNOPSIS

 *** Targets ***

 menu = Top
 title = Top Page

 + branch_1
 menu = First menu
 title = First title
 host = host1
 ++ PROBE_CONF
 # vars for host host1
 var1 = foo
 var2 = bar
 
 ++ branch_1_2
 menu = Second menu
 title = Second title
 host = host2
 +++ PROBE_CONF
 # vars for host host2
 # var1 and var2 are propagated from above, override var2
 var2 = fii

 + branch_2
 # var1 and var2 are undefined here

=head1 DESCRIPTION

Provides the method `targets' that returns a list of hashes.
The hashes contain the entries:

=over

=item addr

The address of the target.

=item vars 

A hash containing variables defined in the corresponding
`PROBE_CONF' config section.

=item tree 

The unique index that `probe::base' uses for targets.

There's also the method 'vars' that returns the abovementioned
hash corresponding to the 'tree' index parameter.

=back

=head1 AUTHOR

Niko Tyni E<lt>ntyni@iki.fiE<gt>

=head1 BUGS

Uses `probes::base' internals too much to be a derived class, but 
I didn't want to touch the base class directly.

=head1 SEE ALSO

probes::base(3pm), probes::EchoPing(3pm)

=cut

use strict;
use probes::base;
use base qw(probes::base);

sub add($$)
{
    my $self = shift;
    my $tree = shift;
    
    $self->{targets}{$tree} = shift;
    $self->{PROBE_CONF}{$tree} = $tree->{PROBE_CONF};
}

sub targets {
	my $self = shift;
	my $addr = $self->addresses;
	my @targets;

	# copy the addrlookup lists to safely pop
	my %copy;

	for (@$addr) {
		@{$copy{$_}} = @{$self->{addrlookup}{$_}} unless exists $copy{$_};
		my $tree = pop @{$copy{$_}};
		push @targets, { addr => $_, vars => $self->{PROBE_CONF}{$tree},
				 tree => $tree };
	}
	return \@targets;
}

sub vars {
	my $self = shift;
	my $tree = shift;
	return $self->{PROBE_CONF}{$tree};
}

sub ProbeDesc {
	return "Probe that supports variables and doesn't override the ProbeDesc method";
}

return 1;
