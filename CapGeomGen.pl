#!/usr/bin/perl

use strict;
use warnings;
use File::Basename;

use lib dirname(__FILE__);
use JSON::Simple;
use mlib::debug;
use mlib::util;
use mlib::icwin;

### Load technology info {{{

if ( $ARGV[0] eq "" ) {
    print "Technology file required\n";
    exit;
}
open( my $file_in, '<', $ARGV[0] ) or die "Error loading technology file ($ARGV[0])\n";

my $tech_in = "";
while (<$file_in>) {
    s/\n//;
    s/\r//;
    s/\s+//g;
    $tech_in .= $_;
}

my %tech_lib = %{from_json($tech_in)};

my %lib  = %{$tech_lib{layers}};
my %cell = %{$tech_lib{cells}};
my %mos  = %{$tech_lib{mos}};

parse_lib \%lib;

my @input = ($ARGV[1], lc($ARGV[2]), $ARGV[3]); #Array of input arguments
my $mincaplength = 73; #minimum width of the capacitor
my $rotate = 0; #if 0, no need to rotate, if 1 you should rotate that mofo

#I should probably calculate the proscribed value here?

#if the constraining parameter of the capacitor is the width, and this width is below the proscribed value rotate the capacitor.
if (($input[1] eq "w") && ($input[2] <= $mincaplength)) {
    $rotate = 0; #y'gotta rotate it
}

#hash for device characteristics
my %dev = ();

my %prefixes = (
		"f" => 1e-15,
		"p" => 1e-12,
		"n" => 1e-9,
		"u" => 1e-6,
		);

#Device Capacitance Alt.
#Checks for units of cap and then adjusts to proper units for calculations
if ( defined($input[0]) && $input[0] =~ /^(\d+\.?\d*|\d*\.\d+)(?:[ ]*(f|p|n|u))?(?:[ ]*[f])?$/i ) {
    if (definded($2)) {
      $dev{cap} = ($1*$prefixes{lc($2)})/$prefixes{f};
    } else {
      $dev{cap} = $1;
    }
} else {
    print "Device must have a valid capacitance value";
    exit;
}

# Device parameter value
#Need a check on the value to ensure it is of minimum size
if ( defined($input[1]) && ($input[1] =~ /^(\d+\.?\d*|\d*\.\d+)(?:[ ]*(f|p|n|u))?(?:[ ]*[m])?$/i) && ) {
    if (definded($2)) {
    $dev{w} = ($1*$prefixes{lc($2)})/$prefixes{u};
    $dev{w} = read_num($dev{w});
    } else {
      $dev{cap} = read_num($1);
    }
} else {
    print "Valid device measurement is required\n";
    exit;
}

my $w = write_num($dev{w});
my $l = write_num($dev{l});

if ($w < 1) {
  $w *= 1000; ($w = "$w");
} else {
  ($w = sprintf("%.3f", $w)) =~ s/\./p/; $w =~ s/p0+$//;
}
if ($l < 1) {
  $l *= 1000; ($l = "$l");
} else {
  ($l = sprintf("%.3f", $l)) =~ s/\./p/; $l =~ s/p0+$//;
}

$dev{name}  = $dev{cap} ."capacitor". $dev{v};
$dev{name} .= "_". $w .($dev{w} > read_num(1) ? "u" : "n");
$dev{name} .= "x". $l .($dev{l} > read_num(1) ? "u" : "n");
$dev{name} .= $post;
$dev{name}  = uc($dev{name});
 
