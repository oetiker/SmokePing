package Config::Grammar::Dynamic;
use strict;
use Config::Grammar;
use base qw(Config::Grammar);

$Config::Grammar::Dynamic::VERSION = $Config::Grammar::VERSION;

sub _deepcopy {
        # this handles circular references on consecutive levels,
        # but breaks if there are any levels in between
        # the makepod() and maketmpl() methods have the same limitation
        my $what = shift;
        return $what unless ref $what;
        for (ref $what) {
                /^ARRAY$/ and return [ map { $_ eq $what ? $_ : _deepcopy($_) } @$what ];
                /^HASH$/ and return { map { $_ => $what->{$_} eq $what ? 
                                            $what->{$_} : _deepcopy($what->{$_}) } keys %$what };
                /^CODE$/ and return $what; # we don't need to copy the subs
                /^Regexp$/ and return $what; # neither Regexp objects
        }
        die "Cannot _deepcopy reference type @{[ref $what]}";
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
    if ($s =~ m|^/(.*)/$|) {
        # for sections specified by a regexp, we create
        # a new branch with a deep copy of the section 
        # grammar so that any _dyn sub further below will edit
        # just this branch

        $self->{grammar}{$name} = _deepcopy($self->{grammar}{$s});

        # put it at the head of the section list
        $self->{grammar}{_sections} ||= [];
        unshift @{$self->{grammar}{_sections}}, $name;
    } 

    # support for recursive sections
    # copy the section syntax to the subsection

    if ($self->{grammar}{_recursive} 
        and grep { $_ eq $s } @{$self->{grammar}{_recursive}}) {
        $self->{grammar}{$name}{_sections} ||= [];
        $self->{grammar}{$name}{_recursive} ||= [];
        push @{$self->{grammar}{$name}{_sections}}, $s;
        push @{$self->{grammar}{$name}{_recursive}}, $s;
        my $grammarcopy = _deepcopy($self->{grammar}{$name});
        if (exists $self->{grammar}{$name}{$s}) {
                # there's syntax for a variable by the same name too
                # make sure we don't lose it
                %{$self->{grammar}{$name}{$s}} = ( %$grammarcopy, %{$self->{grammar}{$name}{$s}} );
        } else {
                $self->{grammar}{$name}{$s} = $grammarcopy;
        }
    }

    # this uses the copy created above for regexp sections 
    # and the original for non-regexp sections (where $s == $name)
    $self->{grammar} = $self->{grammar}{$name};

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

    # this uses the copy created above for regexp sections 
    # and the original for non-regexp sections (where $s == $name)
    $self->{cfg}{_grammar}        = $name;

    $self->{cfg}{_order} = $order if defined $order;

    # increase level
    $self->{level}++;

    # if there's a _dyn sub, apply it
    if (defined $self->{grammar}{_dyn}) {
        &{$self->{grammar}{_dyn}}($s, $name, $self->{grammar});
    }

    return 1;
}

# find variables in old grammar list 'listname'
# that aren't in the corresponding list in the new grammar 
# and list them as a POD document, possibly with a callback
# function 'docfunc'

sub _findmissing($$$;$) {
	my $old = shift;
	my $new = shift;
	my $listname = shift;
	my $docfunc = shift;

	my @doc;
	if ($old->{$listname}) {
		my %newlist;
		if ($new->{$listname}) {
			@newlist{@{$new->{$listname}}} = undef;
		} 
		for my $v (@{$old->{$listname}}) {
			next if exists $newlist{$v};
			if ($docfunc) {
				push @doc, &$docfunc($old, $v)
			} else {
				push @doc, "=item $v";
			}
		}
	}
	return @doc;
}

# find variables in new grammar list 'listname'
# that aren't in the corresponding list in the new grammar
#
# this is just _findmissing with the arguments swapped

sub _findnew($$$;$) {
	my $old = shift;
	my $new = shift;
	my $listname = shift;
	my $docfunc = shift;
	return _findmissing($new, $old, $listname, $docfunc);
}

# compare two lists for element equality

sub _listseq($$);
sub _listseq($$) {
	my ($k, $l) = @_;
	my $length = @$k;
	return 0 unless @$l == $length;
	for (my $i=0; $i<$length; $i++) {
		return 0 unless $k->[$i] eq $l->[$i];
	}
	return 1;
}

# diff two grammar trees, documenting the differences

