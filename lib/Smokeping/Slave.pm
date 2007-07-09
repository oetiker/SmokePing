# -*- perl -*-
package Smokeping::Slave;
use HTTP::Daemon;
use HTTP::Status;

=head1 NAME

Smokeping::Slave - Slave Functionality for Smokeping

=head1 OVERVIEW

This module handles all special functionality required by smokeping running
in slave mode.

=head2 IMPLEMENTATION

=head3 slave_cfg=extract_config(cfg,slave)

Extract the relevant configuration information for the selected slave. The
configuration will only contain the information that is relevant for the
slave. Any parameters overwritten in the B<Slaves> section of the configuration
file will be patched for the slave.

=cut

sub extract_config($$){
    my $cfg = shift;
    my $slave = shift;
}

=head3 expect_request(cfg)

=cut

sub expect_request($){
    my $cfg = shift;
    my $daemon = HTTP::Daemon->new or die "Creating HTTP daemon";
    print "Please contact me at: <URL:", $d->url, ">\n";
    while (my $c = $d->accept) {
         while (my $r = $c->get_request) {
                 if ($r->method eq 'GET' and $r->url->path eq "/xyzzy") {
                     # remember, this is *not* recommended practice :-)
                     $c->send_file_response("/etc/passwd");
                 }
                 else {
                     $c->send_error(RC_FORBIDDEN)
                 }
             }
             $c->close;
             undef($c);
         }
    
}

1;

__END__

=head1 COPYRIGHT

Copyright 2007 by Tobias Oetiker

=head1 LICENSE

This program is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.  See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public
License along with this program; if not, write to the Free
Software Foundation, Inc., 675 Mass Ave, Cambridge, MA
02139, USA.

=head1 AUTHOR

Tobias Oetiker E<lt>tobi@oetiker.chE<gt>

=cut
