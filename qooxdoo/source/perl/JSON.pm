package JSON;

use strict;
use base qw(Exporter);

@JSON::EXPORT = qw(objToJson jsonToObj);

use vars qw($AUTOCONVERT $VERSION $UnMapping $BareKey $QuotApos
            $ExecCoderef $SkipInvalid $Pretty $Indent $Delimiter
            $KeySort $ConvBlessed $SelfConvert $UTF8 $SingleQuote);

$VERSION = '1.14';

$AUTOCONVERT = 1;
$SkipInvalid = 0;
$ExecCoderef = 0;
$Pretty      = 0; # pretty-print mode switch
$Indent      = 2; # (for pretty-print)
$Delimiter   = 2; # (for pretty-print)  0 => ':', 1 => ': ', 2 => ' : '
$UnMapping   = 0; # 
$BareKey     = 0; # 
$QuotApos    = 0; # 
$KeySort     = undef; # Code-ref to provide sort ordering in converter
$UTF8        = 0;
$SingleQuote = 0;

my $USE_UTF8;

BEGIN {
    $USE_UTF8 = $] >= 5.008 ? 1 : 0;
    sub USE_UTF8 {  $USE_UTF8; }
}

use JSON::Parser;
use JSON::Converter;

my $parser; # JSON => Perl
my $conv;   # Perl => JSON


##############################################################################
# CONSTRCUTOR - JSON objects delegate all processes
#                   to JSON::Converter and JSON::Parser.
##############################################################################

sub new {
    my $class = shift;
    my %opt   = @_;
    bless {
        conv   => undef,  # JSON::Converter [perl => json]
        parser => undef,  # JSON::Parser    [json => perl]
        # below fields are for JSON::Converter
        autoconv    => $AUTOCONVERT,
        skipinvalid => $SkipInvalid,
        execcoderef => $ExecCoderef,
        pretty      => $Pretty     ,
        indent      => $Indent     ,
        delimiter   => $Delimiter  ,
        keysort     => $KeySort    ,
        convblessed => $ConvBlessed,
        selfconvert => $SelfConvert,
        singlequote => $SingleQuote,
        # below fields are for JSON::Parser
        unmapping   => $UnMapping,
        quotapos    => $QuotApos ,
        barekey     => $BareKey  ,
        # common options
        utf8        => $UTF8     ,
        # overwrite
        %opt,
    }, $class;
}


##############################################################################
# METHODS
##############################################################################

*parse_json = \&jsonToObj;

*to_json    = \&objToJson;

sub jsonToObj {
    my $self = shift;
    my $js   = shift;

    if(!ref($self)){ # class method
        my $opt = __PACKAGE__->_getParamsForParser($js);
        $js = $self;
        $parser ||= new JSON::Parser;
        $parser->jsonToObj($js, $opt);
    }
    else{ # instance method
        my $opt = $self->_getParamsForParser($_[0]);
        $self->{parser} ||= ($parser ||= JSON::Parser->new);
        $self->{parser}->jsonToObj($js, $opt);
    }
}


sub objToJson {
    my $self = shift || return;
    my $obj  = shift;

    if(ref($self) !~ /JSON/){ # class method
        my $opt = __PACKAGE__->_getParamsForConverter($obj);
        $obj  = $self;
        $conv ||= JSON::Converter->new();
        $conv->objToJson($obj, $opt);
    }
    else{ # instance method
        my $opt = $self->_getParamsForConverter($_[0]);
        $self->{conv}
         ||= JSON::Converter->new( %$opt );
        $self->{conv}->objToJson($obj, $opt);
    }
}


#######################


sub _getParamsForParser {
    my ($self, $opt) = @_;
    my $params;

    if(ref($self)){ # instance
        my @names = qw(unmapping quotapos barekey utf8);
        my ($unmapping, $quotapos, $barekey, $utf8) = @{$self}{ @names };
        $params = {
            unmapping => $unmapping, quotapos => $quotapos,
            barekey   => $barekey,   utf8     => $utf8,
        };
    }
    else{ # class
        $params = {
            unmapping => $UnMapping, barekey => $BareKey,
            quotapos  => $QuotApos,  utf8    => $UTF8,
        };
    }

    if($opt and ref($opt) eq 'HASH'){
        for my $key ( keys %$opt ){
            $params->{$key} = $opt->{$key};
        }
    }

    return $params;
}


