package JSON::Converter;
##############################################################################

use Carp;

use vars qw($VERSION $USE_UTF8);
use strict;
use JSON ();
use B ();


$VERSION = '1.13';

BEGIN {
    eval 'require Scalar::Util';
    unless($@){
        *JSON::Converter::blessed = \&Scalar::Util::blessed;
    }
    else{ # This code is from Sclar::Util.
        # warn $@;
        eval 'sub UNIVERSAL::a_sub_not_likely_to_be_here { ref($_[0]) }';
        *JSON::Converter::blessed = sub {
            local($@, $SIG{__DIE__}, $SIG{__WARN__});
            ref($_[0]) ? eval { $_[0]->a_sub_not_likely_to_be_here } : undef;
        };
    }

    if ($] < 5.006) {
        eval q{
            sub B::SVf_IOK () { 0x00010000; }
            sub B::SVf_NOK () { 0x00020000; }
        };
    }

    $USE_UTF8 = JSON->USE_UTF8;

}


##############################################################################

sub new {
    my $class = shift;
    bless {indent => 2, pretty => 0, delimiter => 2, @_}, $class;
}


sub objToJson {
    my $self = shift;
    my $obj  = shift;
    my $opt  = shift;

    local(@{$self}{qw/autoconv execcoderef skipinvalid/});
    local(@{$self}{qw/pretty indent delimiter keysort convblessed utf8 singlequote/});

    $self->_initConvert($opt);

    if($self->{convblessed}){
        $obj = _blessedToNormalObject($obj);
    }

    #(not hash for speed)
    local @JSON::Converter::obj_addr; # check circular references 
    # for speed
    local $JSON::Converter::pretty  = $self->{pretty};
    local $JSON::Converter::keysort = !$self->{keysort}                ? undef
                                     : ref($self->{keysort}) eq 'CODE' ? $self->{keysort}
                                     : $self->{keysort} =~ /\D+/       ? $self->{keysort}
                                     : sub { $a cmp $b };
    local $JSON::Converter::autoconv    = $self->{autoconv};
    local $JSON::Converter::execcoderef = $self->{execcoderef};
    local $JSON::Converter::selfconvert = $self->{selfconvert};
    local $JSON::Converter::utf8        = $self->{utf8};

    local *_stringfy = *_stringfy_single_quote if($self->{singlequote});

    return $self->_toJson($obj);
}


*hashToJson  = \&objToJson;
*arrayToJson = \&objToJson;
*valueToJson = \&_valueToJson;


sub _toJson {
    my ($self, $obj) = @_;

    if(ref($obj) eq 'HASH'){
        return $self->_hashToJson($obj);
    }
    elsif(ref($obj) eq 'ARRAY'){
        return $self->_arrayToJson($obj);
    }
    elsif( $JSON::Converter::selfconvert
             and blessed($obj) and $obj->can('toJson') ){
        return $self->_selfToJson($obj);
    }
    else{
        return;
    }
}


sub _hashToJson {
    my ($self, $obj) = @_;
    my ($k,$v);
    my %res;

    if (my $class = tied %$obj) { # by ddascalescu+perl [at] gmail.com
        $class =~ s/=.*//;
        tie %res, $class;
    }

    my ($pre,$post) = $self->_upIndent() if($JSON::Converter::pretty);

    if (grep { $_ == $obj } @JSON::Converter::obj_addr) {
        die "circle ref!";
    }

    push @JSON::Converter::obj_addr,$obj;

    for my $k (keys %$obj) {
        my $v = $obj->{$k};
        $res{$k} = $self->_toJson($v) || $self->_valueToJson($v);
    }

    pop @JSON::Converter::obj_addr;

    if ($JSON::Converter::pretty) {
        $self->_downIndent();
        my $del = $self->{_delstr};
        return "{$pre"
         . join(",$pre", map { _stringfy($_) . $del .$res{$_} }
                (defined $JSON::Converter::keysort ? ( sort $JSON::Converter::keysort (keys %res)) : (keys %res) )
                ). "$post}";
    }
    else{
        return '{'. join(',',map { _stringfy($_) .':' .$res{$_} } 
                    (defined $JSON::Converter::keysort ?
                        ( sort $JSON::Converter::keysort (keys %res)) : (keys %res) )
                ) .'}';
    }

}


