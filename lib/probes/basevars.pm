package probes::basevars;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man probes::basevars>

to view the documentation or the command

C<smokeping -makepod probes::basevars>

to generate the POD document.

=cut

use strict;
use probes::base;
use base qw(probes::base);

my $e = "=";
sub pod_hash {
    return {
    	name => <<DOC,
probes::basevars - Another Base Class for implementing SmokePing Probes
DOC
	overview => <<DOC,
Like probes::base, but supports host-specific variables for the probe.
DOC
	description => <<DOC,
Provides the method `targets' that returns a list of hashes.
The hashes contain the entries:

${e}over

${e}item addr

The address of the target.

${e}item vars 

A hash containing variables defined in the corresponding
config section.

${e}item tree 

The unique index that `probe::base' uses for targets.

There's also the method 'vars' that returns the abovementioned
hash corresponding to the 'tree' index parameter.

${e}back
DOC
	authors => <<'DOC',
Niko Tyni <ntyni@iki.fi>
DOC
	bugs => <<DOC,
Uses `probes::base' internals too much to be a derived class, but 
I didn't want to touch the base class directly.
DOC
	see_also => <<DOC,
probes::base(3pm), probes::EchoPing(3pm)
DOC
    }
}

sub add($$)
{
    my $self = shift;
    my $tree = shift;
    
    $self->{targets}{$tree} = shift;
    $self->{vars}{$tree} = { %{$self->{properties}}, %$tree };
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
		push @targets, { addr => $_, vars => $self->{vars}{$tree}, tree => $tree };
	}
	return \@targets;
}

sub vars {
	my $self = shift;
	my $tree = shift;
	return $self->{vars}{$tree};
}

sub ProbeDesc {
	return "Probe that supports variables and doesn't override the ProbeDesc method";
}

return 1;