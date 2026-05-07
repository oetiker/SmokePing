package Smokeping::Request;

=head1 NAME

Smokeping::Request - lightweight CGI request abstraction

=head1 DESCRIPTION

A minimal replacement for CGI.pm providing only the functionality
SmokePing actually needs: parameter parsing, HTTP header generation,
and HTML form helpers. This avoids depending on CGI.pm which has been
removed from Perl core.

=head1 SYNOPSIS

    use Smokeping::Request;
    my $q = Smokeping::Request->new;
    my $val = $q->param('target');
    print $q->header(-type => 'text/html', -status => '200 OK');

=cut

use strict;
use warnings;
use POSIX qw(strftime);

sub new {
    my $class = shift;
    my $self = bless { params => {} }, $class;
    my $input = shift;

    if (defined $input && length $input) {
        $self->_parse_query($input);
    } elsif ($ENV{REQUEST_METHOD}) {
        my $qs = $ENV{QUERY_STRING} || '';
        $self->_parse_query($qs);
        if ($ENV{REQUEST_METHOD} eq 'POST') {
            my $len = $ENV{CONTENT_LENGTH} || 0;
            my $type = $ENV{CONTENT_TYPE} || '';
            if ($len > 0) {
                my $body = '';
                while ($len > 0) {
                    my $n = read(STDIN, my $buf, $len);
                    last unless $n;
                    $body .= $buf;
                    $len -= $n;
                }
                if ($type =~ m{^multipart/form-data;\s*boundary=(.+)$}i) {
                    _parse_multipart($1, $body, $self->{params});
                } else {
                    $self->_parse_query($body);
                }
            }
        }
    }
    return $self;
}

sub _parse_query {
    my ($self, $qs) = @_;
    return unless defined $qs && length $qs;
    for my $pair (split /[&;]/, $qs) {
        my ($key, $val) = split /=/, $pair, 2;
        next unless defined $key;
        $key = _uri_decode($key);
        $val = defined $val ? _uri_decode($val) : '';
        if (exists $self->{params}{$key}) {
            if (ref $self->{params}{$key}) {
                push @{$self->{params}{$key}}, $val;
            } else {
                $self->{params}{$key} = [$self->{params}{$key}, $val];
            }
        } else {
            $self->{params}{$key} = $val;
        }
    }
}

sub _uri_decode {
    my $str = shift;
    return '' unless defined $str;
    $str =~ tr/+/ /;
    $str =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
    return $str;
}

sub _parse_multipart {
    my ($boundary, $body, $params) = @_;
    $boundary =~ s/^\s+//; $boundary =~ s/\s+$//;
    $boundary = quotemeta($boundary);
    for my $part (split /--$boundary/, $body) {
        next unless $part =~ /\S/;
        last if $part =~ /^--/;
        $part =~ s/^\r\n//;
        my ($head, $content) = split /\r\n\r\n/, $part, 2;
        next unless defined $head && defined $content;
        $content =~ s/\r\n$//;
        if ($head =~ /name="([^"]*)"/){
            my $name = $1;
            push @{$params->{$name}}, $content;
        }
    }
}

sub _expires_to_date {
    my $expires = shift;
    if ($expires =~ /^([+-]?\d+)([smhdMy]?)$/) {
        my ($num, $unit) = ($1, $2 || 's');
        my %mult = (s => 1, m => 60, h => 3600, d => 86400, M => 2592000, y => 31536000);
        my $offset = $num * ($mult{$unit} || 1);
        my $time = time() + $offset;
        return strftime("%a, %d %b %Y %H:%M:%S GMT", gmtime($time));
    }
    if ($expires eq 'now') {
        return strftime("%a, %d %b %Y %H:%M:%S GMT", gmtime(time()));
    }
    return $expires;
}

=head2 param

    my $val  = $q->param('name');
    my @vals = $q->param('name');      # multi-value
    my @keys = $q->param();            # all param names
    $q->param('name', 'new_value');    # set value
    $q->param(-name => 'key');         # CGI.pm compat

=cut

sub param {
    my $self = shift;

    # no args: return all param names
    return keys %{$self->{params}} unless @_;

    # handle CGI.pm named-parameter style: param(-name => 'foo')
    if (@_ == 2 && $_[0] eq '-name') {
        my $key = $_[1];
        return unless exists $self->{params}{$key};
        my $v = $self->{params}{$key};
        return ref $v ? @$v : $v;
    }

    my $key = shift;

    # setter: param('key', 'value')
    if (@_) {
        $self->{params}{$key} = $_[0];
        return $_[0];
    }

    # getter
    return unless exists $self->{params}{$key};
    my $v = $self->{params}{$key};
    return wantarray && ref $v ? @$v : ref $v ? $v->[0] : $v;
}

=head2 script_name

Returns C<$ENV{SCRIPT_NAME}>.

=cut

sub script_name {
    return $ENV{SCRIPT_NAME} || '';
}

=head2 header

    print $q->header(-type => 'text/html', -status => '200 OK');

Generates CGI response headers. Supports C<-type>, C<-status>,
C<-expires>, C<-charset>, C<-Content_length>, and C<-cookie>.