sub _getParamsForConverter {
    my ($self, $opt) = @_;
    my $params;

    if(ref($self)){ # instance
        my @names
         = qw(pretty indent delimiter autoconv keysort convblessed selfconvert utf8 singlequote);
        my ($pretty, $indent, $delimiter, $autoconv,
                $keysort, $convblessed, $selfconvert, $utf8, $singlequote)
                                                           = @{$self}{ @names };
        $params = {
            pretty      => $pretty,       indent      => $indent,
            delimiter   => $delimiter,    autoconv    => $autoconv,
            keysort     => $keysort,      convblessed => $convblessed,
            selfconvert => $selfconvert,  utf8        => $utf8,
            singlequote => $singlequote,
        };
    }
    else{ # class
        $params = {
            pretty      => $Pretty,       indent      => $Indent,
            delimiter   => $Delimiter,    autoconv    => $AUTOCONVERT,
            keysort     => $KeySort,      convblessed => $ConvBlessed,
            selfconvert => $SelfConvert,  utf8        => $UTF8,
            singlequote => $SingleQuote, 
        };
    }

    if($opt and ref($opt) eq 'HASH'){
        for my $key ( keys %$opt ){
            $params->{$key} = $opt->{$key};
        }
    }

    return $params;
}

##############################################################################
# ACCESSOR
##############################################################################
BEGIN{
    for my $name (qw/autoconv pretty indent delimiter 
                  unmapping keysort convblessed selfconvert singlequote/)
    {
        eval qq{
            sub $name { \$_[0]->{$name} = \$_[1] if(defined \$_[1]); \$_[0]->{$name} }
        };
    }
}

##############################################################################
# NON STRING DATA
##############################################################################

# See JSON::Parser for JSON::NotString.

sub Number {
    my $num = shift;

    return undef if(!defined $num);

    if(    $num =~ /^-?(?:\d+)(?:\.\d*)?(?:[eE][-+]?\d+)?$/
        or $num =~ /^0[xX](?:[0-9a-zA-Z])+$/                 )
    {
        return bless {value => $num}, 'JSON::NotString';
    }
    else{
        return undef;
    }
}

sub True {
    bless {value => 'true'}, 'JSON::NotString';
}

sub False {
    bless {value => 'false'}, 'JSON::NotString';
}

sub Null {
    bless {value => undef}, 'JSON::NotString';
}

##############################################################################
1;
__END__

=pod

=head1 NAME

JSON - parse and convert to JSON (JavaScript Object Notation).

=head1 SYNOPSIS

 use JSON;
 
 $obj = {
    id   => ["foo", "bar", { aa => 'bb'}],
    hoge => 'boge'
 };
 
 $js  = objToJson($obj);
 # this is {"id":["foo","bar",{"aa":"bb"}],"hoge":"boge"}.
 $obj = jsonToObj($js);
 # the data structure was restored.
 
 # OOP
 
 my $json = new JSON;
 
 $obj = {id => 'foo', method => 'echo', params => ['a','b']};
 $js  = $json->objToJson($obj);
 $obj = $json->jsonToObj($js);
 
 # pretty-printing
 $js = $json->objToJson($obj, {pretty => 1, indent => 2});

 $json = JSON->new(pretty => 1, delimiter => 0);
 $json->objToJson($obj);


=head1 TRANSITION PLAN

In the next large update version, JSON and JSONRPC modules are split.

  JSON::Parser and JSON::Converter are deleted from JSON dist.
  JSON and JSON::PP in JSON dist.

  JSON becomes wrapper to JSON::XS and/or JSON::PP.

  JSONRPC* and Apache::JSONRPC are deleted from JSON dist.
  JSONRPC::Client, JSONRPC::Server and JSONRPC::Procedure in JSON::RPC dist.

  Modules in JSON::RPC dist supports JSONRPC protocol v1.1 and 1.0.


