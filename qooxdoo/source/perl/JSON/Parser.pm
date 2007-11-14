package JSON::Parser;

#
# Perl implementaion of json.js
#  http://www.crockford.com/JSON/json.js
#

use vars qw($VERSION $USE_UTF8 $USE_UnicodeString);
use strict;
use JSON ();
use Carp ();

BEGIN { # suggested by philip.tellis[at]gmail.com
    if ($] < 5.008) {
        eval q{ require Unicode::String };
        unless ($@) {
            $USE_UnicodeString = 1;
            eval q|
                sub utf8::encode (\$) {
                    my $f_ref = $_[0];
                    if (length($$f_ref) == 1 && ord($$f_ref) <= 0xff) {
                        my $us = new Unicode::String;
                        $us->latin1($$f_ref);
                        $$f_ref = $us->utf8;
                    }
                }
            |;
        }
    }
}


$VERSION  = '1.07';

# TODO: I made 1.03, but that will be used after JSON 1.90

$USE_UTF8 = JSON->USE_UTF8();

my %escapes = ( #  by Jeremy Muhlich <jmuhlich [at] bitflood.org>
  b    => "\x8",
  t    => "\x9",
  n    => "\xA",
  f    => "\xC",
  r    => "\xD",
#  '/'  => '/',
  '\\' => '\\',
);


sub new {
    my $class = shift;
    bless { @_ }, $class;
}


*jsonToObj = \&parse;


