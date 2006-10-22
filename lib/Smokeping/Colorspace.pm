# -*- perl -*-

package Smokeping::Colorspace;

=head1 NAME

Smokeping::Colorspace - Simple Colorspace Conversion methods

=head1 OVERVIEW

This module provides simple colorspace conversion methods, primarily allowing 
conversion from RGB (red, green, blue) to and from HSL (hue, saturation, luminosity).

=head1 COPYRIGHT

Copyright 2006 by Grahame Bowland.

=head1 LICENSE

This program is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.  See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public
License along with this program; if not, write to the Free
Software Foundation, Inc., 675 Mass Ave, Cambridge, MA
02139, USA.

=head1 AUTHOR

Grahame Bowland <grahame.bowland@uwa.edu.au>

=cut

sub web_to_rgb {
	my $web = shift;
	$web =~ s/^#//;
	my @rgb = (hex(substr($web, 0, 2)) / 255,
		   hex(substr($web, 2, 2)) / 255,
		   hex(substr($web, 4, 2)) / 255) ;
	return @rgb;
}

sub rgb_to_web {
	my @rgb = @_;
	return sprintf("#%.2x%.2x%.2x", 255 * $rgb[0], 255 * $rgb[1], 255 * $rgb[2]);
}

sub min_max_indexes {
	my $idx = 0;
	my ($min_idx, $min, $max_idx, $max);
	my @l = @_;
		
	foreach my $i (@l) {
		if (not defined($min) or ($i < $min)) {
			$min = $i;
			$min_idx = $idx;
		}
		if (not defined($max) or ($i > $max)) {
			$max = $i;
			$max_idx = $idx;
		}
		$idx++;
	}
	return ($min_idx, $min, $max_idx, $max);	
}

# source for conversion algorithm is:
# http://www.easyrgb.com/math.php?MATH=M18#text18
sub rgb_to_hsl {
	my @rgb = @_;
	my ($h, $l, $s);

	my ($min_idx, $min, $max_idx, $max) = min_max_indexes(@rgb);
	my $delta_max = $max - $min;
	$l = ($max + $min) / 2;
	if ($delta_max == 0) {
		my $h = 0;
		my $s = 0;
	} else {
		if ($l < 0.5) {
			$s = $delta_max / ($max + $min);
		} else {
			$s = $delta_max / (2 - $max - $min);
		}
		my $delta_r = ((($max - $rgb[0]) / 6) + ($max / 2)) / $delta_max;
		my $delta_g = ((($max - $rgb[1]) / 6) + ($max / 2)) / $delta_max;
		my $delta_b = ((($max - $rgb[2]) / 6) + ($max / 2)) / $delta_max;
		if ($max_idx == 0) {
			$h = $delta_b - $delta_g;
		} elsif ($max_idx == 1) {
			$h = (1/3) + $delta_r - $delta_b;
		} else {
			$h = (2/3) + $delta_g - $delta_r;
		}
		if ($h < 0) {
			$h += 1;
		} elsif ($h > 1) {
			$h -= 1;
		}
	}
	return ($h, $s, $l);
}

sub hue_to_rgb  {
	my ($v1, $v2, $vh) = @_;
	if ($vh < 0) {
		$vh += 1;
	} elsif ($vh > 1) {
		$vh -= 1;
	}
	if  ($vh * 6 < 1) {
		return $v1 + ($v2 - $v1) * 6 * $vh;
	} elsif ($vh * 2 < 1)  {
		return $v2;
	} elsif ($vh * 3 < 2) {
		return $v1 + ($v2 - $v1) * ((2/3) - $vh) * 6;
	} else {
		return $v1;
	}
}

sub hsl_to_rgb {
	my ($h, $s, $l) = @_;
	my ($r, $g, $b);
	if ($s == 0) {
		$r = $g = $b = $l;
	} else {
		my $ls;
		if ($l < 0.5) {
			$ls = $l * (1 + $s);
		} else {
			$ls = ($l + $s) - ($s * $l);
		}
		$l = 2 * $l - $ls;
		$r = hue_to_rgb($l, $ls, $h + 1/3);
		$g = hue_to_rgb($l, $ls, $h);
		$b = hue_to_rgb($l, $ls, $h - (1/3));
	}
	return ($r, $g, $b);
}

1;

