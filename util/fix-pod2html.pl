#!/usr/bin/perl -w

use strict;
use HTML::Parser;

# fix pod2html output:
# v1.0: defer </dd> and </dt> tags until
# the next <dd>, <dt> or </dl>

# v1.1: don't nest any <a> elements; 
# end one before beginning another

# v1.2: insert <dd> tags if <dl> occurs
# inside <dt>

# v1.3: <a> anchors must not start with a digit;
# insert a letter "N" at the start if they do

# v1.4: insert the "N" letter into <a href="#xxx"> too.

my $p = HTML::Parser->new(api_version => 3);
$p->handler(start => \&startsub, 'tagname, text');
$p->handler(end => \&endsub, 'tagname, text');
$p->handler(default => sub { print shift() }, 'text');
$p->parse_file(shift||"-") or die("parse: $!");

my @stack;
my $a=0;

sub startsub {
        my $tag = shift;
        my $text = shift;
        if ($tag eq "dl") {
		if (@stack and $stack[0] eq "dt") {
			$stack[0] = "dd";
			print "</dt><dd>";
		}
                unshift @stack, 0;
        }
        if (($tag eq "dt" or $tag eq "dd") and $stack[0]) {
                print "</$stack[0]>";
                $stack[0] = 0;
        }
	if ($tag eq "a") {
		if ($a) {
			print "</a>";
		} else {
			$a++;
		}
		$text =~ s/(name="|href="#)(\d)/$1N$2/;
	}
        print $text;
}
                

sub endsub {
        my $tag = shift;
        my $text = shift;
        if ($tag eq "dl") {
                print "</$stack[0]>" if $stack[0];
                shift @stack;
        }
	if ($tag eq "a") {
		if ($a) {
			print "</a>";
			$a--;
		}
	} elsif ($tag eq "dd" or $tag eq "dt") {
                $stack[0] = $tag;
        } else {
                print $text;
        }
}
