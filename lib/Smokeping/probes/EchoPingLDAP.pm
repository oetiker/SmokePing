package Smokeping::probes::EchoPingLDAP;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::EchoPingLDAP>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::EchoPingLDAP>

to generate the POD document.

=cut

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::EchoPingLDAP - an echoping(1) probe for SmokePing
DOC
		overview => <<DOC,
Measures LDAP roundtrip times for SmokePing with the echoping_ldap plugin. 
DOC
		authors => <<'DOC',
Niko Tyni <ntyni@iki.fi>
DOC
        notes => <<'DOC',
The I<fill>, I<size> and I<udp> EchoPing variables are not valid.

Plugins, including echoping_ldap, are available starting with echoping version 6.
DOC
		see_also => <<DOC,
L<Smokeping::probes::EchoPing>, 
L<Smokeping::probes::EchoPingPlugin>
DOC
	}
}

use strict;
use base qw(Smokeping::probes::EchoPingPlugin);
use Carp;

sub plugin_args {
    my $self = shift;
    my $target = shift;
    my @args;
    my $req = $target->{vars}{ldap_request};
    push @args, "-r $req" if $req;

    my $base = $target->{vars}{ldap_base};
    push @args, "-b $base" if $base;
    
    my $scope = $target->{vars}{ldap_scope};
    push @args, "-s $scope" if $scope;

    return @args;
}

sub ProbeDesc($) {
	return "LDAP pings using the echoping_ldap plugin";
}

sub targetvars {
	my $class = shift;
	my $h = $class->SUPER::targetvars;
	delete $h->{udp};
	delete $h->{fill};
	delete $h->{size};
    $h->{_mandatory} = [ grep { $_ ne "plugin" } @{$h->{_mandatory}}];
    $h->{plugin}{_default} = 'ldap';
    $h->{plugin}{_example} = '/path/to/ldap.so';
    return $class->_makevars($h, {
        ldap_request => {
            _doc => <<DOC,
The echoping_ldap '-r' option:
the request to the LDAP server, in LDAP filter language.
DOC
            _example => '(objectclass=*)',
        },
        ldap_base => {
            _doc => <<DOC,
The echoping_ldap '-b' option:
base of the search.
DOC
            _example => 'dc=current,dc=bugs,dc=debian,dc=org',
        },
        ldap_scope => {
            _doc => <<DOC,
The echoping_ldap '-s' option:
scope of the search, "sub", "one" or "base".
DOC
            _example => 'one',
        },
    },
    );
}

1;
