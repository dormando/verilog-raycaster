#!/usr/bin/perl

use warnings;
use strict;
use Device::SerialPort;

my $port = Device::SerialPort->new("/dev/ttyACM0");

$port->baudrate(9600);
#$port->baudrate(115200);
$port->databits(8);
$port->parity("none");
$port->stopbits(1);
# timeout stuff
$port->read_char_time(0);
$port->read_const_time(1000);

# 0x36  , 1, 0b11001000,             // Memory Access Control (orig: 0x48)
my $iblob = qq{0xEF, 3, 0x03, 0x80, 0x02,
0xCF, 3, 0x00, 0xC1, 0x30,
0xED, 4, 0x64, 0x03, 0x12, 0x81,
0xE8, 3, 0x85, 0x00, 0x78,
0xCB, 5, 0x39, 0x2C, 0x00, 0x34, 0x02,
0xF7, 1, 0x20,
0xEA, 2, 0x00, 0x00,
0xC0  , 1, 0x23,             // Power control VRH[5:0] 0x23: 0b100011 4.60V ?
0xC1  , 1, 0x10,             // Power control SAP[2:0];BT[3:0] 0b10000
0xC5  , 2, 0x3e, 0x28,       // VCM control 0b111110 0b101000
0xC7, 1, 0x86,             // VCM control2
0x36  , 1, 0b11001000,             // Memory Access Control (orig: 0x48)
0x37, 1, 0x00,             // Vertical scroll zero
0x3A, 1, 0x55, // pixel format
0xB1, 2, 0x00, 0x18,
0xB6, 3, 0x08, 0x82, 0x27, // Display Function Control
0xF2, 1, 0x00,                         // 3Gamma Function Disable
0x26, 1, 0x01,             // Gamma curve selected
0xE0, 15, 0x0F, 0x31, 0x2B, 0x0C, 0x0E, 0x08, 0x4E, 0xF1, 0x37, 0x07, 0x10, 0x03, 0x0E, 0x09, 0x00, // set gamma
0xE1, 15, 0x00, 0x0E, 0x14, 0x03, 0x11, 0x07, 0x31, 0xC1, 0x48, 0x08, 0x0F, 0x0C, 0x31, 0x36, 0x0F, // set gamma
0x11, 0x80,                // Exit Sleep
0x29, 0x80,                // Display on
};

my $BLACK = 0x0000;
my $MAROON = 0x7800;

$iblob =~ s!//.*!!g;
$iblob =~ s/,/ /g;
$iblob =~ s/[ ]+/ /g;
#print $iblob;
open(my $dump, "> lcd_output") or die "meh: $!";

if ($ARGV[0]) {
    mad_ctl();
} else {
    reset_lcd();
    init();
    write_bytes();
}
exit;

sub mad_ctl {
    my $cmd = 0b10000101;
    my $cbyte = 0x36; # MADCTL
    my $packed = pack('CSLL', $cmd, 500, 0, $cbyte);
    $port->write($packed);
    $cbyte = 0b00001000; # BGR
    $cbyte |= 0b00000000; # MX (column address order)
    $packed = pack('CSLL', $cmd, 500, 0, $cbyte + 256);
    $port->write($packed);
    select undef, undef, undef, 0.1;
}

# reset sequence.
sub reset_lcd {
    print "resetting...\n";
    my $cmd = 0b00000101;
    my $packed = pack('CSL', $cmd, 0, 1);
    $port->write($packed);
    select undef, undef, undef, 0.250;
    my $junk = $port->read(255);
    $packed = pack('CSL', $cmd, 0, 0);
    $port->write($packed);
    select undef, undef, undef, 0.250;
    $junk = $port->read(255);
    $packed = pack('CSL', $cmd, 0, 1);
    $port->write($packed);
    select undef, undef, undef, 0.250;
    $junk = $port->read(255);
    print "done reset.\n";
}

sub init {
    for my $l (split /\n/, $iblob) {
        my @d = split /\s+/, $l;
        my $cbyte = eval(shift @d);
        my $bcnt = shift @d;

        # register interface takes cmd with 9th bit low, data is all 9th bit high.
        my $cmd = 0b10000101;
        my $packed = pack('CSLL', $cmd, 0, 0, $cbyte);
        print $dump $packed;
        $port->write($packed);
        select undef, undef, undef, 0.01;

        # now write out the arguments.
        for (@d) {
            my $byte = eval($_); # holy dangerous, batman :P
            $byte += 256; # DCX to high for data.
            my $packed = pack('CSLL', $cmd, 0, 0, $byte);
            $port->write($packed);
            print $dump $packed;
            select undef, undef, undef, 0.01;
        }
        if ($bcnt eq '0x80') {
            select undef, undef, undef, 0.25;
        }
    }
}

#define ILI9341_CASET   0x2A
#define ILI9341_PASET   0x2B
#define ILI9341_RAMWR   0x2C

# 0x28 off
# 0x29 on
sub power_cycle {
    my $cmd = 0b10000101;
    my $cbyte;

    # off
    $cbyte = 0x28;
    my $packed = pack('CSLL', $cmd, 0, 0, $cbyte);
    $port->write($packed);
    sleep 3;
    $cbyte = 0x29;
    $packed = pack('CSLL', $cmd, 0, 0, $cbyte);
    $port->write($packed);
    sleep 1;
}

sub write_bytes {
    print "ca/pa set\n";
    {
        my $cmd = 0b10000101;
        my $cbyte;

        $cbyte = 0x2A;
        my $x0 = 0;
        my $x1 = 240;
        my $y0 = 0;
        my $y1 = 320;
        my $packed = pack('CSL', $cmd, 9);
        $packed .= pack('L', $cbyte);
        $packed .= pack('L', 256);
        $packed .= pack('L', $x0 + 256);
        $packed .= pack('L', 256);
        $packed .= pack('L', ($x1 & 0x00FF) + 256);
        $cbyte = 0x2B;
        $packed .= pack('L', $cbyte);
        $packed .= pack('L', 256);
        $packed .= pack('L', $y0 + 256);
        $packed .= pack('L', ($y1 >> 8) + 256);
        $packed .= pack('L', ($y1 & 0x00FF) + 256);
        $port->write($packed);
    }
    return;

    # Randomly try writing a bunch...
    print "shove pixel\n";
    {
        my $cmd = 0b10000101;
        my $cbyte = 0x2C;
        my $packed = pack('CSLL', $cmd, 500, 0, $cbyte);
        $port->write($packed);
    }
    return;
    for (1 .. 500) {
        my $packed = pack('L', 256);
        $packed .= pack('L', 256);
        $port->write($packed);
    }
    sleep 1;
    {
        my $cmd = 0b10000101;
        my $cbyte = 0x00; # NOP
        my $packed = pack('CSLL', $cmd, 0, 0, $cbyte);
        $port->write($packed);
    }
}

close($dump);


#my $cmd = 0b10000101;
#my $packed = pack('CSLL', $cmd, 0, 0, $leds);
#$port->write($packed);


