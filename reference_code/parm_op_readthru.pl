#!/usr/bin/perl

use strict;
use warnings;
use File::Basename;

use lib dirname(__FILE__);
use JSON::Simple;
use mlib::debug;
use mlib::util;
use mlib::icwin;

use POSIX;
use Math::Trig;

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
    s/\s+/ /g;
    $tech_in .= $_;
}

my %tech_lib = %{from_json($tech_in)};

my %lib    = %{$tech_lib{layers}};
my %cell   = %{$tech_lib{cells}};
my %predef = %{$tech_lib{predef}};

parse_lib \%lib;

print_readable %lib;
#print_readable %cell;

### }}}
### Setup {{{

my $debug = 1;

# PI
my $pi = 3.141592;

# open input file
if ( $ARGV[1] eq "" ) {
    print "Input file required\n";
    exit;
}
my $inFile = "$ARGV[1]";
open(IN, "<", "$inFile") or die "Cannot open the input file: $!";

# open output file
my $outFile = "param_op_out.cmd";
if ( $ARGV[2] ne "" ) {
    $outFile = "$ARGV[2]";
}
open(OUT, ">", "$outFile") or die "Cannot open the output file: $!";

### }}}
### Read input file and insert pre-defined ops {{{

my @input;
while ( <IN> ) {
    s/\n//g;
    s/\r//g;
    s/\s+//;
    s/\s+/ /g;
    if ( $_ =~ /^PREDEF\((.+)\)/i ) {
        push(@input, @{$predef{$1}}) if exists $predef{$1};
    } else {
        push(@input, $_);
    }
}

### }}}
### Parse text {{{

if ( $debug ) {
    print "Input File:\n";
    print_readable @input;
    print "\n";
}

my $volt = "lv";
my $diff = "";

### Functions {{{
sub read_coords ($) {
    my $c_str = shift;
    my @ret = ();
    my $i = 0;
    while ( $c_str =~ /\((-?\d+\.?\d*),\s*(-?\d+\.?\d*)\)/g ) {
        $ret[$i]{x} = read_num($1);
        $ret[$i]{y} = read_num($2);
        $i++;
    }
    return \@ret;
}

sub mod_geom ($$) {
    my $offset = shift;
    my $gref = shift;
    my %tmp;
    if ( $gref->{t} eq "WIRE" ) {
        next if (($gref->{w} + 2*$offset) < 0);
        $tmp{t} = "WIRE";
        $tmp{w} = $gref->{w} + 2*$offset;
        @{$tmp{c}} = @{$gref->{c}};
    } elsif ( $gref->{t} eq "BOX" ) {
        next if (($gref->{w} + 2*$offset) < 0 || ($gref->{h} + 2*$offset) < 0);
        $tmp{t} = "BOX";
        $tmp{w} = $gref->{w} + 2*$offset;
        $tmp{h} = $gref->{h} + 2*$offset;
        @{$tmp{c}} = mod_box($offset, @{$gref->{c}});
    }
    return \%tmp;
}

sub sv {
    my $val = shift;
    if (ref($val) eq "HASH") {
        return sv($val->{$volt}) if (exists $val->{$volt});
        return sv($val->{$diff}) if (exists $val->{$diff});
        return sv($val->{tap})   if (exists $val->{tap});
        return 0.0;

      # my $ret = $val->{each %{$val}};
      # $_ < $ret and $ret = $_ for values %{$val};
      # return sv($ret);
    } else { return $val; }
}
### }}}

# Data Types: {{{
#   WIRE([WIDTH],[CLIST])
#   BOX([CLIST])

