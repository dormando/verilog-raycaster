#!/usr/bin/perl
# parses textures/sprites into flat data loadable by the serial protocol,
# along with palette files for each.
# see: tload.sh and texloader.pl

use warnings;
use strict;

use GD;

my $sdir = $ARGV[0];
my $odir = $ARGV[1];
my $sprite = $ARGV[2] || 0;

opendir(my $dh, $sdir) or die "meh: $!";
while (readdir($dh)) {
    next unless $_ =~ m/\.png$/;
    process($_);
}
closedir($dh);

sub sixteenbit {
    my @c = @_;
    $c[0] = ($c[0] * 249 + 1024) >> 11;
    $c[1] = ($c[1] * 253 + 505) >> 10;
    $c[2] = ($c[2] * 249 + 1024) >> 11;
    my $bin = pack('s', ($c[0] << 11) | ($c[1] << 5) | $c[2]);
    return $bin;
}

sub process {
    my $file = shift;
    my $im = GD::Image->newFromPng($sdir . $file, 1);
    # 15 colors + alpha channel (always high color).

    my $nim = new GD::Image->newTrueColor(32, 32);
    $nim->alphaBlending(0);
    $nim->saveAlpha(1);
    # we downsample to 32x32x4bit to save block RAM.
    $nim->copyResampled($im, 0, 0, 0, 0, 32, 32, 64, 64);
    $nim->trueColorToPalette(0, 14);
    my $total = $nim->colorsTotal;
    # some of the source sprites aren't 64x64
    if ($total == 256 || $im->width != 64 || $im->height != 64) {
        print "Skipping: $file: $total\n";
        return;
    }
    print "$file: $total\n";

    # Copy color index.
    open(my $pal, "> $odir/$file.pal") or die "boop: $!";
    for (0 .. $total-1) {
        print $pal sixteenbit($nim->rgb($_));
    }
    close($pal);

    my @f;
    open(my $flat, "> $odir/$file.flat") or die "boop: $!";
    # the alpha seems to get randomized during "dithering" above.
    # in these particular source images the corner is always a transparent
    # one, so find that index and re-slot it into our alpha channel number.
    my $alpha = $nim->getPixel(0, 0);
    for (my $x = 0; $x < $nim->width; $x++) {
        for (my $y = 0; $y < $nim->height; $y++) {
            my $c = $nim->getPixel($x, $y);
            #print $flat $f[$x][$y], " ";
            #print $flat $c, " ";
            if ($c == $alpha && $sprite) {
                # only for sprites!
                # keep a consistent alpha channel.
                $c = 15;
            }
            #print "C: $c\n";
            print $flat pack('C', $c);
        }
    }

    open(my $out, "> $odir/$file") or die "boop: $!";
    binmode $out;
    print $out $nim->png;
    close($out);
    close($flat);
}
