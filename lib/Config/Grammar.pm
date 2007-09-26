package Config::Grammar;
use strict;

$Config::Grammar::VERSION = '1.10';

sub new($$)
{
    my $proto   = shift;
    my $grammar = shift;
    my $class   = ref($proto) || $proto;

    my $self = {grammar => $grammar};
    bless($self, $class);
    return $self;
}

sub err($)
{
    my $self = shift;
    return $self->{'err'};
}

sub _make_error($$)
{
    my $self = shift;
    my $text = shift;
    $self->{'err'} = "$self->{file}, line $self->{line}: $text";
}

sub _peek($)
{
    my $a = shift;
    return $a->[$#$a];
}

sub _quotesplit($)
{
    my $line = shift;
    my @items;
    while ($line ne "") {
        if ($line =~ s/^"((?:\\.|[^"])*)"\s*//) {
            my $frag = $1;
            $frag =~ s/\\(.)/$1/g;
            push @items, $frag;              
        } elsif ($line =~ s/^'((?:\\.|[^'])*)'\s*//) {
            my $frag = $1;
            $frag =~ s/\\(.)/$1/g;
            push @items, $frag;              
        }
        elsif ($line =~ s/^((?:\\.|[^\s])*)(?:\s+|$)//) {
            my $frag = $1;
            $frag =~ s/\\(.)/$1/g;
            push @items, $frag;
        }
        else {
            die "Internal parser error for '$line'";
        }
    }
    return @items;
}

sub _check_mandatory($$$$)
{
    my $self    = shift;
    my $g       = shift;
    my $c       = shift;
    my $section = shift;

    # check _mandatory sections, variables and tables
    if (defined $g->{_mandatory}) {
        for (@{$g->{_mandatory}}) {
            if (not defined $g->{$_}) {
                $g->{$_} = {};
            }
            if (not defined $c->{$_}) {
                if (defined $section) {
                    $self->{'err'} .= "$self->{file} ($section): ";
                }
                else {
                    $self->{'err'} = "$self->{file}: ";
                }

                if (defined $g->{$_}{_is_section}) {
                    $self->{'err'} .= "mandatory (sub)section '$_' not defined";
                }
                elsif ($_ eq '_table') {
                    $self->{'err'} .= "mandatory table not defined";
                }
                else {
                    $self->{'err'} .= "mandatory variable '$_' not defined";
                }
                return 0;
            }
        }
    }

    for (keys %$c) {

        # do some cleanup
        ref $c->{$_} eq 'HASH' or next;
        defined $c->{$_}{_is_section} or next;
        $self->_check_mandatory($g->{$c->{$_}{_grammar}}, $c->{$_},
          defined $section ? "$section/$_" : "$_") or return 0;
        delete $c->{$_}{_is_section};
        delete $c->{$_}{_grammar};
        delete $c->{$_}{_order_count} if exists $c->{$_}{_order_count};
    }

    return 1;
}

######### SECTIONS #########

# search grammar definition of a section
sub _search_section($$)
{
    my $self = shift;
    my $name = shift;

    if (not defined $self->{grammar}{_sections}) {
        $self->_make_error("no sections are allowed");
        return undef;
    }

    # search exact match
    for (@{$self->{grammar}{_sections}}) {
        if ($name eq $_) {
            return $_;
        }
    }

    # search regular expression
    for (@{$self->{grammar}{_sections}}) {
        if (m|^/(.*)/$|) {
            if ($name =~ /^$1$/) {
                return $_;
            }
        }
    }

    # no match
    $self->_make_error("unknown section '$name'");
    return undef;
}

# fill in default values for this section
sub _fill_defaults ($) {
    my $self = shift;
    my $g = $self->{grammar};
    my $c = $self->{cfg};
    if ($g->{_vars}) {
        for my $var (@{$g->{_vars}}) {
                next if exists $c->{$var};
                my $value = $g->{$var}{_default}
                  if exists $g->{$var}{_default};
                next unless defined $value;
                $c->{$var} = $value;
        }
    }

}