sub _arrayToJson {
    my ($self, $obj) = @_;
    my @res;

    if (my $class = tied @$obj) {
        $class =~ s/=.*//;
        tie @res, $class;
    }

    my ($pre,$post) = $self->_upIndent() if($JSON::Converter::pretty);

    if(grep { $_ == $obj } @JSON::Converter::obj_addr){
        die "circle ref!";
    }

    push @JSON::Converter::obj_addr,$obj;

    for my $v (@$obj){
        push @res, $self->_toJson($v) || $self->_valueToJson($v);
    }

    pop @JSON::Converter::obj_addr;

    if ($JSON::Converter::pretty) {
        $self->_downIndent();
        return "[$pre" . join(",$pre" ,@res) . "$post]";
    }
    else {
        return '[' . join(',' ,@res) . ']';
    }
}


sub _selfToJson {
    my ($self, $obj) = @_;
    if(grep { $_ == $obj } @JSON::Converter::obj_addr){
        die "circle ref!";
    }
    push @JSON::Converter::obj_addr, $obj;
    return $obj->toJson($self);
}


sub _valueToJson {
	my ($self, $value) = @_;

    return 'null' if(!defined $value);

    if(!ref($value)){
        if($JSON::Converter::autoconv){
            return $value  if($value =~ /^-?(?:0|[1-9][\d]*)(?:\.\d*)?(?:[eE][-+]?\d+)?$/);
            return $value  if($value =~ /^0[xX](?:[0-9a-fA-F])+$/);
            return 'true'  if($value =~ /^[Tt][Rr][Uu][Ee]$/);
            return 'false' if($value =~ /^[Ff][Aa][Ll][Ss][Ee]$/);
        }

        my $b_obj = B::svref_2object(\$value);  # for round trip problem
        # SvTYPE is IV or NV?
        return $value # as is 
                if ($b_obj->FLAGS & B::SVf_IOK or $b_obj->FLAGS & B::SVf_NOK);

        return _stringfy($value);
    }
    elsif($JSON::Converter::execcoderef and ref($value) eq 'CODE'){
        my $ret = $value->();
        return 'null' if(!defined $ret);
        return $self->_toJson($ret) || _stringfy($ret);
    }
    elsif( blessed($value) and  $value->isa('JSON::NotString') ){
        return defined $value->{value} ? $value->{value} : 'null';
    }
    else {
        die "Invalid value" unless($self->{skipinvalid});
        return 'null';
    }

}


my %esc = (
    "\n" => '\n',
    "\r" => '\r',
    "\t" => '\t',
    "\f" => '\f',
    "\b" => '\b',
    "\"" => '\"',
    "\\" => '\\\\',
    "\'" => '\\\'',
#    "/"  => '\\/', # TODO
);


