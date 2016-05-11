#!/usr/bin/perl

# Script to modify the database in a GDSII stream file

use strict;
use warnings;
no warnings 'experimental';
use GDS2;
use File::Copy "mv";
use File::Basename;
use Getopt::Long qw(:config no_ignore_case);
use v5.14;

use lib dirname(__FILE__);
use mlib::debug;
use mlib::util;

### Initialize variables ############## {{{

my $help = 0;
my $debug = 0;
my @mod_layers = ();
my @mod_cells = ();

my @remove_cells = ();
my @remove_str = ();
my @remove_ref = ();

my @rename_cells = ();
my @rename_str = ();
my @rename_ref = ();

my @database = ();
my @units = ();

####################################### }}}
### Process input parmeters ########### {{{

my $opt = GetOptions(
    "help|h" => \$help,
    "layer|l=i{2}" => \@mod_layers,
    "remove|r=s{1,}" => \@remove_cells,
    "remove_str=s{1,}" => \@remove_str,
    "remove_ref=s{1,}" => \@remove_ref,
    "rename|n=s{2}" => \@rename_cells,
    "rename_str=s{2}" => \@rename_str,
    "rename_ref=s{2}" => \@rename_ref,
    "debug"  => \$debug,
);

print "Debug mode\n" if $debug;

if ( $ARGV[0] eq '' || $help eq 1 || !$opt ) {
    print "Usage:\n";
    print "\t$0 INPUT_GDS2_FILE [OUTPUT_GDS2_FILE] [OPTION...]";
    print "\n";
    print "Options:\n";
    print "    -h, --help                 Print this help text\n";
    print "    -l, --layer N1 N2          Change layer number N1 to N2\n";
    print "    -r, --remove CELL          Remove structure CELL and all references from the database\n";
    print "    --remove_str CELL          Remove structure CELL from the database, leaving all references\n";
    print "    --remove_ref CELL          Remove all references to structure CELL from the database\n";
    print "    -n, --rename CELL1 CELL2   Rename structure CELL1, and all references, to CELL2\n";
    print "    --rename_str CELL1 CELL2   Rename structure CELL1 to CELL2\n";
    print "    --rename_ref CELL1 CELL2   Rename all references to structure CELL1 to CELL2\n";
    print "\n";
    print "Description:\n";
    print "  Modify the database inside INPUT_GDS2_FILE. If specified, the modified        \n";
    print "  database will written into the stream file OUTPUT_GDS2_FILE. Otherwise, the   \n";
    print "  original file will be backed up and the modified database will be written back\n";
    print "  into that file name.                                                          \n";
    exit 0;
}

# check files {{{
unless ( -e $ARGV[0] ) {
    print "$ARGV[0]: file not found!";
    exit 1;
}
my $input_filename = '';
my $output_filename = '';
if ( exists $ARGV[1] and $ARGV[1] ne '' ) {
    $input_filename = $ARGV[0];
    $output_filename = $ARGV[1];
} else {
    mv $ARGV[0], "$ARGV[0]~";
    $input_filename = "$ARGV[0]~";
    $output_filename = $ARGV[0];
}
print "Input:\t$input_filename\n";
print "Output:\t$output_filename\n";
my $input_gds2file = new GDS2( -fileName => $input_filename );
my $output_gds2file = new GDS2( -fileName => ">$output_filename" );
# }}}
# setup removal arrays {{{
foreach my $c ( @remove_cells ) {
    push( @remove_str, $c );
    push( @remove_ref, $c );
}
#@remove_str = uniq( @remove_str );
#@remove_ref = uniq( @remove_ref );
# }}}
# create layer map {{{
my %layer_map = ();
if ( @mod_layers ) {
    for ( my $i = 0 ; $i <= $#mod_layers ; $i += 2 ) {
        $layer_map{$mod_layers[$i]} = $mod_layers[$i+1];
    }
}
# }}}
# create structure maps {{{
my %str_map = ();
my %ref_map = ();
if ( @rename_cells ) {
    for ( my $i = 0 ; $i <= $#rename_cells ; $i += 2 ) {
        $str_map{$rename_cells[$i]} = $rename_cells[$i+1];
        $ref_map{$rename_cells[$i]} = $rename_cells[$i+1];
    }
}
if ( @rename_str ) {
    for ( my $i = 0 ; $i <= $#rename_str ; $i += 2 ) {
        $str_map{$rename_str[$i]} = $rename_str[$i+1];
    }
}
if ( @rename_ref ) {
    for ( my $i = 0 ; $i <= $#rename_ref ; $i += 2 ) {
        $ref_map{$rename_ref[$i]} = $rename_ref[$i+1];
    }
}
# }}}