=head1 DESCRIPTION

This module converts between JSON (JavaScript Object Notation) and Perl
data structure into each other.
For JSON, See to http://www.crockford.com/JSON/.


=head1 METHODS

=over 4

=item new()

=item new( %options )

returns a JSON object. The object delegates the converting and parsing process
to L<JSON::Converter> and L<JSON::Parser>.

 my $json = new JSON;

C<new> can take some options.

 my $json = new JSON (autoconv => 0, pretty => 1);

Following options are supported:

=over 4

=item autoconv

See L</AUTOCONVERT> for more info.

=item skipinvalid

C<objToJson()> does C<die()> when it encounters any invalid data
(for instance, coderefs). If C<skipinvalid> is set with true,
the function convets these invalid data into JSON format's C<null>.

=item execcoderef

C<objToJson()> does C<die()> when it encounters any code reference.
However, if C<execcoderef> is set with true, executes the coderef
and uses returned value.

=item pretty

See L</PRETTY PRINTING> for more info.

=item indent

See L</PRETTY PRINTING> for more info.

=item delimiter

See L</PRETTY PRINTING> for more info.

=item keysort

See L</HASH KEY SORT ORDER> for more info.

=item convblessed

See L</BLESSED OBJECT> for more info.

=item selfconvert

See L</BLESSED OBJECT> for more info.

=item singlequote

See L</CONVERT WITH SINGLE QUOTES> for more info.

=back 


=item objToJson( $object )

=item objToJson( $object, $hashref )

takes perl data structure (basically, they are scalars, arrayrefs and hashrefs)
and returns JSON formated string.

 my $obj = [1, 2, {foo => bar}];
 my $js  = $json->objToJson($obj);
 # [1,2,{"foo":"bar"}]

By default, returned string is one-line. However, you can get pretty-printed
data with C<pretty> option. Please see below L</PRETTY PRINTING>.

 my $js  = $json->objToJson($obj, {pretty => 1, indent => 2});
 # [
 #   1,
 #   2,
 #   {
 #     "foo" : "bar"
 #   }
 # ]

=item jsonToObj( $js )

takes a JSON formated data and returns a perl data structure.


=item autoconv()

=item autoconv($bool)

This is an accessor to C<autoconv>. See L</AUTOCONVERT> for more info.

=item pretty()

=item pretty($bool)

This is an accessor to C<pretty>. It takes true or false.
When prrety is true, C<objToJson()> returns prrety-printed string.
See L</PRETTY PRINTING> for more info.

=item indent()

=item indent($integer)

This is an accessor to C<indent>.
See L</PRETTY PRINTING> for more info.

=item delimiter()

This is an accessor to C<delimiter>.
See L</PRETTY PRINTING> for more info.

=item unmapping()

=item unmapping($bool)

This is an accessor to C<unmapping>.
See L</UNMAPPING OPTION> for more info.

=item keysort()

=item keysort($coderef)

This is an accessor to C<keysort>.
See L</HASH KEY SORT ORDER> for more info.

=item convblessed()

=item convblessed($bool)

This is an accessor to C<convblessed>.
See L</BLESSED OBJECT> for more info.

=item selfconvert()

=item selfconvert($bool)

This is an accessor to C<selfconvert>.
See L</BLESSED OBJECT> for more info.

=item singlequote()

=item singlequote($bool)

This is an accessor to C<singlequote>.
See L</CONVERT WITH SINGLE QUOTES> for more info.


=back