sub _stringfy {
    my ($arg) = @_;
    $arg =~ s/([\\"\n\r\t\f\b])/$esc{$1}/eg;

    unless (JSON->USE_UTF8) {
        $arg =~ s/([\x00-\x07\x0b\x0e-\x1f])/'\\u00' . unpack('H2',$1)/eg;
        return '"' . $arg . '"';
    }

    # suggestion from rt#25727
    $arg = join('',
        map {
            chr($_) =~ /[\x00-\x07\x0b\x0e-\x1f]/ ?
                sprintf('\u%04x', $_) :
            $_ <= 255 ?
                chr($_) :
            $_ <= 65535 ?
                sprintf('\u%04x', $_) : sprintf('\u%04x', $_)
        } unpack('U*', $arg)
    );

    $JSON::Converter::utf8 and utf8::decode($arg);

    return '"' . $arg . '"';
}


sub _stringfy_single_quote {
    my $arg = shift;
    $arg =~ s/([\\\n'\r\t\f\b])/$esc{$1}/eg;

    unless (JSON->USE_UTF8) {
        $arg =~ s/([\x00-\x07\x0b\x0e-\x1f])/'\\u00' . unpack('H2',$1)/eg;
        return "'" . $arg ."'";
    }

    $arg = join('',
        map {
            chr($_) =~ /[\x00-\x07\x0b\x0e-\x1f]/ ?
                sprintf('\u%04x', $_) :
            $_ <= 255 ?
                chr($_) :
            $_ <= 65535 ?
                sprintf('\u%04x', $_) : sprintf('\u%04x', $_)
        } unpack('U*', $arg)
    );

    $JSON::Converter::utf8 and utf8::decode($arg);

    return "'" . $arg ."'";
};


##############################################################################

sub _initConvert {
    my $self = shift;
    my %opt  = %{ $_[0] } if(@_ > 0 and ref($_[0]) eq 'HASH');

    $self->{autoconv}    = $JSON::AUTOCONVERT if(!defined $self->{autoconv});
    $self->{execcoderef} = $JSON::ExecCoderef if(!defined $self->{execcoderef});
    $self->{skipinvalid} = $JSON::SkipInvalid if(!defined $self->{skipinvalid});

    $self->{pretty}      = $JSON::Pretty      if(!defined $self->{pretty});
    $self->{indent}      = $JSON::Indent      if(!defined $self->{indent});
    $self->{delimiter}   = $JSON::Delimiter   if(!defined $self->{delimiter});
    $self->{keysort}     = $JSON::KeySort     if(!defined $self->{keysort});
    $self->{convblessed} = $JSON::ConvBlessed if(!defined $self->{convblessed});
    $self->{selfconvert} = $JSON::SelfConvert if(!defined $self->{selfconvert});
    $self->{utf8}        = $JSON::UTF8        if(!defined $self->{utf8});
    $self->{singlequote} = $JSON::SingleQuote if(!defined $self->{singlequote});

    for my $name (qw/autoconv execcoderef skipinvalid pretty
                     indent delimiter keysort convblessed selfconvert utf8 singlequote/){
        $self->{$name} = $opt{$name} if(defined $opt{$name});
    }

    if($self->{utf8} and !$USE_UTF8){
        $self->{utf8} = 0; warn "JSON::Converter couldn't use utf8.";
    }

    $self->{indent_count} = 0;

    $self->{_delstr} = 
        $self->{delimiter} ? ($self->{delimiter} == 1 ? ': ' : ' : ') : ':';

    $self;
}


sub _upIndent {
    my $self  = shift;
    my $space = ' ' x $self->{indent};

    my ($pre,$post) = ('','');

    $post = "\n" . $space x $self->{indent_count};

    $self->{indent_count}++;

    $pre = "\n" . $space x $self->{indent_count};

    return ($pre,$post);
}


sub _downIndent { $_[0]->{indent_count}--; }


#
# converting the blessed object to the normal object
#

sub _blessedToNormalObject { require overload;
    my ($obj) = @_;

    local @JSON::Converter::_blessedToNormal::obj_addr;

    return _blessedToNormal($obj);
}


sub _getObjType {
    return '' if(!ref($_[0]));
    ref($_[0]) eq 'HASH'  ? 'HASH' :
    ref($_[0]) eq 'ARRAY' ? 'ARRAY' :
    $_[0]->isa('JSON::NotString') ?  '' :
    (overload::StrVal($_[0]) =~ /=(\w+)/)[0];
}


sub _blessedToNormal {
    my $type  = _getObjType($_[0]);
    return $type eq 'HASH'   ? _blessedToNormalHash($_[0])   : 
           $type eq 'ARRAY'  ? _blessedToNormalArray($_[0])  : 
           $type eq 'SCALAR' ? _blessedToNormalScalar($_[0]) : $_[0];
}


sub _blessedToNormalHash {
    my ($obj) = @_;
    my %res;

    die "circle ref!" if(grep { overload::AddrRef($_) eq overload::AddrRef($obj) }
                          @JSON::Converter::_blessedToNormal::obj_addr);

    push @JSON::Converter::_blessedToNormal::obj_addr, $obj;

    for my $k (keys %$obj){
        $res{$k} = _blessedToNormal($obj->{$k});
    }

    pop @JSON::Converter::_blessedToNormal::obj_addr;

    return \%res;
}


sub _blessedToNormalArray {
    my ($obj) = @_;
    my @res;

    die "circle ref!" if(grep { overload::AddrRef($_) eq overload::AddrRef($obj) }
                          @JSON::Converter::_blessedToNormal::obj_addr);

    push @JSON::Converter::_blessedToNormal::obj_addr, $obj;

    for my $v (@$obj){
        push @res, _blessedToNormal($v);
    }

    pop @JSON::Converter::_blessedToNormal::obj_addr;

    return \@res;
}


sub _blessedToNormalScalar {
    my ($obj) = @_;
    my $res;

    die "circle ref!" if(grep { overload::AddrRef($_) eq overload::AddrRef($obj) }
    @JSON::Converter::_blessedToNormal::obj_addr);

    push @JSON::Converter::_blessedToNormal::obj_addr, $obj;

    $res = _blessedToNormal($$obj);

    pop @JSON::Converter::_blessedToNormal::obj_addr;

    return $res; # JSON can't really do scalar refs so it can't be \$res
}

##############################################################################
1;
__END__


=head1 METHODs

=over

=item objToJson

convert a passed perl data structure into JSON object.
can't parse bleesed object by default.

=item hashToJson

convert a passed hash into JSON object.

=item arrayToJson

convert a passed array into JSON array.

=item valueToJson

convert a passed data into a string of JSON.

=back

=head1 COPYRIGHT

makamaka [at] donzoko.net

This library is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<JSON>,
L<http://www.crockford.com/JSON/index.html>

=cut
