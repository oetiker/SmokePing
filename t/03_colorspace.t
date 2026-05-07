#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::RealBin/../lib";
use Test::More;

use_ok('Smokeping::Colorspace');

# Helper: compare floats with tolerance
sub near {
    my ($got, $expected, $tol, $desc) = @_;
    $tol //= 1e-4;
    ok(abs($got - $expected) < $tol, $desc // "near($got, $expected)");
}

# --- web_to_rgb ---

{
    my @rgb = Smokeping::Colorspace::web_to_rgb('#000000');
    is_deeply(\@rgb, [0, 0, 0], 'web_to_rgb: black');
}

{
    my @rgb = Smokeping::Colorspace::web_to_rgb('#ffffff');
    is_deeply(\@rgb, [1, 1, 1], 'web_to_rgb: white');
}

{
    my @rgb = Smokeping::Colorspace::web_to_rgb('#ff0000');
    is_deeply(\@rgb, [1, 0, 0], 'web_to_rgb: red');
}

{
    my @rgb = Smokeping::Colorspace::web_to_rgb('#00ff00');
    is_deeply(\@rgb, [0, 1, 0], 'web_to_rgb: green');
}

{
    my @rgb = Smokeping::Colorspace::web_to_rgb('#0000ff');
    is_deeply(\@rgb, [0, 0, 1], 'web_to_rgb: blue');
}

{
    my @rgb = Smokeping::Colorspace::web_to_rgb('#336699');
    near($rgb[0], 0x33/255, 1e-4, 'web_to_rgb: mixed R');
    near($rgb[1], 0x66/255, 1e-4, 'web_to_rgb: mixed G');
    near($rgb[2], 0x99/255, 1e-4, 'web_to_rgb: mixed B');
}

# without leading #
{
    my @rgb = Smokeping::Colorspace::web_to_rgb('abcdef');
    near($rgb[0], 0xab/255, 1e-4, 'web_to_rgb: no hash R');
    near($rgb[1], 0xcd/255, 1e-4, 'web_to_rgb: no hash G');
    near($rgb[2], 0xef/255, 1e-4, 'web_to_rgb: no hash B');
}

# --- rgb_to_web ---

is(Smokeping::Colorspace::rgb_to_web(0, 0, 0), '#000000', 'rgb_to_web: black');
is(Smokeping::Colorspace::rgb_to_web(1, 1, 1), '#ffffff', 'rgb_to_web: white');
is(Smokeping::Colorspace::rgb_to_web(1, 0, 0), '#ff0000', 'rgb_to_web: red');

# round-trip: web -> rgb -> web
for my $color ('#000000', '#ffffff', '#ff0000', '#00ff00', '#0000ff', '#336699', '#abcdef') {
    my @rgb = Smokeping::Colorspace::web_to_rgb($color);
    my $back = Smokeping::Colorspace::rgb_to_web(@rgb);
    is($back, $color, "rgb_to_web round-trip: $color");
}

# --- rgb_to_hsl ---

{
    # Red: hue=0, sat=1, lum=0.5
    my ($h, $s, $l) = Smokeping::Colorspace::rgb_to_hsl(1, 0, 0);
    near($h, 0,   1e-4, 'rgb_to_hsl: red H=0');
    near($s, 1,   1e-4, 'rgb_to_hsl: red S=1');
    near($l, 0.5, 1e-4, 'rgb_to_hsl: red L=0.5');
}

{
    # Green: hue=120deg=1/3, sat=1, lum=0.5
    my ($h, $s, $l) = Smokeping::Colorspace::rgb_to_hsl(0, 1, 0);
    near($h, 1/3, 1e-4, 'rgb_to_hsl: green H=1/3');
    near($s, 1,   1e-4, 'rgb_to_hsl: green S=1');
    near($l, 0.5, 1e-4, 'rgb_to_hsl: green L=0.5');
}

{
    # Blue: hue=240deg=2/3, sat=1, lum=0.5
    my ($h, $s, $l) = Smokeping::Colorspace::rgb_to_hsl(0, 0, 1);
    near($h, 2/3, 1e-4, 'rgb_to_hsl: blue H=2/3');
    near($s, 1,   1e-4, 'rgb_to_hsl: blue S=1');
    near($l, 0.5, 1e-4, 'rgb_to_hsl: blue L=0.5');
}

{
    # White: hue=0, sat=0, lum=1
    my ($h, $s, $l) = Smokeping::Colorspace::rgb_to_hsl(1, 1, 1);
    near($h, 0, 1e-4, 'rgb_to_hsl: white H=0');
    near($s, 0, 1e-4, 'rgb_to_hsl: white S=0');
    near($l, 1, 1e-4, 'rgb_to_hsl: white L=1');
}

{
    # Black: hue=0, sat=0, lum=0
    my ($h, $s, $l) = Smokeping::Colorspace::rgb_to_hsl(0, 0, 0);
    near($h, 0, 1e-4, 'rgb_to_hsl: black H=0');
    near($s, 0, 1e-4, 'rgb_to_hsl: black S=0');
    near($l, 0, 1e-4, 'rgb_to_hsl: black L=0');
}

{
    # 50% grey: hue=0, sat=0, lum=0.5
    my ($h, $s, $l) = Smokeping::Colorspace::rgb_to_hsl(0.5, 0.5, 0.5);
    near($h, 0,   1e-4, 'rgb_to_hsl: grey H=0');
    near($s, 0,   1e-4, 'rgb_to_hsl: grey S=0');
    near($l, 0.5, 1e-4, 'rgb_to_hsl: grey L=0.5');
}

# --- hsl_to_rgb ---

{
    # Red
    my @rgb = Smokeping::Colorspace::hsl_to_rgb(0, 1, 0.5);
    near($rgb[0], 1, 1e-4, 'hsl_to_rgb: red R');
    near($rgb[1], 0, 1e-4, 'hsl_to_rgb: red G');
    near($rgb[2], 0, 1e-4, 'hsl_to_rgb: red B');
}

{
    # Green
    my @rgb = Smokeping::Colorspace::hsl_to_rgb(1/3, 1, 0.5);
    near($rgb[0], 0, 1e-4, 'hsl_to_rgb: green R');
    near($rgb[1], 1, 1e-4, 'hsl_to_rgb: green G');
    near($rgb[2], 0, 1e-4, 'hsl_to_rgb: green B');
}

{
    # Blue
    my @rgb = Smokeping::Colorspace::hsl_to_rgb(2/3, 1, 0.5);
    near($rgb[0], 0, 1e-4, 'hsl_to_rgb: blue R');
    near($rgb[1], 0, 1e-4, 'hsl_to_rgb: blue G');
    near($rgb[2], 1, 1e-4, 'hsl_to_rgb: blue B');
}

{
    # Achromatic (grey)
    my @rgb = Smokeping::Colorspace::hsl_to_rgb(0, 0, 0.5);
    near($rgb[0], 0.5, 1e-4, 'hsl_to_rgb: grey R');
    near($rgb[1], 0.5, 1e-4, 'hsl_to_rgb: grey G');
    near($rgb[2], 0.5, 1e-4, 'hsl_to_rgb: grey B');
}

# round-trip: rgb -> hsl -> rgb
for my $case (
    [1, 0, 0, 'red'],
    [0, 1, 0, 'green'],
    [0, 0, 1, 'blue'],
    [1, 1, 1, 'white'],
    [0, 0, 0, 'black'],
    [0.5, 0.5, 0.5, 'grey'],
    [0.2, 0.4, 0.6, 'mixed'],
) {
    my ($r, $g, $b, $name) = @$case;
    my @hsl = Smokeping::Colorspace::rgb_to_hsl($r, $g, $b);
    my @rgb = Smokeping::Colorspace::hsl_to_rgb(@hsl);
    near($rgb[0], $r, 1e-4, "hsl round-trip $name R");
    near($rgb[1], $g, 1e-4, "hsl round-trip $name G");
    near($rgb[2], $b, 1e-4, "hsl round-trip $name B");
}

# --- min_max_indexes ---

{
    my ($min_i, $min, $max_i, $max) = Smokeping::Colorspace::min_max_indexes(3, 1, 2);
    is($min_i, 1, 'min_max_indexes: min index');
    is($min,   1, 'min_max_indexes: min value');
    is($max_i, 0, 'min_max_indexes: max index');
    is($max,   3, 'min_max_indexes: max value');
}

{
    my ($min_i, $min, $max_i, $max) = Smokeping::Colorspace::min_max_indexes(5, 5, 5);
    is($min, 5, 'min_max_indexes: all equal min');
    is($max, 5, 'min_max_indexes: all equal max');
}

{
    my ($min_i, $min, $max_i, $max) = Smokeping::Colorspace::min_max_indexes(-1, 0, 1);
    is($min_i, 0,  'min_max_indexes: negative min index');
    is($min,   -1, 'min_max_indexes: negative min value');
    is($max_i, 2,  'min_max_indexes: negative max index');
    is($max,   1,  'min_max_indexes: negative max value');
}

{
    my ($min_i, $min, $max_i, $max) = Smokeping::Colorspace::min_max_indexes(42);
    is($min_i, 0,  'min_max_indexes: single element min index');
    is($min,   42, 'min_max_indexes: single element min value');
    is($max_i, 0,  'min_max_indexes: single element max index');
    is($max,   42, 'min_max_indexes: single element max value');
}

done_testing;