=cut

sub header {
    my $self = shift;
    my %args;
    if (@_ == 1 && ref $_[0] eq 'HASH') {
        %args = %{$_[0]};
    } else {
        %args = @_;
    }

    my $type    = $args{-type}    || 'text/html';
    my $charset = $args{-charset} || '';
    my $status  = $args{-status};
    my $expires = $args{-expires};
    my $length  = $args{-Content_length};
    my $cookie  = $args{-cookie};

    my @headers;
    if ($status) {
        push @headers, "Status: $status";
    }

    my $ct = $type;
    $ct .= "; charset=$charset" if $charset;
    push @headers, "Content-Type: $ct";

    if (defined $length) {
        push @headers, "Content-Length: $length";
    }
    if ($expires) {
        push @headers, "Expires: " . _expires_to_date($expires);
    }
    if ($cookie) {
        my @cookies = ref $cookie eq 'ARRAY' ? @$cookie : ($cookie);
        for my $c (@cookies) {
            push @headers, "Set-Cookie: $c";
        }
    }

    return join("\r\n", @headers) . "\r\n\r\n";
}

=head2 start_form, end_form, textfield, hidden, submit

HTML form helpers compatible with CGI.pm.

=cut

sub start_form {
    my $self = shift;
    my %args = @_;
    my $method  = $args{-method}  || 'GET';
    my $action  = $args{-action}  || '';
    my $enctype = $args{-enctype} || '';
    my $name    = $args{-name}    || '';
    my $id      = $args{-id}      || '';

    my $html = '<form method="' . _escape($method) . '"';
    $html .= ' action="'  . _escape($action)  . '"' if $action;
    $html .= ' enctype="' . _escape($enctype) . '"' if $enctype;
    $html .= ' name="'    . _escape($name)    . '"' if $name;
    $html .= ' id="'      . _escape($id)      . '"' if $id;
    $html .= '>';
    return $html;
}

sub end_form {
    return '</form>';
}

sub textfield {
    my $self = shift;
    my %args = @_;
    my $name    = $args{-name}    || '';
    my $default = $args{-default} // '';
    my $size    = $args{-size}    || '';
    my $id      = $args{-id}     || '';

    my $html = '<input type="text" name="' . _escape($name) . '"'
             . ' value="' . _escape($default) . '"';
    $html .= ' size="'        . _escape($size) . '"'               if $size;
    $html .= ' id="'          . _escape($id) . '"'                 if $id;
    $html .= ' onchange="'    . _escape($args{-onChange}) . '"'    if $args{-onChange};
    $html .= ' placeholder="' . _escape($args{-placeholder}) . '"' if $args{-placeholder};
    $html .= ' />';
    return $html;
}

sub popup_menu {
    my $self = shift;
    my %args = @_;
    my $name     = $args{-name}     || '';
    my $id       = $args{-id}       || '';
    my $values   = $args{-values}   || [];
    my $labels   = $args{-labels}   || {};
    my $default  = $args{-default}  // '';
    my $onchange = $args{-onChange}  || '';

    my $html = '<select name="' . _escape($name) . '"';
    $html .= ' id="'       . _escape($id) . '"'       if $id;
    $html .= ' onchange="' . _escape($onchange) . '"' if $onchange;
    $html .= '>';
    $html .= "\n";
    for my $val (@$values) {
        my $label = exists $labels->{$val} ? $labels->{$val} : $val;
        my $sel   = defined $default && "$val" eq "$default" ? ' selected' : '';
        $html .= '<option value="' . _escape($val) . '"' . $sel . '>'
               . _escape($label) . '</option>' . "\n";
    }
    $html .= '</select>';
    return $html;
}

sub hidden {
    my $self = shift;
    my %args = @_;
    my $name    = $args{-name}    || '';
    my $default = $args{-default} // $self->param($name) // '';
    my $id      = $args{-id}     || '';

    my $html = '<input type="hidden" name="' . _escape($name) . '"'
             . ' value="' . _escape($default) . '"';
    $html .= ' id="' . _escape($id) . '"' if $id;
    $html .= ' />';
    return $html;
}

sub submit {
    my $self = shift;
    my %args = @_;
    my $name = $args{-name} || '';

    return '<input type="submit" value="' . _escape($name) . '" />';
}

=head2 escapeHTML

    my $safe = Smokeping::Request::escapeHTML($string);

Class method / exportable function for HTML escaping.

=cut

sub escapeHTML {
    shift if @_ > 1 && (ref $_[0] || (defined $_[0] && $_[0] eq __PACKAGE__));
    my $str = shift;
    return '' unless defined $str;
    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/"/&quot;/g;
    $str =~ s/'/&#39;/g;
    return $str;
}

# internal HTML attribute escaper
sub _escape { escapeHTML(@_) }

1;

__END__

=head1 COPYRIGHT

Copyright (c) 2024 by OETIKER+PARTNER AG. All rights reserved.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

=head1 AUTHOR

Tobias Oetiker E<lt>tobi@oetiker.chE<gt>

=cut
