package Smokeping::probes::SendEmail;

# Copyright (c) 2012 Florian Coulmier <florian@coulmier.fr>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>. 1
#

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::skel>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::skel>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork); 
use Carp;
use Sys::Hostname;
use Time::HiRes;
use Net::SMTP;

sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::SendEmail - a Smokeping probe that measure time neeed to send an mail
DOC
		description => <<DOC,
This probe actually send a mail to a MX server and measure time it took. You can choose the sender and recipient adress as well as the size of the mail.
DOC
		authors => <<'DOC',
 Florian Coulmier <florian@coulmier.fr>,
DOC
		see_also => <<DOC
L<smokeping_extend>
DOC
	};
}

sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    # no need for this if we run as a cgi
    unless ( $ENV{SERVER_SOFTWARE} ) {
    	# if you have to test the program output
	# or something like that, do it here
	# and bail out if necessary
    };

    return $self;
}

# Probe-specific variables declaration
sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		_mandatory => [ 'from', 'to' ],
		from => {
			_doc => "Mail from address",
			_example => 'test@test.com',
		},
		to => {
			_doc => "Rcpt to address",
			_exemple => 'test@test.com',
		},
		subject => {
			_doc => "Subject of the mail",
			_exemple => "Test Smokeping",
			_default => "Test",
		},
		bodysize => {
			_doc => "Size of the mail to send in bytes. If set to 0, a default mail content will be set. Note that mail always contain From, To and Subject headers.",
			_exemple => "1024",
			_default => "0",
		}
	});
}

# Target-specific variables declaration
sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		port => { _doc => "Port of the SMTP server to reach",
				_exemple => 25,
				_default => 25,
		},
	});
}

sub ProbeDesc($){
    my $self = shift;
    return "Measure time to send a complete email";
}

# this is where the actual stuff happens
sub pingone ($){
	my $self = shift;
	my $target = shift;

	my @times;

	# Retrieve probe-specific and target-specific variables
	my $count = $self->pings($target);
	my $from = $self->{properties}{from};
	my $to = $self->{properties}{to};
	my $subject = $self->{properties}{subject} || "Smokeping Test";
	my $bodysize = $self->{properties}{bodysize} || 0;

	my $host = $target->{addr};
	my $port = $target->{vars}{port} || 25;

	# Get Hostname
	my $hostname = hostname();

	
	# Send a mail as many times as requested
	for (1..$count) {
		# Start counting time
		my $start = Time::HiRes::gettimeofday();

		# Open the connection and then send the mail
		my $smtp = new Net::SMTP("$host:$port", Timeout => 5, Hello => $hostname);
		next if (!$smtp);

		$smtp->mail($from) || next;
		$smtp->to($to, { Notify => ['NEVER'] }) || next;
		$smtp->data() || next;
		$smtp->datasend("From: <$from>\n");
		$smtp->datasend("To: <$to>\n");
		$smtp->datasend("Subject: $subject\n");
		$smtp->datasend("\n");

		# If user specified a bodysize for the probe, send the request number of characters instead of the default content.
		if ($bodysize > 0) {
			my $nbLines = $bodysize / 80;	
			for (1..$nbLines) {
				$smtp->datasend(sprintf("%s\n", "A" x 79));
			}
			$smtp->datasend(sprintf("%s\n", "A" x ($bodysize % 80)));
		} else {
			$smtp->datasend("This is a test email sent by Smokeping to check speed of mx server $host.\n");
			$smtp->datasend("If you receive this mail in your mailbox, you are likely to be spammed in just few minutes!\n");
		}

		$smtp->dataend() || next;
		$smtp->quit();

		# End measure of time and save it
		my $end = Time::HiRes::gettimeofday();
		push(@times, $end - $start);
	}

	return sort {$a <=> $b } @times;
}

# That's all, folks!

1;
