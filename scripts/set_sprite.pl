#!/usr/bin/perl
# sets a sprite position.

use warnings;
use strict;
use Device::SerialPort;
use Data::Dumper qw/Dumper/;

$|++;
my $port = Device::SerialPort->new("/dev/ttyACM0");

#$port->baudrate(9600);
#$port->baudrate(115200);
$port->baudrate(256000);
$port->databits(8);
$port->parity("none");
$port->stopbits(1);
# timeout stuff
$port->read_char_time(0);
$port->read_const_time(1000);

my $map_x = $ARGV[0] or die "moo";
my $map_y = $ARGV[1] or die "boo";

my $cmd = 0b10000110;
my $map_pos = pack('ss', int($map_x * 2**8), int($map_y * 2**8));
# FIXME: hard coded texture ID + sprite id (also pick a position :P)
my $packed = pack('CScccc', $cmd, 0, 0, 8, 8, 0);
$port->write($packed . $map_pos);

