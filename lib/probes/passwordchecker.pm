package probes::passwordchecker;

=head1 NAME

probes::passwordchecker - A Base Class for implementing SmokePing Probes

=head1 OVERVIEW

Like probes::basefork, but supports a probe-specific configuration file
for storing passwords and a method for accessing them.

=head1 SYNOPSYS

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

=head1 DESCRIPTION

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

=head1 PASSWORD FILE FORMAT

The password file format is simply one line for each triplet of host,
username and password, separated from each other by colons (:).

Comment lines, starting with the `#' sign, are ignored, as well as
empty lines.

=head1 AUTHOR

Niko Tyni E<lt>ntyni@iki.fiE<gt>

=head1 BUGS

The need for storing cleartext passwords can be considered a bug in itself.

=head1 SEE ALSO

probes::basefork(3pm), probes::Radius(3pm), probes::LDAP(3pm)

=cut

use strict;
use probes::basefork;
use base qw(probes::basefork);
use Carp;

sub ProbeDesc {
	return "probe that can fork, knows about passwords and doesn't override the ProbeDesc method";
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
