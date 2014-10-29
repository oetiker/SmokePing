package Smokeping::probes::OpenSSHEOSPing;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::OpenSSHEOSPing>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::OpenSSHEOSPing>

to generate the POD document.

=cut

use strict;

use base qw(Smokeping::probes::basefork);
use Net::OpenSSH;
use Carp;

my $e = "=";
sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::OpenSSHEOSPing - Arista EOS SSH Probe for SmokePing
DOC
		description => <<DOC,
Connect to Arista EOS via OpenSSH to run ping commands.
This probe uses the "ping" cli of the Arista EOS.  You have
the option to specify which interface the ping is sourced from as well.
DOC
		notes => <<DOC,
${e}head2 EOS configuration

The EOS device should have a username/password configured, and
the ssh server must not be disabled.

Make sure to connect to the remote host once from the commmand line as the
user who is running smokeping. On the first connect ssh will ask to add the
new host to its known_hosts file. This will not happen automatically so the
script will fail to login until the ssh key of your EOS box is in the
known_hosts file.

${e}head2 Requirements

This module requires the  L<Net::OpenSSH> and L<IO::Pty> perl modules.
DOC
		authors => <<'DOC',
Bill Fenner E<lt>fenner@aristanetworks.comE<gt>

based on L<Smokeping::Probes::OpenSSHJunOSPing> by Tobias Oetiker E<lt>tobi@oetiker.chE<gt>,
which itself is
based on L<Smokeping::probes::TelnetJunOSPing> by S H A N E<lt>shanali@yahoo.comE<gt>.
DOC
	}
}

sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    $self->{pingfactor} = 1000; # Gives us a good-guess default

    return $self;
}

sub ProbeDesc($){
    my $self = shift;
    my $bytes = $self->{properties}{packetsize};
    return "Arista EOS - ICMP Echo Pings ($bytes Bytes)";
}

sub pingone ($$){
    my $self = shift;
    my $target = shift;
    my $source = $target->{vars}{source};
    my $dest = $target->{vars}{host};
    my $psource = $target->{vars}{psource};
    my @output = ();
    my $login = $target->{vars}{eosuser};
    my $password = $target->{vars}{eospass};
    my $bytes = $self->{properties}{packetsize};
    my $pings = $self->pings($target);
    my $unpriv = $target->{vars}{unpriv} || 0;

    # do NOT call superclass ... the ping method MUST be overwriten
    my %upd;
    my @args = ();

    my $ssh = Net::OpenSSH->new(
        $source,
        $login ? ( user => $login ) : (),
        $password ? ( password => $password ) : (),
        timeout => 60,
        batch_mode => 1
    );
    if ($ssh->error) {
        $self->do_log( "OpenSSHEOSPing connecting $source: ".$ssh->error );
        return ();
    };

    if ( $unpriv ) {
        @output = $ssh->capture("ping $dest");
    } else {
        if ( $psource ) {
            @output = $ssh->capture("ping $dest repeat $pings size $bytes source $psource");
        } else {
            @output = $ssh->capture("ping $dest repeat $pings size $bytes");
        }
    }

    if ($ssh->error) {
        $self->do_log( "OpenSSHEOSPing running commands on $source: ".$ssh->error );
        return ();
    };

    if ($output[ 0 ] !~ /^PING/) {
        $self->do_log( "OpenSSHEOSPing got error on $source for $dest: "." / ".join( @output ) );
        return ();
    }
    my @times = ();
    for (@output){
    	chomp;
        /^\d+ bytes from .+: icmp_req=\d+ ttl=\d+ time=(\d+\.\d+) ms$/ and push @times,$1;
    }
    @times = map {sprintf "%.10e", $_ / $self->{pingfactor}} sort {$a <=> $b} @times;
    return @times;
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		packetsize => {
			_doc => <<DOC,
The (optional) packetsize option lets you configure the packetsize for
the pings sent.
DOC
			_default => 100,
			_re => '\d+',
			_sub => sub {
				my $val = shift;
				return "ERROR: packetsize must be between 12 and 64000"
					unless $val >= 12 and $val <= 64000;
				return undef;
			},
		},
	});
}

sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		_mandatory => [ 'eosuser', 'eospass', 'source' ],
		source => {
			_doc => <<DOC,
The source option specifies the EOS device that is going to run the ping commands.  This
address will be used for the ssh connection.
DOC
			_example => "192.168.2.1",
		},
		psource => {
			_doc => <<DOC,
The (optional) psource option specifies an alternate IP address or
Interface from which you wish to source your pings from.  Routers
can have many many IP addresses, and interfaces.  When you ping from a
router you have the ability to choose which interface and/or which IP
address the ping is sourced from.  Specifying an IP/interface does not 
necessarily specify the interface from which the ping will leave, but
will specify which address the packet(s) appear to come from.  If this
option is left out the EOS Device will source the packet automatically
based on routing and/or metrics.  If this doesn't make sense to you
then just leave it out.
DOC
			_example => "192.168.2.129",
		},
		eosuser => {
			_doc => <<DOC,
The eosuser option allows you to specify a username that has ping
capability on the EOS Device.
DOC
			_example => 'user',
		},
		eospass => {
			_doc => <<DOC,
The eospass option allows you to specify the password for the username
specified with the option eosuser.
DOC
			_example => 'password',
		},
                unpriv => {
                        _doc => <<DOC,
If the account is unprivileged, specify the 'unpriv' option.
You must also configure "pings = 5", since that is the only
value supported, and values specified for packetsize or
psource are ignored.
DOC
                        _example => '1',
                },
	});
}

1;
