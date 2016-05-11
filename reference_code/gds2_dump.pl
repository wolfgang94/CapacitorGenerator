#!/usr/bin/perl

use strict ;
use GDS2 ;

$\="\n" ;

my $gds2file ;

if ( $ARGV[0] eq "" ) {
    print "Usage: $0 input_GDS2_file" ;
    print "\tinput_GDS2_FILE: GDS file to dump to screen" ;
} elsif ( -e $ARGV[0] ) {
    $gds2file = new GDS2(-fileName => $ARGV[0]) ;
} else {
    print "$ARGV[0]: file not found" ;
    exit 0 ;
}

my $pos = 0 ;
while ( $gds2file -> readGds2Record ) {
    my $size = $gds2file -> recordSize ;
    print sprintf( '%08u (%04u)', $pos, $size ) ." : ". $gds2file -> returnRecordAsString ;
    $pos += $size ;
}