my $topmetal = 0;
my @data = ();
my $i = 0;
my $d = \%{$data[$i]};
foreach ( @input ) {
    if ( $_ =~ /^(WIRE|BOX)/i ) {
        if ( @data ) { $i++; }
        $d = \%{$data[$i]};
        $d->{t} = $1;
        ### WIRE {{{
        if ( $_ =~ /^WIRE\((\d+\.?\d*),\s*(.+)\)/i ) {
            $d->{w} = read_num($1);
            $d->{c} = read_coords($2);
        }
        ### }}}
        ### BOX {{{
        if ( $_ =~ /^BOX\((.+)\)/i ) {
            $d->{c} = read_coords($1);

            # sort coordinates
            if ( $d->{c}[0]{x} > $d->{c}[1]{x} ) {
                my $tmp       = $d->{c}[0]{x};
                $d->{c}[0]{x} = $d->{c}[1]{x};
                $d->{c}[1]{x} = $tmp;
            }
            if ( $d->{c}[0]{y} > $d->{c}[1]{y} ) {
                my $tmp       = $d->{c}[0]{y};
                $d->{c}[0]{y} = $d->{c}[1]{y};
                $d->{c}[1]{y} = $tmp;
            }

            $d->{w} = $d->{c}[1]{x} - $d->{c}[0]{x};
            $d->{h} = $d->{c}[1]{y} - $d->{c}[0]{y};
        }
        ### }}}
        next;
    } elsif ( $_ =~ /^TOPMETAL\((\d)\)/i ) {
        $topmetal = $1;
    } else {
        push( @{$d->{ops}}, $_ );
    }
}

### }}}

# Ops: {{{
#   PREDEF([TYPE])
#   ADD([LAYER],[OFFSET])
#   ENC([LAYER1],[LAYER2],[OFFSET])
#   FILL([CELL],[LAYER],[OFFSET])

print_readable \@data;

