package Smokeping::probes::basevars;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::basevars>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::basevars>

to generate the POD document.

=cut

use strict;
use Smokeping::probes::base;
use base qw(Smokeping::probes::base);

my $e = "=";
sub pod_hash {
    return {
    	name => <<DOC,
Smokeping::probes::basevars - Another Base Class for implementing SmokePing Probes
DOC
	overview => <<DOC,
Like L<Smokeping::probes::base|Smokeping::probes::base>, but supports host-specific variables for the probe.
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
Uses `Smokeping::probes::base' internals too much to be a derived class, but 
I didn't want to touch the base class directly.
DOC
	see_also => <<DOC,
L<Smokeping::probes::base>, L<Smokeping::probes::EchoPing>
DOC
    }
}

sub add($$)
{
    my $self = shift;
    my $tree = shift;
    
    $self->{target_count}++;
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
        	my $vars = $self->{vars}{$tree};
        	next if defined $vars->{nomasterpoll} and $vars->{nomasterpoll} eq "yes";
        	push @targets, { addr => $_, vars => $vars, tree => $tree };
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