=head1 MAPPING

 (JSON) {"param" : []}
 ( => Perl) {'param' => []};
 
 (JSON) {"param" : {}}
 ( => Perl) {'param' => {}};
 
 (JSON) {"param" : "string"}
 ( => Perl) {'param' => 'string'};
 
 JSON {"param" : null}
  => Perl {'param' => bless( {'value' => undef}, 'JSON::NotString' )};
  or {'param' => undef}
 
 (JSON) {"param" : true}
 ( => Perl) {'param' => bless( {'value' => 'true'}, 'JSON::NotString' )};
  or {'param' => 1}
 
 (JSON) {"param" : false}
 ( => Perl) {'param' => bless( {'value' => 'false'}, 'JSON::NotString' )};
  or {'param' => 2}
 
 (JSON) {"param" : 0xff}
 ( => Perl) {'param' => 255};

 (JSON) {"param" : 010}
 ( => Perl) {'param' => 8};

These JSON::NotString objects are overloaded so you don't care about.
Since 1.00, L</UnMapping option> is added. When that option is set,
{"param" : null} will be converted into {'param' => undef}, insted of 
{'param' => bless( {'value' => undef}, 'JSON::NotString' )}.


Perl's C<undef> is converted to 'null'.


=head1 PRETTY PRINTING

If you'd like your JSON output to be pretty-printed, pass the C<pretty>
parameter to objToJson(). You can affect the indentation (which defaults to 2)
by passing the C<indent> parameter to objToJson().

  my $str = $json->objToJson($obj, {pretty => 1, indent => 4});

In addition, you can set some number to C<delimiter> option.
The available numbers are only 0, 1 and 2.
In pretty-printing mode, when C<delimiter> is 1, one space is added
after ':' in object keys. If C<delimiter> is 2, it is ' : ' and
0 is ':' (default is 2). If you give 3 or more to it, the value
is taken as 2.


=head1 AUTOCONVERT

By default, $JSON::AUTOCONVERT is true.

 (Perl) {num => 10.02}
 ( => JSON) {"num" : 10.02}

it is not C<{"num" : "10.02"}>.

But set false value with $JSON::AUTOCONVERT:

 (Perl) {num => 10.02}
 ( => JSON) {"num" : "10.02"}

it is not C<{"num" : 10.02}>.

You can explicitly sepcify:

 $obj = {
    id     => JSON::Number(10.02),
    bool1  => JSON::True,
    bool2  => JSON::False,
    noval  => JSON::Null,
 };

 $json->objToJson($obj);
 # {"noval" : null, "bool2" : false, "bool1" : true, "id" : 10.02}

C<JSON::Number()> returns C<undef> when an argument invalid format.

=head1 UNMAPPING OPTION

By default, $JSON::UnMapping is false and JSON::Parser converts
C<null>, C<true>, C<false> into C<JSON::NotString> objects.
You can set true into $JSON::UnMapping to stop the mapping function.
In that case, JSON::Parser will convert C<null>, C<true>, C<false>
into C<undef>, 1, 0.

=head1 BARE KEY OPTION

You can set a true value into $JSON::BareKey for JSON::Parser to parse
bare keys of objects.

 local $JSON::BareKey = 1;
 $obj = jsonToObj('{foo:"bar"}');

=head1 SINGLE QUOTATION OPTION

You can set a true value into $JSON::QuotApos for JSON::Parser to parse
any keys and values quoted by single quotations.

 local $JSON::QuotApos = 1;
 $obj = jsonToObj(q|{"foo":'bar'}|);
 $obj = jsonToObj(q|{'foo':'bar'}|);

With $JSON::BareKey:

 local $JSON::BareKey  = 1;
 local $JSON::QuotApos = 1;
 $obj = jsonToObj(q|{foo:'bar'}|);

=head1 HASH KEY SORT ORDER

By default objToJSON will serialize hashes with their keys in random
order.  To control the ordering of hash keys, you can provide a standard
'sort' function that will be used to control how hashes are converted.

You can provide either a fully qualified function name or a CODEREF to
$JSON::KeySort or $obj->keysort.

If you give any integers (excluded 0), the sort function will work as:

 sub { $a cmp $b }

Note that since the sort function is external to the JSON module the
magical $a and $b arguments will not be in the same package.  In order
to gain access to the sorting arguments, you must either:

  o use the ($$) prototype (slow)
  o Fully qualify $a and $b from the JSON::Converter namespace

