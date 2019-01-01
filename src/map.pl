#!/usr/bin/perl

use warnings;
use strict;

my $mfile = $ARGV[0];

open(my $fh, "< $mfile") or die "boop: $!";
my $x = 0;
while (my $l = <$fh>) {
    chomp $l;
    my $y = 0;
    $l =~ s/^\s+//;
    $l =~ s/,$//;
    $l =~ s/[{}]//g;
    for my $col (split(/,/, $l)) {
        print "    map[$x][$y] = 4'd$col;\n";
        $y++;
    }
    $x++;
}
close($fh);
