package JSON::PP5005;

use 5.005;
use strict;

my @properties;

$JSON::PP5005::VERSION = '0.05';

BEGIN {
    *JSON::PP::JSON_encode_ascii   = *_encode_ascii;
    *JSON::PP::JSON_encode_latin1  = *_encode_latin1;
    *JSON::PP::JSON_decode_unicode = *_disable_decode_unicode;

    sub utf8::is_utf8 {
        1; # It is considered that UTF8 flag on for Perl 5.005.
    }

    sub utf8::encode (\$) {
    }

    sub utf8::decode (\$) {
    }

    sub JSON::PP::ascii {
        warn "ascii() is disable in Perl5.005.";
        $_[0]->{ascii} = 0; $_[0];
    }

    sub JSON::PP::latin1 {
        warn "latin1() is disable in Perl5.005.";
        $_[0]->{latin1} = 0; $_[0];
    }

    # missing in B module.
    sub B::SVf_IOK () { 0x00010000; }
    sub B::SVf_NOK () { 0x00020000; }

}


sub _encode_ascii {
    # currently noop
}


sub _encode_latin1 {
    # currently noop
}


sub _disable_decode_unicode { chr(hex($_[0])); }



1;
__END__

=pod

=head1 NAME

JSON::PP5005 - Helper module in using JSON::PP in Perl 5.005

=head1 DESCRIPTION

JSON::PP calls internally.

=head1 AUTHOR

Makamaka Hannyaharamitu, E<lt>makamaka[at]cpan.orgE<gt>


=head1 COPYRIGHT AND LICENSE

Copyright 2007 by Makamaka Hannyaharamitu

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

