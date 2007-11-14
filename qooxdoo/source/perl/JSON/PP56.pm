package JSON::PP56;

use 5.006;
use strict;

my @properties;

$JSON::PP56::VERSION = '0.13';

BEGIN {
    sub utf8::is_utf8 {
        1; # It is considered that UTF8 flag on for Perl 5.6.
    }

    sub utf8::encode (\$) { # UTF8 flag off
        ${$_[0]} = pack("C*", unpack("C*", ${$_[0]}));
    }

    sub utf8::decode (\$) { # UTF8 flag on
        ${$_[0]} = pack("U*", unpack_emu(${$_[0]}));
    }
}

eval q| require Unicode::String |;

unless ($@) {
    #print Unicode::String->VERSION;
    if (Unicode::String->VERSION < 2.08) { # utf16be() exists more than v2.08
        eval q| *Unicode::String::utf16be = *Unicode::String::utf16 |;
    }

    *JSON::PP::JSON_encode_ascii   = *_encode_ascii;
    *JSON::PP::JSON_encode_latin1  = *_encode_latin1;
    *JSON::PP::JSON_decode_unicode = *JSON::PP::_decode_unicode;

    eval q|
        sub Encode::encode {
            my (undef, $str) = @_;
            my $u = new Unicode::String;
            $u->utf8($str);
            $u->utf16be;
        }

        sub Encode::decode {
            my (undef, $str) = @_;
            my $u = new Unicode::String;
            $u->utf16be($str);
            my $utf8 = $u->utf8;
            pack("U", unpack("U", $utf8)); # UTF8 flag on
        }

    |;
    die $@ if ($@);

    $JSON::PP::_ENABLE_UTF16 = 1;

    push @JSON::PP::_properties, 'ascii', 'latin1';
}
else {
    *JSON::PP::JSON_encode_ascii   = *_noop_encode_ascii;
    *JSON::PP::JSON_decode_unicode = *_disable_decode_unicode;

    eval q| 
        sub JSON::PP::ascii {
            warn "ascii() is disable in Perl5.6x.";
            $_[0]->{ascii} = 0; $_[0];
        }

        sub JSON::PP::latin1 {
            warn "latin1() is disable in Perl5.6x.";
            $_[0]->{latin1} = 0; $_[0];
        }
    |;
}


sub _encode_ascii {
    join('',
        map {
            $_ <= 127 ?
                chr($_) :
            $_ <= 65535 ?
                sprintf('\u%04x', $_) :
                join("", map { '\u' . $_ }
                        unpack("H4H4", Encode::encode('UTF-16BE', pack("U", $_))));
        } unpack_emu($_[0])
    );
}


sub _encode_latin1 {
    join('',
        map {
            $_ <= 255 ?
                chr($_) :
            $_ <= 65535 ?
                sprintf('\u%04x', $_) :
                join("", map { '\u' . $_ }
                        unpack("H4H4", Encode::encode('UTF-16BE', pack("U", $_))));
        } unpack_emu($_[0])
    );
}


sub unpack_emu { # for Perl 5.6 unpack warnings
    my $str = $_[0];
    my @ret;
    my $is_utf8;

    while ($str =~ /(?:
          (
             [\x00-\x7F]
            |[\xC2-\xDF][\x80-\xBF]
            |[\xE0][\xA0-\xBF][\x80-\xBF]
            |[\xE1-\xEC][\x80-\xBF][\x80-\xBF]
            |[\xED][\x80-\x9F][\x80-\xBF]
            |[\xEE-\xEF][\x80-\xBF][\x80-\xBF]
            |[\xF0][\x90-\xBF][\x80-\xBF][\x80-\xBF]
            |[\xF1-\xF3][\x80-\xBF][\x80-\xBF][\x80-\xBF]
            |[\xF4][\x80-\x8F][\x80-\xBF][\x80-\xBF]
          )
        | (.)
    )/xg)
    {
        if (defined $1) {
            $is_utf8 = 1 if (!defined $is_utf8);
            if ($is_utf8) {
                push @ret, unpack('U', $1);
            }
            else {
                push @ret, unpack('C*', $1);
            }
        }
        else {
            $is_utf8 = 0 if (!defined $is_utf8);

            if ($is_utf8) { # eventually, not utf8
                return unpack('C*', $str);
            }

            push @ret, unpack('C', $2);
        }
    }

    return @ret;
}



sub _noop_encode_ascii {
    # noop
}


sub _disable_decode_unicode { chr(hex($_[0])); }


1;
__END__

=pod

=head1 NAME

JSON::PP56 - Helper module in using JSON::PP in Perl 5.6

=head1 DESCRIPTION

JSON::PP calls internally.

=head1 AUTHOR

Makamaka Hannyaharamitu, E<lt>makamaka[at]cpan.orgE<gt>


=head1 COPYRIGHT AND LICENSE

Copyright 2007 by Makamaka Hannyaharamitu

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

