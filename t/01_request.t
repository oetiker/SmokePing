#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::RealBin/../lib";
use Test::More;

use_ok('Smokeping::Request');

# ====================================================================
# new() - constructor
# ====================================================================

{
    my $q = Smokeping::Request->new('foo=bar&baz=qux');
    isa_ok($q, 'Smokeping::Request', 'new with query string');
    is($q->param('foo'), 'bar', 'new: parsed first param');
    is($q->param('baz'), 'qux', 'new: parsed second param');
}

{
    my $q = Smokeping::Request->new('');
    isa_ok($q, 'Smokeping::Request', 'new with empty string');
    is_deeply([sort $q->param()], [], 'new empty: no params');
}

{
    local $ENV{REQUEST_METHOD} = 'GET';
    local $ENV{QUERY_STRING}   = 'x=1&y=2';
    my $q = Smokeping::Request->new;
    is($q->param('x'), '1', 'new from ENV QUERY_STRING: x');
    is($q->param('y'), '2', 'new from ENV QUERY_STRING: y');
}

{
    local $ENV{REQUEST_METHOD} = undef;
    local $ENV{QUERY_STRING}   = undef;
    my $q = Smokeping::Request->new;
    isa_ok($q, 'Smokeping::Request', 'new with no input and no ENV');
    is_deeply([sort $q->param()], [], 'new no input: no params');
}

# semicolons as separators
{
    my $q = Smokeping::Request->new('a=1;b=2');
    is($q->param('a'), '1', 'semicolon separator: a');
    is($q->param('b'), '2', 'semicolon separator: b');
}

# ====================================================================
# _uri_decode() - private but testable
# ====================================================================

{
    is(Smokeping::Request::_uri_decode('hello+world'), 'hello world',
       '_uri_decode: plus to space');
    is(Smokeping::Request::_uri_decode('%2F%3A'), '/:',
       '_uri_decode: hex encoding');
    is(Smokeping::Request::_uri_decode('%2f%3a'), '/:',
       '_uri_decode: lowercase hex');
    is(Smokeping::Request::_uri_decode(''), '',
       '_uri_decode: empty string');
    is(Smokeping::Request::_uri_decode(undef), '',
       '_uri_decode: undef');
    is(Smokeping::Request::_uri_decode('plain'), 'plain',
       '_uri_decode: no encoding needed');
    is(Smokeping::Request::_uri_decode('100%25'), '100%',
       '_uri_decode: percent sign itself');
}

# ====================================================================
# param() - getter / setter / multi-value / all keys
# ====================================================================

{
    my $q = Smokeping::Request->new('color=red&color=blue&color=green&size=large');

    # single value in scalar context
    is($q->param('size'), 'large', 'param: single value');

    # multi-value in list context
    my @colors = $q->param('color');
    is_deeply(\@colors, ['red', 'blue', 'green'],
              'param: multi-value in list context');

    # multi-value in scalar context returns first
    my $first = $q->param('color');
    is($first, 'red', 'param: multi-value scalar context returns first');

    # all parameter names
    my @keys = sort $q->param();
    is_deeply(\@keys, ['color', 'size'], 'param: all keys');

    # nonexistent param
    is($q->param('nope'), undef, 'param: nonexistent returns undef');

    # setter
    my $ret = $q->param('size', 'small');
    is($ret, 'small', 'param setter: returns new value');
    is($q->param('size'), 'small', 'param setter: value updated');

    # setter for new param
    $q->param('shape', 'round');
    is($q->param('shape'), 'round', 'param setter: create new param');

    # -name style (CGI.pm compat)
    is($q->param(-name => 'size'), 'small', 'param -name style: scalar');
    my @c2 = $q->param(-name => 'color');
    is_deeply(\@c2, ['red', 'blue', 'green'],
              'param -name style: multi-value');

    # -name for nonexistent
    is($q->param(-name => 'missing'), undef,
       'param -name style: nonexistent');
}

# ====================================================================
# escapeHTML() - all 5 entities, undef, empty, calling conventions
# ====================================================================

{
    is(Smokeping::Request::escapeHTML('&'), '&amp;',   'escapeHTML: ampersand');
    is(Smokeping::Request::escapeHTML('<'), '&lt;',    'escapeHTML: less than');
    is(Smokeping::Request::escapeHTML('>'), '&gt;',    'escapeHTML: greater than');
    is(Smokeping::Request::escapeHTML('"'), '&quot;',  'escapeHTML: double quote');
    is(Smokeping::Request::escapeHTML("'"), '&#39;',   'escapeHTML: single quote');

    is(Smokeping::Request::escapeHTML('<b>"Tom & Jerry\'s"</b>'),
       '&lt;b&gt;&quot;Tom &amp; Jerry&#39;s&quot;&lt;/b&gt;',
       'escapeHTML: combined entities');

    is(Smokeping::Request::escapeHTML(undef), '', 'escapeHTML: undef returns empty');
    is(Smokeping::Request::escapeHTML(''),    '', 'escapeHTML: empty returns empty');

    # called as class method
    is(Smokeping::Request->escapeHTML('&'), '&amp;',
       'escapeHTML: class method call');

    # called on instance
    my $q = Smokeping::Request->new;
    is($q->escapeHTML('<'), '&lt;', 'escapeHTML: instance method call');
}