foreach my $d ( @data ) {
    if ( $debug ) {
        print "\nGeometry data:\n";
        print_readable $d;
        print "\n";
    }
    my %output = ();

    # set flags
    foreach ( @{$d->{ops}} ) {
        if ( $_ =~ /TGO/ ) { $volt = "hv"; }
        if ( $diff eq "" ) {
            if ( $_ =~ /NPLUS/ ) { $diff = "n"; }
            if ( $_ =~ /PPLUS/ ) { $diff = "p"; }
        }
    }
    if ( $debug ) {
        print "Flags: $diff $volt\n\n";
    }

### Output ops {{{
    foreach ( @{$d->{ops}} ) {
        ### ADD {{{
        if ( $_ =~ /^ADD\((\w+),?\s*(-?\d+\.?\d*)?\)/i ) {
            printf "Parsing: $_\n" if $debug;
            my $layer = uc($1);
            my $offset = 0;
            if ( defined $2 ) { $offset = read_num($2); }
            push(@{$output{$layer}}, mod_geom($offset, $d));
            next;
        }
        ### }}}
        ### ENC {{{
        if ( $_ =~ /^ENC\((\w+),\s*(\w+),?\s*(\d+\.?\d*)?\)/i ) {
            printf "Parsing: $_\n" if $debug;
            my $layer1 = uc($1);
            my $layer2 = "";
            if ( defined $2 ) { $layer2 = uc($2); }
            my $offset = 0;
            if ( exists $lib{$layer2}{enc}{$layer1} ) {
                $offset = sv($lib{$layer2}{enc}{$layer1});
            }
            if ( defined $3 ) { $offset = read_num($3); }

            # Add enclosing layer2 geometry around existing layer1 geometry
            my @layer2_out = ();
            if ( ref($output{$layer1}) eq "ARRAY" ) {
                push(@layer2_out, mod_geom($offset, $_)) foreach (@{$output{$layer1}});
            }

            # Add layer1 geometry inside existing layer2 geometry
            $offset *= -1;
            my @layer1_out = ();
            if ( ref($output{$layer2}) eq "ARRAY" ) {
                push(@layer1_out, mod_geom($offset, $_)) foreach (@{$output{$layer2}});
            }

            if ( @layer1_out ) { push(@{$output{$layer1}}, @layer1_out); }
            if ( @layer2_out ) { push(@{$output{$layer2}}, @layer2_out); }
        }
        ### }}}
        ### FILL {{{
        if ( $_ =~ /^FILL\((\w+),?\s*(\w+)?,?\s*(-?\d+\.?\d*)?\)/i ) {
            printf "Parsing: $_:\n" if $debug;
            my $cell = uc($1);
            my $layer = "";

            my $clib = $cell;
            if ( !exists $lib{$clib} ) {
                if ( $clib =~ /(\w+)(\d)/ ) {
                    $clib = ($topmetal && $2 == ($topmetal - 1)) ? "$1T" : "$1n";
                    next if ( !exists $lib{$clib} );
                } else { next; }
            }

            print "cell = $clib\n";

            if ( defined $2 ) { $layer = uc($2); }

            my $llib = "";
            if ( $layer ) {
                $llib = $layer;
                if ( !exists $lib{$llib} ) {
                    if ( $llib =~ /(\w+)(\d)/ ) {
                        $llib = ($topmetal && $2 == $topmetal) ? "$1T" : "$1n";
                        next if ( !exists $lib{$llib} );
                    } else { next; }
                }
            }

            my $offset = 0;
            if ( $llib && exists $lib{$llib}{enc}{$clib} ) {
                $offset = -1 * sv($lib{$llib}{enc}{$clib});
            }
            if ( defined $3 ) { $offset = read_num($3); }

            my $cell_s = $lib{$clib}{s};

            my @op_geom = ();
            if ( $layer ) { push(@op_geom, @{$output{$layer}}); }
            else { push(@op_geom, mod_geom(0, $d)); }

            foreach (@op_geom) {
                my %area = %{mod_geom($offset, $_)};
                if ( $_->{t} eq "WIRE" ) {
                    my $cell_spc = 0;
                    my $n = 0;
                    foreach my $i (sort keys %{$lib{$clib}{spc}{$clib}}) {
                        if ($n >= $i) {
                            $cell_spc = $lib{$clib}{spc}{$clib}{$i};
                            $n = int(($area{w} + $cell_spc) / ($cell_s + $cell_spc));
                        }
                    }

                    next if ($n == 0);

                    my $cell_p = $cell_s + $cell_spc;
                    my $as = ($n - 1) * $cell_p + $cell_s;

                    $area{w} = $as;

                    my @c = @{$area{c}};

                    # arrays at each corner
                    foreach my $ii (0 .. $#c) {
                        my $pi = ($ii - 1 < 0) ? 0 : $ii - 1;
                        my $ni = ($ii + 1 > $#c) ? $#c : $ii + 1;

                        next if (($c[$ii]{x} != $c[$pi]{x} && $c[$ii]{y} != $c[$pi]{y}) ||
                                 ($c[$ii]{x} != $c[$ni]{x} && $c[$ii]{y} != $c[$ni]{y}));

                        my %n = ( "x" => $n, "y" => $n );

                        my %pos = (
                            "x" => $c[$ii]{x} - int($as/2),
                            "y" => $c[$ii]{y} - int($as/2)
                        );

                        my $px = "";
                        if    ($c[$pi]{y} != $c[$ii]{y}) { $px = "y"; }
                        elsif ($c[$pi]{x} != $c[$ii]{x}) { $px = "x"; }

                        if ($px) {
                            next if (abs($c[$pi]{$px} - $c[$ii]{$px}) < ($as + $cell_spc));
                        }

                        my $nx = "";
                        if    ($c[$ii]{y} != $c[$ni]{y}) { $nx = "y"; }
                        elsif ($c[$ii]{x} != $c[$ni]{x}) { $nx = "x"; }

                        if ($nx && abs($c[$ii]{$nx} - $c[$ni]{$nx}) < ($as + $cell_spc)) {
                            my $dist = abs($c[$ii]{$nx} - $c[$ni]{$nx});
                            $n{$nx} = int(($dist + $area{w} + $cell_spc) / $cell_p);

                            $pos{$nx} = int(min($c[$ii]{$nx}, $c[$ni]{$nx})
                                + ($dist - ($n{$nx} - 1) * $cell_p - $cell_s)/2);
                        }

                        print OUT draw_array($cell{$cell}{name}, $n{x}, $n{y}, $cell_p, $cell_p,
                            ax($pos{x} + $cell_s/2, $cell_s/2, $cell{$cell}{align}),
                            ay($pos{y} + $cell_s/2, $cell_s/2, $cell{$cell}{align}));
                    }

                    # arrays along each line segment
                    foreach my $ii (0 .. $#c - 1) {
                        my $pi = ($ii - 1 < 0) ? 0 : $ii - 1;
                        my $ni = $ii + 1;
                        my $nn = ($ii + 2 > $#c) ? $#c : $ii + 2;

                        my %n      = ( "x" => 0, "y" => 0 );
                        my %step   = ( "x" => 0, "y" => 0 );
                        my %pos    = ( "x" => 0, "y" => 0 );
                        my %offset = ( "x" => 0, "y" => 0 );

                        my $x = ""; my $y = "";
                        if    ($c[$ii]{y} == $c[$ni]{y}) { $x = "x"; $y = "y"; }
                        elsif ($c[$ii]{x} == $c[$ni]{x}) { $x = "y"; $y = "x"; }
                        else { next; }

                        my $dist = abs($c[$ii]{$x} - $c[$ni]{$x}) - $as;

                        # cell fill fudge factors
                        my $filln = ($c[$ni]{$x} != $c[$nn]{$x} && $c[$ni]{$y} != $c[$nn]{$y}) ? 1 : 0;
                        my $fillp = ($c[$ii]{$x} != $c[$pi]{$x} && $c[$ii]{$y} != $c[$pi]{$y}) ? 1 : 0;

                        my $fillAdjust = int($area{w} * (1 - tan($pi/2))/2);
                        $dist += ($filln + $fillp) * $fillAdjust;
                        next if ($dist < ($cell_s + 2 * $cell_spc));

                        if ($filln && $c[$ii]{$x} > $c[$ni]{$x}) { $offset{$x} -= $fillAdjust; }
                        if ($fillp && $c[$ii]{$y} > $c[$ni]{$y}) { $offset{$y} -= $fillAdjust; }

                        $n{$x} = int(($dist - $cell_spc) / $cell_p);
                        $n{$y} = $n;

                        $step{$x} = ($n{$x} > 1) ? int(($dist - $cell_spc) / $n{$x}) : 0;
                        $step{$y} = $cell_p;

                        $pos{$x} = int(min($c[$ii]{$x}, $c[$ni]{$x}) + $as/2
                            + ($dist - ($n{$x} - 1) * $step{$x} - $cell_s)/2);
                        $pos{$y} = int($c[$ii]{$y} - $as/2);

                        $pos{x} += $offset{x};
                        $pos{y} += $offset{y};

                        print OUT draw_array($cell{$cell}{name}, $n{x}, $n{y}, $step{x}, $step{y},
                            ax($pos{x} + $cell_s/2, $cell_s/2, $cell{$cell}{align}),
                            ay($pos{y} + $cell_s/2, $cell_s/2, $cell{$cell}{align}));
                    }
                    print "  Wire fill x$n\n" if $debug;
                }
                if ( $_->{t} eq "BOX" ) {
                    my $cell_spc = 0;
                    my %n = ( "x" => 0, "y" => 0 );
                    foreach my $i (sort keys %{$lib{$clib}{spc}{$clib}}) {
                        if ($n{x} >= $i && $n{y} >= $i) {
                            $cell_spc = $lib{$clib}{spc}{$clib}{$i};
                            $n{x} = int(($area{w} + $cell_spc) / ($cell_s + $cell_spc));
                            $n{y} = int(($area{h} + $cell_spc) / ($cell_s + $cell_spc));
                        }
                    }

                    next if ($n{x} == 0 || $n{y} == 0);

                    my $cell_p = $cell_s + $cell_spc;
                    my %as = (
                        "x" => ($n{x} - 1) * $cell_p + $cell_s,
                        "y" => ($n{y} - 1) * $cell_p + $cell_s,
                    );

                    $area{c}[0]{x} += floor(($area{w} - $as{x})/2);
                    $area{c}[0]{y} += floor(($area{h} - $as{y})/2);
                    $area{c}[1]{x} -= ceil(($area{w} - $as{x})/2);
                    $area{c}[1]{y} -= ceil(($area{h} - $as{y})/2);

                    ($area{w}, $area{h}) = ($as{x}, $as{y});

                    print OUT draw_array($cell{$cell}{name}, $n{x}, $n{y}, $cell_p, $cell_p,
                        ax($area{c}[0]{x} + $cell_s/2, $cell_s/2, $cell{$cell}{align}),
                        ay($area{c}[0]{y} + $cell_s/2, $cell_s/2, $cell{$cell}{align}));

                    print "  Box fill $n{x}x$n{y}\n" if $debug;
                }
                $area{dummy} = 1;
                push(@{$output{$cell}}, \%area);
            }
        }
        ### }}}
    }
### }}}
### Write Output to file {{{
    foreach my $l ( keys %output ) {
        foreach ( @{$output{$l}} ) {
            next if $_->{dummy};
            if ( $_->{t} eq "WIRE" ) {
                print OUT draw_wire($l, $_->{w}, @{$_->{c}});
            }
            if ( $_->{t} eq "BOX" ) {
                print OUT draw_box($l, @{$_->{c}});
            }
        }
    }
### }}}
}

### }}}