sub _diffgrammars($$);
sub _diffgrammars($$) {
	my $old = shift;
	my $new = shift;
	my @doc;

	my @vdoc;
	@vdoc = _findmissing($old, $new, '_vars');
	push @doc, "The following variables are not valid anymore:", "=over" , @vdoc, "=back"
		if @vdoc;
	@vdoc = _findnew($old, $new, '_vars', \&_describevar);
	push @doc, "The following new variables are valid:", "=over" , @vdoc, "=back"
		if @vdoc;
	@vdoc = _findmissing($old, $new, '_sections');
	push @doc, "The following subsections are not valid anymore:", "=over" , @vdoc, "=back"
		if @vdoc;
	@vdoc = _findnew($old, $new, '_sections', sub { 
		my ($tree, $sec) = @_; 
		my @tdoc; 
		_genpod($tree->{$sec}, 0, \@tdoc);
		return @tdoc;
	});
	push @doc, "The following new subsections are defined:", "=over" , @vdoc, "=back"
		if @vdoc;
	for (@{$old->{_sections}}) {
		next unless exists $new->{$_};
		@vdoc = _diffgrammars($old->{$_}, $new->{$_});
		push @doc, "Syntax changes for subsection B<$_>", "=over", @vdoc, "=back"
			if @vdoc;
	}
	return @doc;
}


sub _describevar {
	my $tree = shift;
	my $var = shift;
	my $mandatory = ( $tree->{_mandatory} and 
		grep {$_ eq $var} @{$tree->{_mandatory}} ) ? 
		" I<(mandatory setting)>" : ""; 
	my @doc;
	push @doc, "=item B<$var>".$mandatory;
	push @doc, $tree->{$var}{_doc} if $tree->{$var}{_doc} ;
	my $inherited = ( $tree->{_inherited} and 
		grep {$_ eq $var} @{$tree->{_inherited}});
	push @doc, "This variable I<inherits> its value from the parent section if nothing is specified here."
		if $inherited;
	push @doc, "This variable I<dynamically> modifies the grammar based on its value."
		if $tree->{$var}{_dyn};
	push @doc, "Default value: $var = $tree->{$var}{_default}"
		if ($tree->{$var}{_default});
	push @doc, "Example: $var = $tree->{$var}{_example}"
		if ($tree->{$var}{_example});
	return @doc;
}

sub _genpod($$$);
sub _genpod($$$)
{
    my ($tree, $level, $doc) = @_;
    my %dyndoc;
    if ($tree->{_vars}){
	push @{$doc}, "The following variables can be set in this section:";
	push @{$doc}, "=over";
	foreach my $var (@{$tree->{_vars}}){
	    push @{$doc}, _describevar($tree, $var);
	}
	push @{$doc}, "=back";
    }

    if ($tree->{_text}){
	push @{$doc}, ($tree->{_text}{_doc} or "Unspecified Text content");
	if ($tree->{_text}{_example}){
	    my $ex = $tree->{_text}{_example};
	    chomp $ex;
	    $ex = map {" $_"} split /\n/, $ex;
	    push @{$doc}, "Example:\n\n$ex\n";
	}
    }

    if ($tree->{_table}){
	push @{$doc}, ($tree->{_table}{_doc} or
		       "This section can contain a table ".
		       "with the following structure:" );
	push @{$doc}, "=over";
	for (my $i=0;$i < $tree->{_table}{_columns}; $i++){
	    push @{$doc}, "=item column $i";
	    push @{$doc}, ($tree->{_table}{$i}{_doc} or
			   "Unspecific Content");
	    push @{$doc}, "Example: $tree->{_table}{$i}{_example}"
		    if ($tree->{_table}{$i}{_example})
	}
	push @{$doc}, "=back";
    }
    if ($tree->{_sections}){
            if ($level > 0) {
              push @{$doc}, "The following sections are valid on level $level:";
  	      push @{$doc}, "=over";
            }
	    foreach my $section (@{$tree->{_sections}}){
		my $mandatory = ( $tree->{_mandatory} and 
				  grep {$_ eq $section} @{$tree->{_mandatory}} ) ?
				      " I<(mandatory section)>" : "";
		push @{$doc}, ($level > 0) ? 
		    "=item B<".("+" x $level)."$section>$mandatory" :
			"=head2 *** $section ***$mandatory";
		if ($tree eq $tree->{$section}) {
			push @{$doc}, "This subsection has the same syntax as its parent.";
			next;
		}
		push @{$doc}, ($tree->{$section}{_doc})
		    if $tree->{$section}{_doc};
		push @{$doc}, "The grammar of this section is I<dynamically> modified based on its name."
		    if $tree->{$section}{_dyn};
		if ($tree->{_recursive} and 
			 grep {$_ eq $section} @{$tree->{_recursive}}) {
			 push @{$doc}, "This section is I<recursive>: it can contain subsection(s) with the same syntax.";
		} 
		_genpod ($tree->{$section},$level+1,$doc);
		next unless $tree->{$section}{_dyn} and $tree->{$section}{_dyndoc};
		push @{$doc}, "Dynamical grammar changes for example instances of this section:";
		push @{$doc}, "=over";
		for my $name (sort keys %{$tree->{$section}{_dyndoc}}) {
			my $newtree = _deepcopy($tree->{$section});
			push @{$doc}, "=item B<$name>: $tree->{$section}{_dyndoc}{$name}";
			&{$tree->{$section}{_dyn}}($section, $name, $newtree);
			my @tdoc = _diffgrammars($tree->{$section}, $newtree);
			if (@tdoc) {
				push @{$doc}, @tdoc;
			} else {
				push @{$doc}, "No changes that can be automatically described.";
			}
			push @{$doc}, "(End of dynamical grammar changes for example instance C<$name>.)";
		}
		push @{$doc}, "=back";
		push @{$doc}, "(End of dynamical grammar changes for example instances of section C<$section>.)";
	    }
        push @{$doc}, "=back" if $level > 0    
    }	
    if ($tree->{_vars}) {
    	for my $var (@{$tree->{_vars}}) {
		next unless $tree->{$var}{_dyn} and $tree->{$var}{_dyndoc};
		push @{$doc}, "Dynamical grammar changes for example values of variable C<$var>:";
		push @{$doc}, "=over";
		for my $val (sort keys %{$tree->{$var}{_dyndoc}}) {
			my $newtree = _deepcopy($tree);
			push @{$doc}, "=item B<$val>: $tree->{$var}{_dyndoc}{$val}";
			&{$tree->{$var}{_dyn}}($var, $val, $newtree);
			my @tdoc = _diffgrammars($tree, $newtree);
			if (@tdoc) {
				push @{$doc}, @tdoc;
			} else {
				push @{$doc}, "No changes that can be automatically described.";
			}
			push @{$doc}, "(End of dynamical grammar changes for variable C<$var> example value C<$val>.)";
		}
		push @{$doc}, "=back";
		push @{$doc}, "(End of dynamical grammar changes for example values of variable C<$var>.)";
	}
    }
};