sub _next_level($$$)
{
    my $self = shift;
    my $name = shift;

    # section name
    if (defined $self->{section}) {
        $self->{section} .= "/$name";
    }
    else {
        $self->{section} = $name;
    }

    # grammar context
    my $s = $self->_search_section($name);
    return 0 unless defined $s;
    if (not defined $self->{grammar}{$s}) {
        $self->_make_error("Config::Grammar internal error (no grammar for $s)");
        return 0;
    }
    push @{$self->{grammar_stack}}, $self->{grammar};
    $self->{grammar} = $self->{grammar}{$s};

    # support for inherited values
    # note that we have to do this on the way down
    # and keep track of which values were inherited
    # so that we can propagate the values even further
    # down if needed
    my %inherited;
    if ($self->{grammar}{_inherited}) {
        for my $var (@{$self->{grammar}{_inherited}}) {
                next unless exists $self->{cfg}{$var};
                my $value = $self->{cfg}{$var};
                next unless defined $value;
                next if ref $value; # it's a section
                $inherited{$var} = $value;
        }
    }

    # config context
    my $order;
    if (defined $self->{grammar}{_order}) {
        if (defined $self->{cfg}{_order_count}) {
            $order = ++$self->{cfg}{_order_count};
        }
        else {
            $order = $self->{cfg}{_order_count} = 0;
        }
    }

    if (defined $self->{cfg}{$name}) {
        $self->_make_error('section or variable already exists');
        return 0;
    }
    $self->{cfg}{$name} = { %inherited }; # inherit the values
    push @{$self->{cfg_stack}}, $self->{cfg};
    $self->{cfg} = $self->{cfg}{$name};

    # keep track of the inherited values here;
    # we delete it on the way up in _prev_level()
    $self->{cfg}{_inherited} = \%inherited; 

    # list of already defined variables on this level
    if (defined $self->{grammar}{_varlist}) {
	$self->{cfg}{_varlist} = [];
    }

    # meta data for _mandatory test
    $self->{grammar}{_is_section} = 1;
    $self->{cfg}{_is_section}     = 1;
    $self->{cfg}{_grammar}        = $s;
    $self->{cfg}{_order} = $order if defined $order;

    # increase level
    $self->{level}++;

    return 1;
}

sub _prev_level($)
{
    my $self = shift;

    # fill in the values from _default keywords when going up
    $self->_fill_defaults;

    # section name
    if (defined $self->{section}) {
        if ($self->{section} =~ /\//) {
            $self->{section} =~ s/\/.*?$//;
        }
        else {
            $self->{section} = undef;
        }
    }

    # clean up the _inherited hash, we won't need it anymore
    delete $self->{cfg}{_inherited};

    # config context
    $self->{cfg} = pop @{$self->{cfg_stack}};

    # grammar context
    $self->{grammar} = pop @{$self->{grammar_stack}};

    # decrease level
    $self->{level}--;
}

sub _goto_level($$$)
{
    my $self  = shift;
    my $level = shift;
    my $name  = shift;

    # _text is multi-line. Check when changing level
    $self->_check_text($self->{section}) or return 0;

    if ($level > $self->{level}) {
        if ($level > $self->{level} + 1) {
            $self->_make_error("section nesting error");
            return 0;
        }
        $self->_next_level($name) or return 0;
    }
    else {

        while ($self->{level} > $level) {
            $self->_prev_level;
        }
        if ($level != 0) {
            $self->_prev_level;
            $self->_next_level($name) or return 0;
        }
    }

    return 1;
}

######### VARIABLES #########

# search grammar definition of a variable
sub _search_variable($$)
{
    my $self = shift;
    my $name = shift;

    if (not defined $self->{grammar}{_vars}) {
        $self->_make_error("no variables are allowed");
        return undef;
    }

    # search exact match
    for (@{$self->{grammar}{_vars}}) {
        if ($name eq $_) {
            return $_;
        }
    }

    # search regular expression
    for (@{$self->{grammar}{_vars}}) {
        if (m|^/(.*)/$|) {
            if ($name =~ /^$1$/) {
                return $_;
            }
        }
    }

    # no match
    $self->_make_error("unknown variable '$name'");
    return undef;
}

sub _set_variable($$$)
{
    my $self  = shift;
    my $key   = shift;
    my $value = shift;
    
    my $gn = $self->_search_variable($key);
    defined $gn or return 0;

    my $varlistref;
    if (defined $self->{grammar}{_varlist}) {
	$varlistref = $self->{cfg}{_varlist};
    }

    if (defined $self->{grammar}{$gn}) {
        my $g = $self->{grammar}{$gn};

        # check regular expression
        if (defined $g->{_re}) {
            $value =~ /^$g->{_re}$/ or do {
                if (defined $g->{_re_error}) {
                    $self->_make_error($g->{_re_error});
                }
                else {
                    $self->_make_error("syntax error in value of '$key'");
                }
                return 0;
              }
        }
        if (defined $g->{_sub}){
                my $error = &{$g->{_sub}}($value, $varlistref);
                if (defined $error){
                        $self->_make_error($error);
                        return 0;
                }
        }
    }
    $self->{cfg}{$key} = $value;
    push @{$varlistref}, $key if ref $varlistref;

    return 1;
}

