package Smokeping::probes::RemoteFPing;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::RemoteFPing>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::RemoteFPing>

to generate the POD document.

=cut

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::RemoteFPing - Remote FPing Probe for SmokePing
DOC
		description => <<DOC,
Integrates the remote execution of FPing via ssh/rsh into smokeping.
The variable B<binary> must point to your copy of the ssh/rsh program.
The variable B<rbinary> must point to your copy of the fping program 
at the remote end.
DOC
		notes => <<'DOC',
It is important to make sure that you can access the remote machine
without a password prompt, otherwise this probe will not work properly.
To test just try something like this:

    $ ssh foo@HostA.foobar.com fping HostB.barfoo.com 

The next thing you see must be fping's output.

The B<rhost>, B<ruser> and B<rbinary> variables used to be configured in
the Targets section of the first target or its parents They were moved
to the Probes section, because the variables aren't really target-specific
(all the targets are measured with the same parameters). The Targets
sections aren't recognized anymore.
DOC
		authors => <<'DOC',
 Luis F Balbinot <hades@inf.ufrgs.br>

 Niko Tyni <ntyni@iki.fi>

 derived from Smokeping::probes::FPing by

 Tobias Oetiker <tobi@oetiker.ch>
DOC
		bugs => <<DOC
This functionality should be in a generic 'remote execution' module
so that it could be used for the other probes too.
DOC
	}
}

use strict;
use base qw(Smokeping::probes::FPing);

sub ProbeDesc($) {
    my $self = shift;
    my $superdesc = $self->SUPER::ProbeDesc;
    return "Remote $superdesc";
}

sub binary {
    my $self = shift;
    my @ret = ( $self->SUPER::binary );
    for my $what (qw(ruser rhost rbinary)) {
        my $prefix = ($what eq 'ruser' ? "-l" : "");
        if (defined $self->{properties}{$what}) {
		push @ret, $prefix . $self->{properties}{$what};
        } 
    }
    return @ret;
}

sub probevars {
	my $class = shift;
	my $h = $class->SUPER::probevars;
	$h->{rbinary} = $h->{binary};
	delete $h->{binary};
	delete $h->{rbinary}{_sub}; # we can't check the remote program's -x bit
	@{$h->{_mandatory}} = map { $_ ne 'binary' ? $_ : 'rbinary' } @{$h->{_mandatory}};
	return $class->_makevars($h, {
		_mandatory => [ 'binary', 'rhost' ],
		binary => {
			_doc => <<DOC,
This variable specifies the path of the remote shell program (usually ssh,
rsh or remsh). Any other script or binary that can be called as

binary [ -l ruser ] rhost rbinary

may be used.
DOC
			_example => '/usr/bin/ssh',
			_sub => sub {
				my $val = shift;
				-x $val or return "ERROR: binary '$val' is not executable";
				return undef;
			},
		},
		rhost => {
			_doc => <<DOC,
The B<rhost> option specifies the remote device from where fping will
be launched.
DOC
			_example => 'my.pinger.host',
		},
		ruser => {
			_doc => <<DOC,
The (optional) B<ruser> option allows you to specify the remote user,
if different from the one running the smokeping daemon.
DOC
			_example => 'foo',
		},
	});
}

1;