# ====================================================================
# script_name() - from ENV
# ====================================================================

{
    local $ENV{SCRIPT_NAME} = '/cgi-bin/smokeping.cgi';
    my $q = Smokeping::Request->new;
    is($q->script_name(), '/cgi-bin/smokeping.cgi',
       'script_name: from ENV');
}

{
    local $ENV{SCRIPT_NAME} = undef;
    my $q = Smokeping::Request->new;
    is($q->script_name(), '', 'script_name: missing ENV returns empty');
}

# ====================================================================
# header() - type, charset, status, expires, content_length, cookies
# ====================================================================

{
    my $q = Smokeping::Request->new;

    # default header
    my $h = $q->header();
    like($h, qr/Content-Type: text\/html\r\n/, 'header: default type');
    like($h, qr/\r\n\r\n$/, 'header: ends with blank line');

    # custom type
    $h = $q->header(-type => 'image/png');
    like($h, qr/Content-Type: image\/png/, 'header: custom type');

    # charset
    $h = $q->header(-type => 'text/html', -charset => 'utf-8');
    like($h, qr/Content-Type: text\/html; charset=utf-8/,
         'header: charset appended');

    # status
    $h = $q->header(-status => '404 Not Found');
    like($h, qr/Status: 404 Not Found/, 'header: status');

    # expires
    $h = $q->header(-expires => 'Thu, 01 Jan 2099 00:00:00 GMT');
    like($h, qr/Expires: Thu, 01 Jan 2099/, 'header: expires');

    # content length
    $h = $q->header(-Content_length => 42);
    like($h, qr/Content-Length: 42/, 'header: content length');

    # single cookie
    $h = $q->header(-cookie => 'sid=abc123');
    like($h, qr/Set-Cookie: sid=abc123/, 'header: single cookie');

    # multiple cookies
    $h = $q->header(-cookie => ['sid=abc', 'lang=en']);
    like($h, qr/Set-Cookie: sid=abc/, 'header: multi cookie 1');
    like($h, qr/Set-Cookie: lang=en/, 'header: multi cookie 2');

    # hash ref argument style
    $h = $q->header({-type => 'application/json', -status => '200 OK'});
    like($h, qr/Content-Type: application\/json/, 'header: hashref type');
    like($h, qr/Status: 200 OK/, 'header: hashref status');
}

# ====================================================================
# start_form() - method, action, name, id, enctype
# ====================================================================

{
    my $q = Smokeping::Request->new;

    # defaults
    my $f = $q->start_form();
    like($f, qr/^<form method="GET">$/, 'start_form: default GET');

    # POST with action
    $f = $q->start_form(-method => 'POST', -action => '/submit');
    like($f, qr/method="POST"/, 'start_form: POST method');
    like($f, qr/action="\/submit"/, 'start_form: action');

    # name and id
    $f = $q->start_form(-method => 'POST', -name => 'myform', -id => 'f1');
    like($f, qr/name="myform"/, 'start_form: name');
    like($f, qr/id="f1"/, 'start_form: id');

    # enctype
    $f = $q->start_form(-method => 'POST',
                         -enctype => 'multipart/form-data');
    like($f, qr/enctype="multipart\/form-data"/, 'start_form: enctype');

    # HTML escaping in attributes
    $f = $q->start_form(-method => 'POST', -action => '/a&b');
    like($f, qr/action="\/a&amp;b"/, 'start_form: escapes action');
}

# ====================================================================
# end_form()
# ====================================================================

{
    is(Smokeping::Request->end_form(), '</form>', 'end_form: returns tag');
    my $q = Smokeping::Request->new;
    is($q->end_form(), '</form>', 'end_form: instance call');
}

# ====================================================================
# textfield() - name, default, size, id, onChange, placeholder
# ====================================================================

{
    my $q = Smokeping::Request->new;

    my $t = $q->textfield(-name => 'user', -default => 'alice');
    like($t, qr/type="text"/, 'textfield: type text');
    like($t, qr/name="user"/, 'textfield: name');
    like($t, qr/value="alice"/, 'textfield: default value');
    like($t, qr/\/>$/, 'textfield: self-closing');

    # size
    $t = $q->textfield(-name => 'q', -default => '', -size => 40);
    like($t, qr/size="40"/, 'textfield: size');

    # id
    $t = $q->textfield(-name => 'q', -id => 'search');
    like($t, qr/id="search"/, 'textfield: id');

    # onChange
    $t = $q->textfield(-name => 'q', -onChange => 'doStuff()');
    like($t, qr/onchange="doStuff\(\)"/, 'textfield: onChange');

    # placeholder
    $t = $q->textfield(-name => 'q', -placeholder => 'type here');
    like($t, qr/placeholder="type here"/, 'textfield: placeholder');

    # escaping in value
    $t = $q->textfield(-name => 'x', -default => '<"test">');
    like($t, qr/value="&lt;&quot;test&quot;&gt;"/, 'textfield: escapes value');

    # default of undef / 0
    $t = $q->textfield(-name => 'x');
    like($t, qr/value=""/, 'textfield: no default gives empty value');

    $t = $q->textfield(-name => 'x', -default => 0);
    like($t, qr/value="0"/, 'textfield: default 0 preserved');
}

