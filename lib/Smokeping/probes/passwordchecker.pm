package Smokeping::probes::passwordchecker;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::passwordchecker>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::passwordchecker>

to generate the POD document.

=cut

use strict;
use Smokeping::probes::basefork;
use base qw(Smokeping::probes::basefork);
use Carp;

my $e = "=";
sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::passwordchecker - A Base Class for implementing SmokePing Probes
DOC
		overview => <<DOC,
Like Smokeping::probes::basefork, but supports a probe-specific configuration file
for storing passwords and a method for accessing them.
DOC

		description => <<DOC,
${e}head2 synopsis with more detail

SmokePing main configuration file:

 *** Probes ***
 + MyPasswordChecker
 # location of the file containing usernames and passwords
 passwordfile = /usr/share/smokeping/etc/passwords

The specified password file:

 # host:username:password
 host1:joe:hardlyasecret
  # comments and whitespace lines are allowed

 host2:sue:notasecreteither

${e}head2 Actual description

In implementing authentication probes, it might not be desirable to store
the necessary cleartext passwords in the SmokePing main configuration
file, since the latter must be readable both by the SmokePing daemon
performing the probes and the CGI that displays the results. If the
passwords are stored in a different file, this file can be made readable
by only the user the daemon runs as. This way we can be sure that nobody
can trick the CGI into displaying the passwords on the Web.

This module reads the passwords in at startup from the file specified
in the probe-specific variable `passwordfile'. The passwords can later
be accessed and modified by the B<password> method, that needs the corresponding
host and username as arguments.

${e}head2 Password file format

The password file format is simply one line for each triplet of host,
username and password, separated from each other by colons (:).

Comment lines, starting with the `#' sign, are ignored, as well as
empty lines.
DOC
		authors => <<'DOC',
Niko Tyni <ntyni@iki.fi>
DOC

		bugs => <<DOC,
The need for storing cleartext passwords can be considered a bug in itself.
DOC

		see_also => <<DOC,
L<Smokeping::probes::basefork>, L<Smokeping::probes::Radius>, L<Smokeping::probes::LDAP>
DOC
	}
}

sub ProbeDesc {
	return "probe that can fork, knows about passwords and doesn't override the ProbeDesc method";
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		passwordfile => {
			_doc => "Location of the file containing usernames and passwords.",
			_example => '/some/place/secret',
			_sub => sub {
				my $val = shift;
				-r $val or $ENV{SERVER_SOFTWARE} or return "ERROR: password file $val is not readable.";
				return undef;
			},
		},
	});
}

sub new {
        my $proto = shift;
        my $class = ref($proto) || $proto;
        my $self = $class->SUPER::new(@_);

	# no need for this if we run as a cgi
	unless ($ENV{SERVER_SOFTWARE}) {

	        if (defined $self->{properties}{passwordfile}) {
			my @stat = stat($self->{properties}{passwordfile});
			my $mode = $stat[2];
			carp("Warning: password file $self->{properties}{passwordfile} is world-readable\n") 
				if defined $mode and $mode & 04;
				
			open(P, "<$self->{properties}{passwordfile}") 
				or croak("Error opening specified password file $self->{properties}{passwordfile}: $!");
			while (<P>) {
				chomp;
				next unless /\S/;
				next if /^\s*#/;
				my ($host, $username, $password) = split(/:/);
				carp("Line $. in $self->{properties}{passwordfile} is invalid"), next unless defined $host and defined $username and defined $password;
				$self->password($host, $username, $password);
			}
			close P;
	        }
	}


        return $self;
}

sub password {
	my $self = shift;
	my $host = shift;
	my $username = shift;
	my $newval = shift;
	$self->{password}{$host}{$username} = $newval if defined $newval;
	return $self->{password}{$host}{$username};
}

1;