See the documentation on sort for more information.

 local $JSON::KeySort = 'My::Package::sort_function';

 or

 local $JSON::KeySort = \&_some_function;

 sub sort_function {
    $JSON::Converter::a cmp $JSON::Converter::b;
 }

 or

 sub sort_function ($$) {
    my ($a, $b) = @_;

    $a cmp $b
 }

=head1 BLESSED OBJECT

By default, JSON::Converter doesn't deal with any blessed object
(returns C<undef> or C<null> in the JSON format).
If you use $JSON::ConvBlessed or C<convblessed> option,
the module can convert most blessed object (hashref or arrayref).

  local $JSON::ConvBlessed = 1;
  print objToJson($blessed);

This option slows down the converting speed.

If you use $JSON::SelfConvert or C<selfconvert> option,
the module will test for a C<toJson()> method on the object,
and will rely on this method to obtain the converted value of
the object.

=head1 UTF8

You can set a true value into $JSON::UTF8 for JSON::Parser
and JSON::Converter to set UTF8 flag into strings contain utf8.


=head1 CONVERT WITH SINGLE QUOTES

You can set a true value into $JSON::SingleQuote for JSON::Converter
to quote any keys and values with single quotations.

You want to parse single quoted JSON data, See L</SINGLE QUOTATION OPTION>.


=head1 EXPORT

C<objToJson>, C<jsonToObj>.

=head1 TODO

Which name is more desirable? JSONRPC or JSON::RPC.

SingleQuote and QuotApos...


=head1 SEE ALSO

L<http://www.crockford.com/JSON/>, L<JSON::Parser>, L<JSON::Converter>

If you want the speed and the saving of memory usage,
check L<JSON::Syck>.

=head1 ACKNOWLEDGEMENTS

I owe most JSONRPC idea to L<XMLRPC::Lite> and L<SOAP::Lite>.

SHIMADA pointed out many problems to me.

Mike Castle E<lt>dalgoda[at]ix.netcom.comE<gt> suggested
better packaging way.

Jeremy Muhlich E<lt>jmuhlich[at]bitflood.orgE<gt> help me
escaped character handling in JSON::Parser.

Adam Sussman E<lt>adam.sussman[at]ticketmaster.comE<gt>
suggested the octal and hexadecimal formats as number.
Sussman also sent the 'key sort' and 'hex number autoconv' patch
and 'HASH KEY SORT ORDER' section.

Tatsuhiko Miyagawa E<lt>miyagawa[at]bulknews.netE<gt>
taught a terrible typo and gave some suggestions.

David Wheeler E<lt>david[at]kineticode.comE<gt>
suggested me supporting pretty-printing and
gave a part of L<PRETTY PRINTING>.

Rusty Phillips E<lt>rphillips[at]edats.comE<gt>
suggested me supporting the query object other than CGI.pm
for JSONRPC::Transport::HTTP::CGI.

Felipe Gasper E<lt>gasperfm[at]uc.eduE<gt>
pointed to a problem of JSON::NotString with undef.
And show me patches for 'bare key option' & 'single quotation option'.

Yaman Saqqa E<lt>abulyomon[at]gmail.comE<gt>
helped my decision to support the bare key option.

Alden DoRosario E<lt>adorosario[at]chitika.comE<gt>
tought JSON::Conveter::_stringfy (<= 0.992) is very slow.

Brad Baxter sent to 'key sort' patch and thought a bug in JSON.

Jacob and Jay Buffington sent 'blessed object conversion' patch.

Thanks to Peter Edwards, IVAN, and all testers for bug reports.

Yann Kerherve sent 'selfconverter' patch(code, document and test).

Annocpan users comment on JSON pod. See http://annocpan.org/pod/JSON

And Thanks very much to JSON by JSON.org (Douglas Crockford) and
JSON-RPC by http://json-rpc.org/


=head1 AUTHOR

Makamaka Hannyaharamitu, E<lt>makamaka[at]cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2005-2007 by Makamaka Hannyaharamitu

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut


