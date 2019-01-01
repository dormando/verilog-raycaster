#!/usr/bin/perl

use warnings;
use strict;
use Device::SerialPort;

my $port = Device::SerialPort->new("/dev/ttyACM0");

#$port->baudrate(9600);
$port->baudrate(115200);
$port->databits(8);
$port->parity("none");
$port->stopbits(1);
# timeout stuff
$port->read_char_time(0);
$port->read_const_time(1000);

my $offset = 0;
my $poffset = 0;

for my $file (@ARGV) {
    load_tex($file, $offset);
    my $pal = $file;
    $pal =~ s/\.flat/.pal/;
    load_pal($pal, $poffset);
    $offset += 1024;
    $poffset += 15;
    select undef, undef, undef, 0.25;
}

sub load_pal {
    my $file = shift;
    my $offset = shift;
    print "$file...\n";
    open(my $fh, "<$file") or die "boop: $!";
    my $buf;
    my $pbuf;
    my $cnt = 0;
    while (read($fh, $buf, 2)) {
        $pbuf .= $buf . pack('n', 0);
        $cnt++;
    }
    close($fh);

    my $cmd = 0b11000001;
    my $packed = pack('CSL', $cmd, $cnt-1, $offset);
    $port->write($packed);
    $port->write($pbuf);
}

sub load_tex {
    my $file = shift;
    my $offset = shift;
    print "$file...\n";
    open(my $fh, "<$file") or die "boop: $!";
    my $buf;
    my $pbuf;
    while (read($fh, $buf, 1)) {
        $pbuf .= pack('L', ord($buf));
    }
    close($fh);

    my $cmd = 0b11000011;
    my $packed = pack('CSL', $cmd, 1023, $offset);
    $port->write($packed);
    $port->write($pbuf);
}
