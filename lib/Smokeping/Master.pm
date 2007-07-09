# -*- perl -*-
package Smokeping::Master;
use HTTP::Request;


=head1 NAME

Smokeping::Master - Master Functionality for Smokeping

=head1 OVERVIEW

This module handles all special functionality required by smokeping running
in master mode.

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

=head3 poll_slave(cfg,slave)

Get latest measurement results from the slave

=cut

sub poll_slave($$){
    my $cfg = shift;
    my $slave = shift;
}


=head3 push_config(cfg,slave)

Upload new config information to the slave if the poll result shows that it needs an update.

=cut

sub push_config ($$){
    my $cfg = shift;
    my $slave = shift;
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
