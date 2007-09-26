package Config::Grammar::Document;

# This is a helper class for Config::Grammar implementing the logic
# of its documentation-generating methods.
# 
# This code is placed here instead of Config::Grammar in order to make
# the main module leaner. These methods are only used in special cases.
# Note that the installation of this module is optional: if you don't install
# it, the make...() methods just won't work.

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
		_genpod($tree->{$section},$level+1,$doc);
	    }
        push @{$doc}, "=back" if $level > 0    
    }	
};

sub makepod($) {
    my $self = shift;
    my $tree = $self->{grammar};
    my @doc;
    _genpod($tree,0,\@doc);
    return join("\n\n", @doc)."\n";
}

sub _gentmpl($$$@);
sub _gentmpl($$$@){
    my $tree = shift;
    my $complete = shift;
    my $level = shift;
    my $doc = shift;
    my @start = @_;
    if (scalar @start ) {
	my $section = shift @start;
	my $secex ='';
	my $prefix = '';
	$prefix = "# " unless $tree->{_mandatory} and 
		    grep {$_ eq $section} @{$tree->{_mandatory}};
	if ($tree->{$section}{_example}) {
	    $secex = " #  ( ex. $tree->{$section}{_example} )";
	}

	if($complete) {
	    push @{$doc}, $prefix.
		(($level > 0) ? ("+" x $level)."$section" : "*** $section ***").$secex;
	} else {
	    my $minsection=$section =~ m|^/| ? "" : $section;
	    push @{$doc},(($level > 0) ? ("+" x $level)."$minsection" : "*** $minsection ***");
	}
	
	my $match;
	foreach my $s (@{$tree->{_sections}}){
	    if ($s =~ m|^/.+/$| and $section =~ /$s/ or $s eq $section) {
		_gentmpl ($tree->{$s},$complete,$level+1,$doc,@start)
		    unless $tree eq $tree->{$s};
		$match = 1;
	    }
	}
        push @{$doc}, "# Section $section is not a valid choice"
	    unless $match;
    } else {
	if ($tree->{_vars}){
	    foreach my $var (@{$tree->{_vars}}){
		my $mandatory= ($tree->{_mandatory} and 
		    grep {$_ eq $var} @{$tree->{_mandatory}});
		if($complete) {
		    push @{$doc}, "# $var = ". 
			($tree->{$var}{_example} || ' * no example *');
		    push @{$doc}, "$var=" if $mandatory;
		} else {
			push @{$doc}, ($mandatory?"":"# ")."$var=";
		    next unless $tree->{_mandatory} and 
			grep {$_ eq $var} @{$tree->{_mandatory}};
		}
	    }
	}

	if ($tree->{_text} and $complete){
	    if ($tree->{_text}{_example}){
		my $ex = $tree->{_text}{_example};
		chomp $ex;
		$ex = map {"# $_"} split /\n/, $ex;
		push @{$doc}, "$ex\n";
	    }
	}
	if ($tree->{_table} and $complete){
	    my $table = "# table\n#";
	    for (my $i=0;$i < $tree->{_table}{_columns}; $i++){
		$table .= ' "'.($tree->{_table}{$i}{_example} || "C$i").'"';
	    }
 	    push @{$doc}, $table;
	}
	if ($tree->{_sections}){
	    foreach my $section (@{$tree->{_sections}}){
		my $opt = "";
		unless( $tree->{_mandatory} and 
			grep {$_ eq $section} @{$tree->{_mandatory}} ) {
		    $opt="\n# optional section\n" if $complete;
		}
		my $prefix = '';
		$prefix = "# " unless $tree->{_mandatory} and 
		    grep {$_ eq $section} @{$tree->{_mandatory}};
		my $secex ="";
		if ($section =~ m|^/.+/$| && $tree->{$section}{_example}) {
		    $secex = " #  ( ex. $tree->{$section}{_example} )"
			if $complete;
		}
		if($complete) {
		    push @{$doc}, $prefix.
			(($level > 0) ? ("+" x $level)."$section" : "*** $section ***").
			    $secex;
		} else {
		    my $minsection=$section =~ m|^/| ? "" : $section;
		    push @{$doc},(($level > 0) ? ("+" x $level)."$minsection" : "*** $minsection ***");
		}
		_gentmpl ($tree->{$section},$complete,$level+1,$doc,@start)
		    unless $tree eq $tree->{$section};
	    }
	}
    }
};

sub maketmpl ($@) {
    my $self = shift;
    my @start = @_;
    my $tree = $self->{grammar};
    my @tmpl;
    _gentmpl $tree,1,0,\@tmpl,@start;
    return join("\n", @tmpl)."\n";
}

sub makemintmpl ($@) {
    my $self = shift;
    my @start = @_;
    my $tree = $self->{grammar};
    my @tmpl;
    _gentmpl $tree,0,0,\@tmpl,@start;
    return join("\n", @tmpl)."\n";
}

1;
