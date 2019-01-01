#!/usr/bin/perl

use warnings;
use strict;
use Device::SerialPort;
use Data::Dumper qw/Dumper/;

$|++;
my $port = Device::SerialPort->new("/dev/ttyACM0");

$port->baudrate(9600);
#$port->baudrate(115200);
#$port->baudrate(256000);
$port->databits(8);
$port->parity("none");
$port->stopbits(1);
# timeout stuff
$port->read_char_time(0);
$port->read_const_time(1000);

open(my $sout_line, "> sout_line") or die "meh: $!";
$sout_line->autoflush(1);

my $leds = $ARGV[0];
my $map_x = $ARGV[1];
my $map_y = $ARGV[2];
my $turn = $ARGV[3];
# show how many CPU cycles the frame took.
my $cycles = $ARGV[4] || 0;
# Blank LED's.
my $cmd = 0b10000000;
my $packed = pack('CSLL', $cmd, 0, 0, $leds);
$port->write($packed);
select undef, undef, undef, 0.1;

print "casting rays...\n";
cast_rays();

sub reduce {
    my $f = int($_[0] * 2**8);
    $f = -3200 if ($f < -32000);
    $f = 32000 if ($f > 32000);
    return $f;
}

sub cast_rays {
    my $cmd = 0b11000100;
    my $map_pos = pack('ss', int($map_x * 2**8), int($map_y * 2**8));
    my $packed = pack('CSL', $cmd, 1, 0);
    $port->write($packed . $map_pos . pack('L', $turn));
    return unless $cycles;
    # Should be more or less instantly done, but sleep a bit anyway.
    select undef, undef, undef, 0.1;
    $cmd = 0b00000100;
    $packed = pack('CSL', $cmd, 0, 0);
    $port->write($packed);
    {
        my $buf = '';
        my $timeout = 2;
        while ($timeout) {
            my ($count, $got) = $port->read(255);
            if ($count > 0) {
                $buf .= $got;
                last if length($buf) >= 4;
            } else {
                $timeout--;
            }
            print STDERR "cycle $count\n";
        }
        print "cycle count: ", unpack('L', $buf), "\n";
        open(my $dump, "> cycle_output") or die "meh: $!";
        print $dump $buf;
        close($dump);
    }
}