# ====================================================================
# hidden() - name, default, id, falls back to param value
# ====================================================================

{
    my $q = Smokeping::Request->new('secret=fromquery');

    # explicit default
    my $h = $q->hidden(-name => 'token', -default => 'abc123');
    like($h, qr/type="hidden"/, 'hidden: type');
    like($h, qr/name="token"/, 'hidden: name');
    like($h, qr/value="abc123"/, 'hidden: explicit default');

    # id attribute
    $h = $q->hidden(-name => 'token', -default => 'x', -id => 'hid1');
    like($h, qr/id="hid1"/, 'hidden: id');

    # fallback to param value when no default given
    $h = $q->hidden(-name => 'secret');
    like($h, qr/value="fromquery"/, 'hidden: falls back to param value');

    # no param and no default gives empty
    $h = $q->hidden(-name => 'nonexistent');
    like($h, qr/value=""/, 'hidden: no default no param gives empty');

    # escaping
    $h = $q->hidden(-name => 'x', -default => '<>&"\'');
    like($h, qr/value="&lt;&gt;&amp;&quot;&#39;"/, 'hidden: escapes value');
}

# ====================================================================
# submit() - name
# ====================================================================

{
    my $q = Smokeping::Request->new;

    my $s = $q->submit(-name => 'Go');
    like($s, qr/type="submit"/, 'submit: type');
    like($s, qr/value="Go"/, 'submit: name as value');
    like($s, qr/\/>$/, 'submit: self-closing');

    # default empty name
    $s = $q->submit();
    like($s, qr/value=""/, 'submit: no name gives empty value');

    # escaping
    $s = $q->submit(-name => 'A&B');
    like($s, qr/value="A&amp;B"/, 'submit: escapes name');
}

# ====================================================================
# popup_menu() - values, labels, default, onChange, id
# ====================================================================

{
    my $q = Smokeping::Request->new;

    my $m = $q->popup_menu(
        -name   => 'fruit',
        -values => ['apple', 'banana', 'cherry'],
    );
    like($m, qr/^<select name="fruit">/, 'popup_menu: select tag with name');
    like($m, qr/<option value="apple">apple<\/option>/,
         'popup_menu: option without label');
    like($m, qr/<option value="banana">banana<\/option>/,
         'popup_menu: second option');
    like($m, qr/<\/select>$/, 'popup_menu: closes select');

    # with labels
    $m = $q->popup_menu(
        -name   => 'fruit',
        -values => ['a', 'b'],
        -labels => { a => 'Apple', b => 'Banana' },
    );
    like($m, qr/<option value="a">Apple<\/option>/, 'popup_menu: label mapping');
    like($m, qr/<option value="b">Banana<\/option>/, 'popup_menu: label mapping 2');

    # default selection
    $m = $q->popup_menu(
        -name    => 'fruit',
        -values  => ['a', 'b', 'c'],
        -default => 'b',
    );
    unlike($m, qr/<option value="a"[^>]*selected/, 'popup_menu: a not selected');
    like($m, qr/<option value="b" selected>/, 'popup_menu: b selected');
    unlike($m, qr/<option value="c"[^>]*selected/, 'popup_menu: c not selected');

    # onChange and id
    $m = $q->popup_menu(
        -name     => 'x',
        -values   => ['1'],
        -onChange  => 'update()',
        -id       => 'sel1',
    );
    like($m, qr/onchange="update\(\)"/, 'popup_menu: onChange');
    like($m, qr/id="sel1"/, 'popup_menu: id');

    # escaping in values and labels
    $m = $q->popup_menu(
        -name   => 'x',
        -values => ['<a>'],
        -labels => { '<a>' => '"quoted"' },
    );
    like($m, qr/value="&lt;a&gt;"/, 'popup_menu: escapes value');
    like($m, qr/>&quot;quoted&quot;<\/option>/, 'popup_menu: escapes label');

    # empty values
    $m = $q->popup_menu(-name => 'x', -values => []);
    like($m, qr/^<select name="x">\n<\/select>$/, 'popup_menu: empty values');
}

# ====================================================================
# Edge cases: query parsing
# ====================================================================

{
    # key with no value
    my $q = Smokeping::Request->new('flag');
    is($q->param('flag'), '', 'parse: key with no value gives empty string');
}

{
    # encoded key and value
    my $q = Smokeping::Request->new('na%20me=va%20lue');
    is($q->param('na me'), 'va lue', 'parse: encoded key and value');
}

{
    # multi-value accumulation (3+ values)
    my $q = Smokeping::Request->new('k=1&k=2&k=3');
    my @v = $q->param('k');
    is_deeply(\@v, [1, 2, 3], 'parse: three values accumulate correctly');
}

done_testing;