{ # PARSE 

    my $text;
    my $at;
    my $ch;
    my $len;
    my $unmap; # unmmaping
    my $bare;  # bareKey
    my $apos;  # loosely quoting
    my $utf8;  # set utf8 flag


    sub parse {
        my $self = shift;
        $text = shift;
        $at   = 0;
        $ch   = '';
        $len  = length $text;
        $self->_init(@_);
        value();
    }


    sub next_chr {
        return $ch = undef if($at >= $len);
        $ch = substr($text, $at++, 1);
    }


    sub value {
        white();
        return          if(!defined $ch);
        return object() if($ch eq '{');
        return array()  if($ch eq '[');
        return string() if($ch eq '"' or ($apos and $ch eq "'"));
        return number() if($ch eq '-');
        return $ch =~ /\d/ ? number() : word();
    }


    sub string {
        my ($i,$s,$t,$u);
        $s = '';

        if($ch eq '"' or ($apos and $ch eq "'")){
            my $boundChar = $ch if ($apos);

            OUTER: while( defined(next_chr()) ){
                if((!$apos and $ch eq '"') or ($apos and $ch eq $boundChar)){
                    next_chr();
                    $utf8 and utf8::decode($s);
                    return $s;
                }
                elsif($ch eq '\\'){
                    next_chr();
                    if(exists $escapes{$ch}){
                        $s .= $escapes{$ch};
                    }
                    elsif($ch eq 'u'){
                        my $u = '';
                        for(1..4){
                            $ch = next_chr();
                            last OUTER if($ch !~ /[\da-fA-F]/);
                            $u .= $ch;
                        }
                         my $f = chr(hex($u));
                         utf8::encode( $f ) if($USE_UTF8 || $USE_UnicodeString);
                         $s .= $f;
                    }
                    else{
                        $s .= $ch;
                    }
                }
                else{
                    $s .= $ch;
                }
            }
        }

        error("Bad string");
    }


    sub white {
        while( defined $ch  ){
            if($ch le ' '){
                next_chr();
            }
            elsif($ch eq '/'){
                next_chr();
                if($ch eq '/'){
                    1 while(defined(next_chr()) and $ch ne "\n" and $ch ne "\r");
                }
                elsif($ch eq '*'){
                    next_chr();
                    while(1){
                        if(defined $ch){
                            if($ch eq '*'){
                                if(defined(next_chr()) and $ch eq '/'){
                                    next_chr();
                                    last;
                                }
                            }
                            else{
                                next_chr();
                            }
                        }
                        else{
                            error("Unterminated comment");
                        }
                    }
                    next;
                }
                else{
                    error("Syntax error (whitespace)");
                }
            }
            else{
                last;
            }
        }
    }


    sub object {
        my $o = {};
        my $k;

        if($ch eq '{'){
            next_chr();
            white();
            if($ch eq '}'){
                next_chr();
                return $o;
            }
            while(defined $ch){
                $k = ($bare and $ch ne '"' and $ch ne "'") ? bareKey() : string();
                white();

                if($ch ne ':'){
                    last;
                }

                next_chr();
                $o->{$k} = value();
                white();

                if($ch eq '}'){
                    next_chr();
                    return $o;
                }
                elsif($ch ne ','){
                    last;
                }
                next_chr();
                white();
            }

            error("Bad object");
        }
    }


    sub bareKey { # doesn't strictly follow Standard ECMA-262 3rd Edition
        my $key;
        while($ch =~ /[^\x00-\x23\x25-\x2F\x3A-\x40\x5B-\x5E\x60\x7B-\x7F]/){
            $key .= $ch;
            next_chr();
        }
        return $key;
    }


    sub word {
        my $word =  substr($text,$at-1,4);

        if($word eq 'true'){
            $at += 3;
            next_chr;
            return $unmap ? 1 : bless {value => 'true'}, 'JSON::NotString'
        }
        elsif($word eq 'null'){
            $at += 3;
            next_chr;
            return $unmap ? undef : bless {value => undef}, 'JSON::NotString';
        }
        elsif($word eq 'fals'){
            $at += 3;
            if(substr($text,$at,1) eq 'e'){
                $at++;
                next_chr;
                return $unmap ? 0 : bless {value => 'false'}, 'JSON::NotString'
            }
        }

        error("Syntax error (word)");
    }


    sub number {
        my $n    = '';
        my $v;

        if($ch eq '0'){
            my $peek = substr($text,$at,1);
            my $hex  = $peek =~ /[xX]/;

            if($hex){
                ($n) = ( substr($text, $at+1) =~ /^([0-9a-fA-F]+)/);
            }
            else{
                ($n) = ( substr($text, $at) =~ /^([0-7]+)/);
            }

            if(defined $n and length($n)){
                $at += length($n) + $hex;
                next_chr;
                return $hex ? hex($n) : oct($n);
            }
        }

        if($ch eq '-'){
            $n = '-';
            next_chr;
        }

        while($ch =~ /\d/){
            $n .= $ch;
            next_chr;
        }

        if($ch eq '.'){
            $n .= '.';
            while(defined(next_chr) and $ch =~ /\d/){
                $n .= $ch;
            }
        }

        if($ch eq 'e' or $ch eq 'E'){
            $n .= $ch;
            next_chr;

            if(defined($ch) and ($ch eq '+' or $ch eq '-' or $ch =~ /\d/)){
                $n .= $ch;
            }

            while(defined(next_chr) and $ch =~ /\d/){
                $n .= $ch;
            }

        }

        $v .= $n;

        return 0+$v;
    }


    sub array {
        my $a  = [];

        if($ch eq '['){
            next_chr();
            white();
            if($ch eq ']'){
                next_chr();
                return $a;
            }
            while(defined($ch)){
                push @$a, value();
                white();
                if($ch eq ']'){
                    next_chr();
                    return $a;
                }
                elsif($ch ne ','){
                    last;
                }
                next_chr();
                white();
            }
        }

        error("Bad array");
    }


    sub error {
        my $error  = shift;

        local $Carp::CarpLevel = 1;

        my $str = substr($text, $at);

        unless (length $str) { $str = '(end of string)'; }

        Carp::croak "$error, at character offset $at ($str)";
    }


    sub _init {
        my $opt  = $_[1] || {};
        $unmap= $_[0]->{unmapping};
        $unmap= $opt->{unmapping} if(exists $opt->{unmapping});
        $bare = $_[0]->{barekey};
        $bare = $opt->{barekey} if(exists $opt->{barekey});
        $apos = $_[0]->{quotapos};
        $apos = $opt->{quotapos} if(exists $opt->{quotapos});
        $utf8 = $_[0]->{utf8};
        $utf8 = $opt->{utf8} if(exists $opt->{utf8});
        if($utf8 and !$USE_UTF8){ $utf8 = 0; warn "JSON::Parser couldn't use utf8."; }
    }

} # PARSE




package JSON::NotString;

use overload (
    '""'   => sub { $_[0]->{value} },
    'bool' => sub {
          ! defined $_[0]->{value}  ? undef
        : $_[0]->{value} eq 'false' ? 0 : 1;
    },
    'eq'   => sub { (defined $_[0]->{value} ? $_[0]->{value} : 'null') eq $_[1] },
    'ne'   => sub { (defined $_[0]->{value} ? $_[0]->{value} : 'null') ne $_[1] },
    '=='   => sub { (!defined $_[0]->{value} ? -1 : $_[0]->{value} eq 'false' ? 0 : 1) == $_[1] },
    '!='   => sub { (!defined $_[0]->{value} ? -1 : $_[0]->{value} eq 'false' ? 0 : 1) != $_[1] },
);

1;

__END__

    'eq'   => sub {
        if (ref($_[1]) eq 'JSON::NotString') {
            return $_[0]->{value} eq $_[1]->{value};
        }
        else {
            return $_[0]->{value} eq $_[1];
        }
    },


=head1 SEE ALSO

L<http://www.crockford.com/JSON/index.html>

This module is an implementation of L<http://www.crockford.com/JSON/json.js>.


=head1 COPYRIGHT

makamaka [at] donzoko.net

This library is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=cut
