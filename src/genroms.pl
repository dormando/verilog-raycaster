#!/usr/bin/perl
# generates the various .rom lookup tables

use warnings;
use strict;

my $odir = $ARGV[0] || './';

camerax();
floordist();
angle();
idist();
iheight();
height();

sub height {
    # 32 / 1024 (32 == max distance)
    # convert distance to wall height.
    # FIXME: caps out too early. causes distortion when too close to a wall.
    my $fh = outfile('height.rom');
    my $scale = 0.03125;
    my $tot = $scale;
    for (my $x = 0; $x < 1024; $x++) {
        my $cur = int(240 / $tot);
        # height
        $cur = 238 if ($cur > 238);
        # also the Q8.8 inverse of height
        my $icur = int((1 / $tot) * 2**8);
        # texture scale
        my $tscale = int((32 << 8) / $cur);
        my $bin = pack('Cnn', $cur, $tscale, $icur);
        my $str = hexstr($bin);

        print $fh "   heights[$x] = 40'h$str;\n";
        $tot += $scale;
    }
    close($fh);
}

sub iheight {
    # inverse height for sprite scaler (32 / height)
    # wall scaling should really use this table. they cap out too low which
    # causes distortion when close to a wall.
    my $fh = outfile('iheight.rom');
    for (my $x = 0; $x < 512; $x++) {
        # inverse of resultant height for picking pixels
        # 32 being the sprite/texture original size.
        my $ih = int((32 / ($x != 0 ? $x : 1)) * 2**8);
        my $bin = pack('n', $ih);
        my $str = hexstr($bin);

        print $fh "   iheights[$x] = 16'h$str;\n";
    }
    close($fh);
}

sub idist {
    my $fh = outfile('idist.rom');
    # 32 / 1024 (32 == max distance. also the tile/sprite size :P)
    my $scale = 0.03125;
    my $tot = $scale;
    for (my $x = 0; $x < 1024; $x++) {
        # Q8.8 inverse of distance
        my $icur = int((1 / $tot) * 2**8);
        my $bin = pack('n', $icur);
        my $str = hexstr($bin);

        print $fh "   idists[$x] = 16'h$str;\n";
        $tot += $scale;
    }
    close($fh);
}

sub angle {
    my $fh = outfile('angle.rom');
    # pre-generated turn angles. This is me avoiding cos/sin/tan/atan tables.
    # current camera angle is simply determined by an array position.
	my $dirX = -1;
	my $dirY = 0;
	my $planeX = 0;
	my $planeY = 0.66;
	my $rotSpeed = 0.050264; # 1 / 60 * 3.0

    my $inverse = sub {
		# for sprite matrix transform.
		return 1.0 / ($planeX * $dirY - $dirX * $planeY);
    };

	my $invDet = $inverse->();

	my $idx = 0;

	my $binpack = sub {
		my $bin = pack('nnnnn', int($dirX * (2**8)),
			int($dirY * (2**8)),
			int($planeX * (2**8)),
			int($planeY * (2**8)),
			int($invDet * (2**8)));
        my $str = hexstr($bin);
		# too lazy to batch by 2 but this looks better than them all mashed up.
		printf $fh "  angles[$idx] = 80'h$str;\n";
		$idx++;
    };

	$binpack->();

	# FIXME: reverse? meh.
	for (my $x = 0; $x < 125; $x++) {
		my $ox = $dirX;
		$dirX = $dirX * cos(-$rotSpeed) - $dirY * sin(-$rotSpeed);
		$dirY = $ox * sin(-$rotSpeed) + $dirY * cos(-$rotSpeed);
		my $opx = $planeX;
		$planeX = $planeX * cos(-$rotSpeed) - $planeY * sin(-$rotSpeed);
		$planeY = $opx * sin(-$rotSpeed) + $planeY * cos(-$rotSpeed);
		$invDet = $inverse->();
	   
		$binpack->();
	}
    close($fh);
}

sub floordist {
    # similar inverse distance for floor heights.
    # table is halved since it's mirrored 0-119 and 120-240
    my $fh = outfile('floordist.rom');
    for (my $x = 121; $x <= 240; $x++) {
        my $cur = eval{240 / (2.0 * $x - 240)};
        my $bin = pack('n', int($cur * 2**8));
        my $str = hexstr($bin);

        my $off = $x - 121;
        print $fh "  floor_dist[$off] = 16'h$str;\n";
    }

    close($fh);
}

sub camerax {
    # generates an inverse range -1 to 1 over the width of the screen.
    my $fh = outfile('camerax.rom');
    for (my $x = 0; $x < 320; $x++) {
        my $cur = 2 * $x / 320 - 1;
        my $bin = pack('n', int($cur * 2**8));
        my $str = hexstr($bin);

        print $fh "  camerax_pos[$x] = 16'h$str;\n";
    }
    close($fh);
}

sub hexstr {
    my $b = shift;
    my $str = join("", map { sprintf("%02x_", ord($_)) } split(//, $b));
    chop($str);
    return $str;
}

sub outfile {
    my $f = shift;
    open(my $fh, "> $odir/$f") or die "couldn't open: $odir/$f for writing: $!";
    return $fh;
}
