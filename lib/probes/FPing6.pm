package probes::FPing6;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man probes::FPing6>

to view the documentation or the command

C<smokeping -makepod probes::FPing6>

to generate the POD document.

=cut

use strict;
use base qw(probes::FPing);

sub pod_hash {
      return {
              name => <<DOC,
probes::FPing6 - FPing6 Probe for SmokePing
DOC
              description => <<DOC,
Integrates FPing6 as a probe into smokeping. This probe is derived from
FPing; the only difference is that the target host used for checking
the fping command output is ::1 instead of localhost.
DOC
              authors => <<'DOC',
Tobias Oetiker <tobi@oetiker.ch>

Niko Tyni <ntyni@iki.fi>
DOC
             see_also => <<DOC
probes::FPing
DOC
      }
}

sub testhost {
      return "::1";
}

sub probevars {
      my $self = shift;
      my $h = $self->SUPER::probevars;
      $h->{binary}{_example} = "/usr/bin/fping6";
      return $h;
}
  
1;