sub makepod($) {
    my $self = shift;
    my $tree = $self->{grammar};
    my @doc;
    _genpod($tree,0,\@doc);
    return join("\n\n", @doc)."\n";
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
        # if there's a _dyn sub, apply it
        if (defined $g->{_dyn}) {
                &{$g->{_dyn}}($key, $value, $self->{grammar});
        }
    }
    $self->{cfg}{$key} = $value;
    push @{$varlistref}, $key if ref $varlistref;

    return 1;
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

    # we work with a copy of the grammar so the _dyn subs may change it
    local $self->{grammar} = _deepcopy($self->{grammar});

    $self->_parse_file($file) or return undef;

    $self->_goto_level(0, undef) or return undef;

    # fill in the top level values from _default keywords
    $self->_fill_defaults;

    $self->_check_mandatory($self->{grammar}, $self->{cfg}, undef)
      or return undef;

    return $self->{cfg};

}

=head1 NAME

Config::Grammar::Dynamic - A grammar-based, user-friendly config parser

=head1 DESCRIPTION

Config::Grammar::Dynamic is like Config::Grammar but with some additional
features useful for building configuration grammars that are dynamic, i.e.
where the syntax changes according to configuration entries in the same file.

The following keys can be additionally specified in the grammar when using this
module:

=head2 Special Section Keys

=over 12

=item _dyn

A subroutine reference (function pointer) that will be called when
a new section of this syntax is encountered. The subroutine will get
three arguments: the syntax of the section name (string or regexp), the
actual name encountered (this will be the same as the first argument for
non-regexp sections) and a reference to the grammar tree of the section.
This subroutine can then modify the grammar tree dynamically.

=item _dyndoc

A hash reference that lists interesting names for the section that
should be documented. The keys of the hash are the names and the
values in the hash are strings that can contain an explanation
for the name. The _dyn() subroutine is then called for each of 
these names and the differences of the resulting grammar and
the original one are documented. This module can currently document
differences in the _vars list, listing new variables and removed
ones, and differences in the _sections list, listing the
new and removed sections.

=item _recursive

Array containing the list of those sub-sections that are I<recursive>, ie.
that can contain a new sub-section with the same syntax as themselves.

The same effect can be accomplished with circular references in the
grammar tree or a suitable B<_dyn> section subroutine (see below},
so this facility is included just for convenience.

=back

=head2 Special Variable Keys

=over 12

=item _dyn

A subroutine reference (function pointer) that will be called when the
variable is assigned some value in the config file. The subroutine will
get three arguments: the name of the variable, the value assigned and
a reference to the grammar tree of this section.  This subroutine can
then modify the grammar tree dynamically.

Note that no _dyn() call is made for default and inherited values of
the variable.

=item _dyndoc

A hash reference that lists interesting values for the variable that
should be documented. The keys of the hash are the values and the
values in the hash are strings that can contain an explanation
for the value. The _dyn() subroutine is then called for each of 
these values and the differences of the resulting grammar and
the original one are documented. This module can currently document
differences in the _vars list, listing new variables and removed
ones, and differences in the _sections list, listing the
new and removed sections.

=back

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