if ( @remove_ref ) {
    print "\nRemove (ref):\n\n";
    foreach my $c (@remove_ref) { print "  $c\n"; }
}
if ( @remove_str ) {
    print "\nRemove (str):\n\n";
    foreach my $c (@remove_str) { print "  $c\n"; }
}

if ( %str_map ) {
    print "\nRename (ref):\n\n";
    foreach my $c (keys %str_map) { print "  $c => $str_map{$c}\n"; }
}
if ( %ref_map ) {
    print "\nRename (str):\n\n";
    foreach my $c (keys %ref_map) { print "  $c => $ref_map{$c}\n"; }
}

if ( %layer_map ) {
    print "\nLayer map:\n\n";
    foreach my $l (keys %layer_map) { print "  $l => $layer_map{$l}\n"; }
}



####################################### }}}
### Read GDSII database ############### {{{

while ( $input_gds2file -> readGds2Record ) {
    my @record = split( ' ', $input_gds2file -> returnRecordAsString );
    if ( $input_gds2file -> isUnits ) { @units = @record[1,2]; }
    if ( $#record == 0 ) {
        push @database, { 'type' => $record[0] };
    } elsif ( $#record == 1 ) {
        $record[1] =~ s/'//g;
        if ( $input_gds2file -> isWidth ) {
            $record[1] = sprintf( '%d', ( $record[1] / $units[0] ) );
            # fixed rounding errors
            $record[1] += ( $record[1] % 5 == 4 ? 1 : 0 );
            $record[1] -= ( $record[1] % 5 == 1 ? 1 : 0 );
        }
        push @database, { 'type' => $record[0], 'data' => $record[1] };
    } else {
        if ( $input_gds2file -> isXy ) {
            for ( my $i = 1 ; $i <= $#record ; $i++ ) {
                $record[$i] = sprintf( '%d', ( $record[$i] / $units[0] ) );
                # fixed rounding errors
                $record[$i] += ( $record[$i] % 5 == 4 ? 1 : 0 );
                $record[$i] -= ( $record[$i] % 5 == 1 ? 1 : 0 );
            }
        }
        push @database, { 'type' => $record[0], 'data' => [ @record[1 .. $#record] ] };
    }
}

####################################### }}}
### Modify GDSII database ############# {{{

# getStrname: look ahead for structure name {{{
sub getStrname ($) {
    my $pos = shift;
    $pos++ until $database[$pos]->{'type'} eq 'STRNAME';
    return $database[$pos]->{'data'};
}
# }}}
# getRefname: look ahead for structure reference name {{{
sub getRefname ($) {
    my $pos = shift;
    $pos++ until $database[$pos]->{'type'} eq 'SNAME';
    return $database[$pos]->{'data'};
}
# }}}
# remStr: remove structure from database {{{
sub remStr ($) {
    my $pos = shift;
    my $offset = 0;
    $offset++ until $database[$pos + $offset]->{'type'} eq 'ENDSTR';
    splice @database, $pos, $offset + 1;
}
# }}}
# remRef: remove structure reference from database {{{
sub remRef ($) {
    my $pos = shift;
    my $offset = 0;
    $offset++ until $database[$pos + $offset]->{'type'} eq 'ENDEL';
    splice @database, $pos, $offset + 1;
}
# }}}

RECORD: for ( my $i = 0 ; $i <= $#database ; $i++ ) {
    for ( $database[$i]->{'type'} ) {
        when( /BGNSTR/ ) {
            foreach my $s ( @remove_str ) {
                do { remStr($i); redo RECORD; } if $s eq getStrname($i);
            }
        }
        when( /[AS]REF/ ) {
            foreach my $s ( @remove_ref ) {
                do { remRef($i); redo RECORD; } if $s eq getRefname($i);
            }
        }
        when( /LAYER/ ) {
            $database[$i]->{'data'} = $layer_map{$database[$i]->{'data'}} if (exists $layer_map{$database[$i]->{'data'}});
        }
        when( /SNAME/ ) {
            $database[$i]->{'data'} = $ref_map{$database[$i]->{'data'}} if (exists $ref_map{$database[$i]->{'data'}});
        }
        when( /STRNAME/ ) {
            $database[$i]->{'data'} = $str_map{$database[$i]->{'data'}} if (exists $str_map{$database[$i]->{'data'}});
        }
        default { next RECORD; }
    }
}

####################################### }}}
### Write GDSII database ############## {{{

foreach my $r ( @database ) {
    if ( exists $r->{'data'} and $r->{'data'} ne '' ) {
        $output_gds2file -> printGds2Record( -type => "$r->{'type'}", -data => $r->{'data'} );
    } else {
        $output_gds2file -> printGds2Record( -type => "$r->{'type'}" );
    }
}

$output_gds2file -> close( -pad => 2048 );

####################################### }}}