######### PARSER #########

sub _parse_table($$)
{
    my $self = shift;
    local $_ = shift;

    my $g = $self->{grammar}{_table};
    defined $g or do {
        $self->_make_error("table syntax error");
        return 0;
    };

    my @l = _quotesplit $_;

    # check number of columns
    my $columns = $g->{_columns};
    if (defined $columns and $#l + 1 != $columns) {
        $self->_make_error("row must have $columns columns (has " . ($#l + 1)
          . ")");
        return 0;
    }

    # check columns
    my $n = 0;
    for my $c (@l) {
        my $gc = $g->{$n};
        defined $gc or next;

        # regular expression
        if (defined $gc->{_re}) {
            $c =~ /^$gc->{_re}$/ or do {
                if (defined $gc->{_re_error}) {
                    $self->_make_error("column ".($n+1).": $gc->{_re_error}");
                }
                else {
                    $self->_make_error("syntax error in column ".($n+1));
                }
                return 0;
            };
        }
        if (defined $gc->{_sub}){
                my $error = &{$gc->{_sub}}($c);
                if (defined $error) {
                        $self->_make_error($error);
                        return 0;
                }
        }
        $n++;
    }

    # hash (keyed table)
    if (defined $g->{_key}) {
        my $kn = $g->{_key};
        if ($kn < 0 or $kn > $#l) {
            $self->_make_error("grammar error: key out of bounds");
        }
        my $k = $l[$kn];

        if (defined $self->{cfg}{$k}) {
            $self->_make_error("table row $k already defined");
            return 0;
        }
        $self->{cfg}{$k} = \@l;
    }

    # list (unkeyed table)
    else {
        push @{$self->{cfg}{_table}}, \@l;
    }

    return 1;
}

sub _parse_text($$)
{
    my ($self, $line) = @_;

    $self->{cfg}{_text} .= $line;

    return 1;
}

sub _check_text($$)
{
    my ($self, $name) = @_;

    my $g = $self->{grammar}{_text};
    defined $g or return 1;

    # chop empty lines at beginning and end
    if(defined $self->{cfg}{_text}) {
	$self->{cfg}{_text} =~ s/\A([ \t]*[\n\r]+)*//m;
	$self->{cfg}{_text} =~  s/^([ \t]*[\n\r]+)*\Z//m;
    }

    if (defined $g->{_re}) {
        $self->{cfg}{_text} =~ /^$g->{_re}$/ or do {
            if (defined $g->{_re_error}) {
                $self->_make_error($g->{_re_error});
            }
            else {
                $self->_make_error("syntax error");
            }
            return 0;
          }
    }
    if (defined $g->{_sub}){
        my $error =  &{$g->{_sub}}($self->{cfg}{_text});
        if (defined $error) {
            $self->_make_error($error);
            return 0;
        }
    }
    return 1;
}

sub _parse_file($$);

sub _parse_line($$$)
{
    my $self = shift;
    local $_ = shift;
    my $source = shift;

    /^\@include\s+["']?(.*)["']?$/ and do {
	my $inc = $1;
        if ( ( $^O eq 'win32' and $inc !~ m|^(?:[a-z]:)?[/\\]|i and  $self->{file} =~ m|^(.+)[\\/][^/]+$| ) or
	     ( $inc !~ m|^/| and $self->{file} =~ m|^(.+)/[^/]+$| ) ){
	   $inc = "$1/$inc";
        }	
        push @{$self->{file_stack}}, $self->{file};
        push @{$self->{line_stack}}, $self->{line};
        $self->_parse_file($inc) or return 0;
        $self->{file} = pop @{$self->{file_stack}};
        $self->{line} = pop @{$self->{line_stack}};
        return 1;
    };
    /^\@define\s+(\S+)\s+(.*)$/ and do {
	$self->{defines}{$1}=$2;
	return 1;
    };

    if(defined $self->{defines}) {
	for my $d (keys %{$self->{defines}}) {
	    s/$d/$self->{defines}{$d}/g;
	}
    }

    /^\*\*\*\s*(.*?)\s*\*\*\*$/ and do {
    	my $name = $1;
        $self->_goto_level(1, $name) or return 0;
	$self->_check_section_sub($name) or return 0;
        return 1;
    };
    /^(\++)\s*(.*)$/ and do {
        my $level = length $1;
    	my $name = $2;
        $self->_goto_level($level + 1, $name) or return 0;
	$self->_check_section_sub($name) or return 0;
        return 1;
    };

    if (defined $self->{grammar}{_text}) {
        $self->_parse_text($source) or return 0;
        return 1;
    }
    /^(\S+)\s*=\s*(.*)$/ and do {
        if (defined $self->{cfg}{$1}) {
            if (exists $self->{cfg}{_inherited}{$1}) {
                # it's OK to override any inherited values
                delete $self->{cfg}{_inherited}{$1};
                delete $self->{cfg}{$1};
            } else {
                $self->_make_error('variable already defined');
                return 0;
            }
        }
        $self->_set_variable($1, $2) or return 0;
        return 1;
    };

    $self->_parse_table($_) or return 0;

    return 1;
}

sub _check_section_sub($$) {
	my $self = shift;
	my $name = shift;
	my $g = $self->{grammar};
        if (defined $g->{_sub}){
                my $error = &{$g->{_sub}}($name);
                if (defined $error){
                        $self->_make_error($error);
                        return 0;
                }
        }
	return 1;
}

sub _parse_file($$)
{
    my $self = shift;
    my $file = shift;

    local *File;
    unless ($file) { $self->{'err'} = "no filename given" ;
                     return undef;};
    open(File, "$file") or do {
        $self->{'err'} = "can't open $file: $!";
        return undef;
    };
    $self->{file} = $file;

    local $_;
    my $source = '';
    while (<File>) {
	$source .= $_;
        chomp;
        s/^\s+//;
        s/\s+$//;            # trim
        s/\s*#.*$//;         # comments
        next if $_ eq '';    # empty lines
        while (/\\$/) {# continuation
            s/\\$//;
            my $n = <File>;
            last if not defined $n;
            chomp $n;
            $n =~ s/^\s+//;
            $n =~ s/\s+$//;    # trim
            $_ .= ' ' . $n;
        }

        $self->{line} = $.;
        $self->_parse_line($_, $source) or do{ close File; return 0; };
	$source = '';
    }
    close File;
    return 1;
}

sub makepod($) {
    my $pod = eval {
	require Config::Grammar::Document;
	return Config::Grammar::Document::makepod(@_);
    };
    defined $pod or die "ERROR: install Config::Grammar::Document in order to use makepod(): $@\n";
    return $pod;
}

sub maketmpl ($@) {
    my $pod = eval {
	require Config::Grammar::Document;
	return Config::Grammar::Document::maketmpl(@_);
    };
    defined $pod or die "ERROR: install Config::Grammar::Document in order to use maketmpl()\n";
    return $pod;
}

sub makemintmpl ($@) {
    my $pod = eval {
	require Config::Grammar::Document;
	return Config::Grammar::Document::makemintmpl(@_);
    };
    defined $pod or die "ERROR: install Config::Grammar::Document in order to use makemintmpl()\n";
    return $pod;
}

sub parse($$)
{
    my $self = shift;
    my $file = shift;

    $self->{cfg}           = {};
    $self->{level}         = 0;
    $self->{cfg_stack}     = [];
    $self->{grammar_stack} = [];
    $self->{file_stack}    = [];
    $self->{line_stack}    = [];

    $self->_parse_file($file) or return undef;

    $self->_goto_level(0, undef) or return undef;

    # fill in the top level values from _default keywords
    $self->_fill_defaults;

    $self->_check_mandatory($self->{grammar}, $self->{cfg}, undef)
      or return undef;

    return $self->{cfg};

}

1;

__END__

=head1 NAME

Config::Grammar - A grammar-based, user-friendly config parser

=head1 SYNOPSIS

 use Config::Grammar;

 my $parser = Config::Grammar->new(\%grammar);
 my $cfg = $parser->parse('app.cfg') or die "ERROR: $parser->{err}\n";
 my $pod = $parser->makepod();
 my $ex = $parser->maketmpl('TOP','SubNode');
 my $minex = $parser->maketmplmin('TOP','SubNode');

=head1 DESCRIPTION

Config::Grammar is a module to parse configuration files. The
configuration may consist of multiple-level sections with assignments
and tabular data. The parsed data will be returned as a hash
containing the whole configuration. Config::Grammar uses a grammar
that is supplied upon creation of a Config::Grammar object to parse
the configuration file and return helpful error messages in case of
syntax errors. Using the B<makepod> method you can generate
documentation of the configuration file format.

The B<maketmpl> method can generate a template configuration file.  If
your grammar contains regexp matches, the template will not be all
that helpful as Config::Grammar is not smart enough to give you sensible
template data based in regular expressions. The related function 
B<maketmplmin> generates a minimal configuration template without 
examples, regexps or comments and thus allows an experienced user to
fill in the configuration data more efficiently.


=head2 Grammar Definition

The grammar is a multiple-level hash of hashes, which follows the structure of
the configuration. Each section or variable is represented by a hash with the
same structure.  Each hash contains special keys starting with an underscore
such as '_sections', '_vars', '_sub' or '_re' to denote meta data with information
about that section or variable. Other keys are used to structure the hash
according to the same nesting structure of the configuration itself. The
starting hash given as parameter to 'new' contains the "root section".

=head3 Special Section Keys

=over 12

=item _sections

Array containing the list of sub-sections of this section. Each sub-section
must then be represented by a sub-hash in this hash with the same name of the
sub-section.

The sub-section can also be a regular expression denoted by the syntax '/re/',
where re is the regular-expression. In case a regular expression is used, a
sub-hash named with the same '/re/' must be included in this hash.

=item _vars

Array containing the list of variables (assignments) in this section.
Analogous to sections, regular expressions can be used.

=item _mandatory

Array containing the list of mandatory sections and variables.

=item _inherited

Array containing the list of the variables that should be assigned the
same value as in the parent section if nothing is specified here.

=item _table

Hash containing the table grammar (see Special Table Keys). If not specified,
no table is allowed in this section. The grammar of the columns if specified
by sub-hashes named with the column number.

=item _text

Section contains free-form text. Only sections and @includes statements will
be interpreted, the rest will be added in the returned hash under '_text' as
string.

B<_text> is a hash reference which can contain a B<_re> and a B<_re_error> key
which will be used to scrutanize the text ... if the hash is empty, all text
will be accepted.

=item _order

If defined, a '_order' element will be put in every hash containing the
sections with a number that determines the order in which the sections were
defined.

=item _doc

Describes what this section is about

=item _sub

A function pointer. It is called for every instance of this section,
with the real name of the section passed as its first argument. This is
probably only useful for the regexp sections. If the function returns
a defined value it is assumed that the test was not successful and an
error is generated with the returned string as content.

=back

=head3 Special Variable Keys

=over 12

=item _re

Regular expression upon which the value will be checked.

=item _re_error

String containing the returned error in case the regular expression doesn't
match (if not specified, a generic 'syntax error' message will be returned).

=item _sub

A function pointer. It called for every value, with the value passed as its
first argument. If the function returns a defined value it is assumed that
the test was not successful and an error is generated with the returned
string as content.

If the '_varlist' key (see above) is defined in this section, the '_sub'
function will also receive an array reference as the second argument. The
array contains a list of those variables already defined in the same
section. This can be used to enforce the order of the variables.

=item _default

A default value that will be assigned to the variable if none is specified or inherited.

=item _doc

Description of the variable.

=item _example

A one line example for the content of this variable.

=back

=head3 Special Table Keys

=over 12

=item _columns

Number of columns. If not specified, it will not be enforced.

=item _key

If defined, the specified column number will be used as key in a hash in the
returned hash. If not defined, the returned hash will contain a '_table'
element with the contents of the table as array. The rows of the tables are
stored as arrays.

=item _sub

they work analog to the description in the previous section.

=item _doc

describes the content of the column.

=item _example

example for the content of this column

=back

=head3 Special Text Keys

=over 12

=item _re

Regular expression upon which the text will be checked (everything as a single
line).

=item _re_error

String containing the returned error in case the regular expression doesn't
match (if not specified, a generic 'syntax error' message will be returned).

=item _sub

they work analog to the description in the previous section.

=item _doc

Ditto.

=item _example

Potential multi line example for the content of this text section

=back

=head2 Configuration Syntax

=head3 General Syntax

'#' denotes a comment up to the end-of-line, empty lines are allowed and space
at the beginning and end of lines is trimmed.

'\' at the end of the line marks a continued line on the next line. A single
space will be inserted between the concatenated lines.

'@include filename' is used to include another file. Include works relative to the
directory where the parent file is in.

'@define a some value' will replace all occurences of 'a' in the following text
with 'some value'.

Fields in tables that contain white space can be enclosed in either C<'> or C<">.
Whitespace can also be escaped with C<\>. Quotes inside quotes are allowed but must
be escaped with a backslash as well.

=head3 Sections

Config::Grammar supports hierarchical configurations through sections, whose
syntax is as follows:

=over 15 

=item Level 1

*** section name ***

=item Level 2

+ section name

=item Level 3

++ section name

=item Level n, n>1

+..+ section name (number of '+' determines level)

=back

=head3 Assignments

Assignements take the form: 'variable = value', where value can be any string
(can contain whitespaces and special characters). The spaces before and after
the equal sign are optional.

=head3 Tabular Data

The data is interpreted as one or more columns separated by spaces.

=head2 Example

=head3 Code

 use Data::Dumper;
 use Config::Grammar;

 my $RE_IP       = '\d+\.\d+\.\d+\.\d+';
 my $RE_MAC      = '[0-9a-f]{2}(?::[0-9a-f]{2}){5}';
 my $RE_HOST     = '\S+';

 my $parser = Config::Grammar->new({
   _sections => [ 'network', 'hosts' ],
   network => {
      _vars     => [ 'dns' ],
      _sections => [ "/$RE_IP/" ],
      dns       => {
         _doc => "address of the dns server",
         _example => "ns1.oetiker.xs",
         _re => $RE_HOST,
         _re_error =>
            'dns must be an host name or ip address',
         },
      "/$RE_IP/" => {
         _doc    => "Ip Adress",
         _example => '10.2.3.2',
         _vars   => [ 'netmask', 'gateway' ],
         netmask => {
	    _doc => "Netmask",
	    _example => "255.255.255.0",
            _re => $RE_IP,
            _re_error =>
               'netmask must be a dotted ip address'
            },
         gateway => {
	    _doc => "Default Gateway address in IP notation",
	    _example => "10.22.12.1",
            _re => $RE_IP,
            _re_error =>
               'gateway must be a dotted ip address' },
         },
      },
   hosts => {
      _doc => "Details about the hosts",
      _table  => {
	  _doc => "Description of all the Hosts",
         _key => 0,
         _columns => 3,
         0 => {
            _doc => "Ethernet Address",
            _example => "0:3:3:d:a:3:dd:a:cd",
            _re => $RE_MAC,
            _re_error =>
               'first column must be an ethernet mac address',
            },
         1 => {
            _doc => "IP Address",
            _example => "10.11.23.1",
            _re => $RE_IP,
            _re_error =>
               'second column must be a dotted ip address',
            },
         2 => {
            _doc => "Host Name",
            _example => "tardis",
             },
         },
      },
   });

 my $cfg = $parser->parse('test.cfg') or
   die "ERROR: $parser->{err}\n";
 print Dumper($cfg);
 print $parser->makepod;

=head3 Configuration

 *** network ***
  
   dns      = 192.168.7.87
  
 + 192.168.7.64
 
   netmask  = 255.255.255.192
   gateway  = 192.168.7.65
  
 *** hosts ***
 
   00:50:fe:bc:65:11     192.168.7.97    plain.hades
   00:50:fe:bc:65:12     192.168.7.98    isg.ee.hades
   00:50:fe:bc:65:14     192.168.7.99    isg.ee.hades

=head3 Result

 {
   'hosts' => {
                '00:50:fe:bc:65:11' => [
                                         '00:50:fe:bc:65:11',
                                         '192.168.7.97',
                                         'plain.hades'
                                       ],
                '00:50:fe:bc:65:12' => [
                                         '00:50:fe:bc:65:12',
                                         '192.168.7.98',
                                         'isg.ee.hades'
                                       ],
                '00:50:fe:bc:65:14' => [
                                         '00:50:fe:bc:65:14',
                                         '192.168.7.99',
                                         'isg.ee.hades'
                                       ]
              },
   'network' => {
                  '192.168.7.64' => {
                                      'netmask' => '255.255.255.192',
                                      'gateway' => '192.168.7.65'
                                    },
                  'dns' => '192.168.7.87'
                }
 };

=head1 SEE ALSO

L<Config::Grammar::Dynamic>

=head1 COPYRIGHT

Copyright (c) 2000-2005 by ETH Zurich. All rights reserved.
Copyright (c) 2007 by David Schweikert. All rights reserved.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 AUTHORS

David Schweikert,
Tobias Oetiker,
Niko Tyni

=cut

# Emacs Configuration
#
# Local Variables:
# mode: cperl
# eval: (cperl-set-style "PerlStyle")
# mode: flyspell
# mode: flyspell-prog
# End:
#
# vi: sw=4
