package Smokeping::probes::FTPtransfer;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::FTPtransfer>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::FTPtransfer>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::passwordchecker);
use Net::FTP;
use Time::HiRes qw(gettimeofday sleep);
use Carp;

my $DEFAULTINTERVAL = 1;

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::FTPtransfer - intrusive bandwidth probe
DOC
		overview => <<DOC,
This probe send and retrieve files to or from an ftp server. It will plot
the bandwidth it could use.
DOC
		description => <<DOC,
The probe uses the Net::FTP perl client to run performance tests using an
FTP server as a target. This probe is B<intrusive> as it transfers real
data. By using real data we get a fair shot at figuring out what a link is
capable of when it comes to transfering actual files.

The password can be specified either (in order of precedence, with
the latter overriding the former) in the probe-specific variable
`password', in an external file or in the target-specific variable
`password'.  The location of this external file is given in the probe-specific
variable `passwordfile'. See Smokeping::probes::passwordchecker(3pm) for the
format of this file (summary: colon-separated triplets of the form
`<host>:<username>:<password>')

The probe tries to be nice to the server and waits at least X seconds
between starting filetransfers, where X is the value of the probe 
specific `min_interval' variable ($DEFAULTINTERVAL by default).

Many variables can be specified either in the probe or in the target definition,
the target-specific variable will override the prove-specific variable.

If your transfer takes a lot of time, you may want to make sure to set the
B<timeout> and B<max_rtt> properly so that smokeping does not abort the
transfers of limit the graph size.
DOC
		authors => <<'DOC',
Tobias Oetiker <tobi@oetiker.ch> sponsored by Virtela
DOC
		bugs => <<DOC,
This probe has the capability for saturating your links, so don't use it
unless you know what you are doing.

The FTPtransfer probe measures bandwidth, but we report the number of
seconds it took to transfer the 'reference' file. This is because curently
the notion of I<Round Trip Time> is at the core of the application. It would
take some re-engineering to split this out in plugins and thus make it
configurable ...
DOC
	}
}

# returns the last part of a path
sub _get_filename ($) {
    return (split m|/|, $_[0])[-1];
}

sub ProbeDesc ($) {
        my $self = shift;  
        my $srcfile = $self->{properties}{srcfile};
        my $destfile = $self->{properties}{destfile} || _get_filename $self->{properties}{srcfile};
        my $mode = $self->{properties}{mode};
	my $size = $mode eq 'get' ? -s $destfile : -s $srcfile;
	return sprintf("FTP File transfers (%.0f KB)",$size/1024);
}

sub new {
        my $proto = shift;
        my $class = ref($proto) || $proto;
        my $self = $class->SUPER::new(@_);
        return $self;
}


sub pingone {
	my $self = shift;
	my $target = shift;
	my $host = $target->{addr};
	my $vars = $target->{vars};
	my $mininterval = $self->{properties}{min_interval};
	my $srcfile = $self->{properties}{srcfile};
	my $destfile = $self->{properties}{destfile} || _get_filename $self->{properties}{srcfile};
	my $mode = $self->{properties}{mode};
	my $username = $vars->{username};

	$self->do_log("Missing FTP username for $host"), return 
		unless defined $username;

	my $password = $self->password($host, $username) || $vars->{password};

	$self->do_log("Missing FTP password for $host/$username"), return 
		unless defined $password;

	my @options = ();
	push (@options, Timeout   => $vars->{timeout});
	push (@options, Port      => $vars->{port} ) if $vars->{port};
	push (@options, LocalAddr => $vars->{localaddr} ) if $vars->{localaddr};
	push (@options, Passive   => 1 ) if $vars->{passive} and $vars->{passive} eq 'yes';

	my @times;
	my $elapsed;

	for (1..$self->pings($target)) {
		if (defined $elapsed) {
			my $timeleft = $mininterval - $elapsed;
			sleep $timeleft if $timeleft > 0;
		}
		my $ftp = Net::FTP->new($host, @options) or 
			$self->do_log("Problem with $host: ftp session $@"), return;
		$ftp->login($username,$password) or
 		        $self->do_log("Problem with $host: ftp login ".$ftp->message), return;
		my $start = gettimeofday();
		my $ok;
		my $size;
		if ($mode eq 'get'){
			$ok = $ftp->get($srcfile,$destfile) or 
        	                $self->do_log("Problem with $host: ftp get ".$ftp->message);
			$size = -s $destfile;
		} else {
			$ok = $ftp->put($srcfile,$destfile) or 
        	                $self->do_log("Problem with $host: ftp put ".$ftp->message);
			$size = -s $srcfile;
		}
		my $end = gettimeofday();
		$ftp->quit;
		$elapsed = ( $end - $start );
		$ok or next;
		$self->do_debug("$host - $mode mode transfered $size Bytes in ${elapsed}s");
		push @times, $elapsed;
	}
	return sort { $a <=> $b } @times;
}

sub probevars {
	my $class = shift;
	my $h = $class->SUPER::probevars;
	delete $h->{timeout}{_default}; # force a timeout to be defined
	$h->{timeout}{_doc} = <<DOC;
The timeout is the maximum amount of time you will allow the probe to
transfer the file. If the probe does not succeed to transfer in the time specified,
it will get killed and a 'loss' will be loged.

Since FTPtransfer is an invasive probe you should make sure you do not load
the link for more than a few seconds anyway. Smokeping curently has a hard
limit of 180 seconds for any RTT.
DOC

	return $class->_makevars($h, {
		_mandatory => [ 'srcfile','mode','timeout' ],
		srcfile => {
			_doc => <<DOC,
The name of the source file. If the probe is in B<put> mode, this file
has to be on the local machine, if the probe is in B<get> mode then this
file should sit in the remote ftp account.
DOC
			_example => 'src/path/mybig.pdf',
		},
		destfile => {
			_doc => <<DOC,
Normally the destination filename is the same as the source filename
(without the path). If you want keep files in different directories this may not
work, and you have to specify destfile as well.
DOC
			_example => 'path/to/destinationfile.xxx',
		},
		mode => {
			_doc => <<DOC,
The ftp probe can be in either put or get mode. If it is in put mode then it will send a file to the ftp server. In get mode it will retrieve a file
from the ftp server.
DOC
			_example => 'get',
			_re => '(put|get)',
		},
		
		min_interval => {
                        _default => $DEFAULTINTERVAL,
                        _doc => "The minimum interval between each starting ftp sessions in seconds.",
                        _re => '(\d*\.)?\d+',
		},
	});
}
		
sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		username => {
			_doc => 'The username to be tested.',
			_example => 'test-user',
		},
		password => {
			_doc => 'The password for the user, if not present in the password file.',
			_example => 'test-password',
		},
		timeout => {
			_doc => "Timeout in seconds for the FTP transfer to complete.",
			_re => '\d+',
			_example => 10,
		},
		port => {
			_doc => 'A non-standard FTP port to be used',
			_re => '\d+',
			_example => '3255',
		},
		localaddr => {
			_doc => 'The local address to be used when making connections',
			_example => 'myhost-nat-if',
		},
		passive => {
			_doc => 'Use passive FTP protocol',
			_re => '(yes|no)',
			_example => 'yes',
		}

		
	});
}

1;
