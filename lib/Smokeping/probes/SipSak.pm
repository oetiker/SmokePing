package Smokeping::probes::SipSak;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command

C<smokeping -man Smokeping::probes::SipSak>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::SipSak>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork);
use Carp;
use IO::Select;

sub pod_hash {
    return {
        name => <<DOC,
Smokeping::probes::SipSak - tests sip server
DOC
        overview => <<DOC,
This probe sends OPTIONS messages to a sip server testing the latency.
DOC
        description => <<DOC,
The probe uses the L<sipsak|http://sipsak.org/> tool to measure sip server latency by sending an OPTIONS message.

The sipsak command supports a large number of additional parameters to fine-tune its operation. Use the
params variable to configure them.
DOC
        authors => <<'DOC',
Tobias Oetiker <tobi@oetiker.ch> sponsored by ANI Networks
DOC
    }
}

sub ProbeDesc ($) {
        my $self = shift;
    return sprintf("SIP OPTIONS messages");
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
    my @times;
    my $elapsed;
    my $pingcount = $self->pings($target);
    my $keep = $vars->{keep_second};
    $host = $vars->{user}.'@'.$host if $vars->{user};
    $host = $host . ':' . $vars->{port} if $vars->{port};
    my @extra_opts = ();
    @extra_opts = split /\s/, $vars->{params} if $vars->{params};
    open (my $sak,'-|',$self->{properties}{binary},'-vv','-A',$pingcount,'-s','sip:'.$host,@extra_opts)
        or die("ERROR: $self->{properties}{binary}: $!\n");
    my $sel = IO::Select->new();
    $sel->add($sak);
    if (not $sel->can_read($vars->{sipsak_timeout})){
        $self->do_debug("SipSak: timeout for $host");
        return '';
    }

    my $reply = join ("",<$sak>);
    close $sak;

    my @reply = split /\*\*\sreply/, $reply;
    # don't need the stuff before the first replyx
    shift @reply;

    my $filter = '.*';
    $self->do_debug("SipSak: got ".(scalar @reply)." replies, expected $pingcount");
    if (scalar @reply > $pingcount){
        $filter = $keep eq 'yes' ? 'final received' : 'provisional received';
    }
    for my $item (@reply){
        $self->do_debug("SipSak: looking at '$item'");
        if (not $item =~ /$filter/){
            $self->do_debug("SipSak: skipping as there was not match for $filter");
            next;
        }
        if ($item =~ /(?:\sand|\sreceived\safter)\s(\d+(?:\.\d+)?)\sms\s/){
            $self->do_debug("SipSak: match");
            push @times,$1/1000;
        }
        else {
            $self->do_debug("SipSak: no match");
        }
    }
    return sort { $a <=> $b } @times;
}

sub probevars {
    my $class = shift;
    my $h = $class->SUPER::probevars;
    return $class->_makevars($h, {
        binary => {
            _doc => "The location of your echoping binary.",
            _default => '/usr/bin/sipsak',
            _sub => sub {
                my $val = shift;
                -x $val or return "ERROR: binary '$val' is not executable";
                return undef;
            },
        },
    });
}

sub targetvars {
    my $class = shift;
    return $class->_makevars($class->SUPER::targetvars, {
        user => {
            _doc => "User to use for sip connection.",
            _example => 'nobody',
        },
        port => {
            _doc => "usa non-default port for the sip connection.",
            _example => 5061,
        },
        params => {
            _doc => "additional sipsak options. The options will get split on space.",
            _example => '--numeric --password=mysecret'
        },
        keep_second => {
            _doc => "If OPTIONS is actually implemented by the server, SipSak will receive two responses. If this option is set, the timeing from the second, final response will be counter",
            _example => 'yes',
            _re => 'yes|no'
        },
        sipsak_timeout => {
            _doc => "Timeout for sipsak in seconds (fractional)",
            _default => 2,
        },
    });
}

1;
