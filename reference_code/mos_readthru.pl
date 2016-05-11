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

#print_readable \%lib;
#print_readable \%cell;
#print_readable \%mos;

### }}}
### Load user input {{{

# Input string:
# type:l:w:name:ngtc:ngbc:ndc:nsc
# type: device type -> n|p|nhv|phv (required)
# l:    length (required)
# w:    width (defaults to tech specific)
# name: cell name (defaults to (n|p)mos[hv]_(l)x(w))
# ngtc: number of gate contact rows at the top (default 1)
# ngbc: number of gate contact rows at the bottom (default 1)
# ndc:  number of contact columns on the right/drain (default 1)
# nsc:  number of contact columns on the left/source (default 1)

if ( $ARGV[1] eq "" ) {
    print "Requires input string!\n";
    print "Input string: 'type:l:w:name:ngtc:ngbc:ndc:nsc'\n";
    print "\ttype: device type -> n|p|nhv|phv (required)\n";
    print "\tw:    width in um (required)\n";
    print "\tl:    length in um (defaults to tech specific)\n";
    print "\tname: cell name (defaults to (n|p)mos[hv]_(l)x(w))\n";
    print "\tntc:  number of gate contact rows at the top (default 1)\n";
    print "\tnbc:  number of gate contact rows at the bottom (default 1)\n";
    print "\tnsc:  number of contact columns on the left/source (default 1)\n";
    print "\tndc:  number of contact columns on the right/drain (default 1)\n";
    exit;
}

my @input = split( ':', lc($ARGV[1]) );
my %dev = ();

# Device type
if ( defined($input[0]) && $input[0] =~ /^(n|p)(hv)?$/ ) {
    $dev{type} = $1;
    $dev{v} = ( defined($2) && $2 eq "hv" ) ? "hv" : "lv";
} else {
    print "Device type must be n|p|nhv|phv\n";
    exit;
}

# Device width
if ( defined($input[1]) && $input[1] =~ /^(\d+\.?\d*|\d*\.\d+)$/ ) {
    $dev{w} = read_num($input[1]);
} else {
    print "Valid device width is required\n";
    exit;
}

# Device length
if ( defined($input[2]) && $input[2] =~ /^(\d+\.?\d*|\d*\.\d+)$/ ) {
    $dev{l} = read_num($input[2]);
    if ( $dev{l} < sv($lib{GATE}{w}) ) { $dev{l} = sv($lib{GATE}{w}); }
} else {
    $dev{l} = sv($lib{GATE}{w});
}

# Cell name
if ( defined($input[3]) && $input[3] =~ /^\S/ ) {
    $dev{name} = uc($input[3]);
} else {
    $dev{name} = "";
}

if ( $dev{name} eq "" or $dev{name} =~ /^_/ ) {
    my $post = "";
    if ( $dev{name} =~ /^_/ ) {
        $post = $dev{name};
    }

    my $w = write_num($dev{w});
    my $l = write_num($dev{l});
    if ($w < 1) { $w *= 1000; ($w = "$w"); } else { ($w = sprintf("%.3f", $w)) =~ s/\./p/; $w =~ s/p0+$//; }
    if ($l < 1) { $l *= 1000; ($l = "$l"); } else { ($l = sprintf("%.3f", $l)) =~ s/\./p/; $l =~ s/p0+$//; }

    $dev{name}  = $dev{type} ."MOS". $dev{v};
    $dev{name} .= "_". $w .($dev{w} > read_num(1) ? "u" : "n");
    $dev{name} .= "x". $l .($dev{l} > read_num(1) ? "u" : "n");
    $dev{name} .= $post;
    $dev{name}  = uc($dev{name});
}

$dev{ntc} = (defined($input[4]) && $input[4] =~ /^\d+$/) ? $input[4] : 1; # Top gate contacts
$dev{nbc} = (defined($input[5]) && $input[5] =~ /^\d+$/) ? $input[5] : 1; # Bottom gate contacts
$dev{nsc} = (defined($input[6]) && $input[6] =~ /^\d+$/) ? $input[6] : 1; # Source/left contacts
$dev{ndc} = (defined($input[7]) && $input[7] =~ /^\d+$/) ? $input[7] : 1; # Drain/right contacts

#print_readable %device;

### }}}
### Functions {{{

sub sv {
    my $val = shift;
    if (ref($val) eq "HASH") {
        if ( exists $val->{$dev{v}}    ) { return sv($val->{$dev{v}});    }
        if ( exists $val->{$dev{type}} ) { return sv($val->{$dev{type}}); }
    } else { return $val; }
}

#Is this used at any point?
sub copy_geom {
    my @cl = ();
    my @in = @_;

    foreach my $i (0 .. $#in) {
        $cl[$i]{x} = $in[$i]{x};
        $cl[$i]{y} = $in[$i]{y};
    }

    return @cl;
}

### }}}
### Output device {{{

my $file_out = "MOS_OUT.CMD";

open( OUT, '>', "$file_out" ) or die "Error writing to output file ($file_out)\n";

print OUT "XSELECT OFF\n";
print OUT edit_temp();

my $g_dist  = $dev{l} - 2 * sv($lib{GATE}{enc}{CT}); #why is sv necessary?
my $sd_dist = $dev{w} - 2 * $lib{ACT}{enc}{CT}{def};

### Contact array info {{{

my $ct_s = $lib{CT}{s};
my %ct_spc = (
    "t" => $lib{CT}{spc}{CT}{0},
    "b" => $lib{CT}{spc}{CT}{0},
    "s" => $lib{CT}{spc}{CT}{0},
    "d" => $lib{CT}{spc}{CT}{0},
);
my %n = (
    "t" => ($g_dist  < $ct_s) ? 1 : int(($g_dist  + $ct_spc{t}) / ($ct_s + $ct_spc{t})),
    "b" => ($g_dist  < $ct_s) ? 1 : int(($g_dist  + $ct_spc{b}) / ($ct_s + $ct_spc{b})),
    "s" => ($sd_dist < $ct_s) ? 1 : int(($sd_dist + $ct_spc{s}) / ($ct_s + $ct_spc{s})),
    "d" => ($sd_dist < $ct_s) ? 1 : int(($sd_dist + $ct_spc{d}) / ($ct_s + $ct_spc{d})),
);
foreach my $i (keys %{$lib{CT}{spc}{CT}}) {
    if ( $dev{ntc} >= $i && $n{t} >= $i ) { $ct_spc{t} = $lib{CT}{spc}{CT}{$i}; }
    if ( $dev{ndc} >= $i && $n{b} >= $i ) { $ct_spc{b} = $lib{CT}{spc}{CT}{$i}; }
    if ( $dev{nsc} >= $i && $n{s} >= $i ) { $ct_spc{s} = $lib{CT}{spc}{CT}{$i}; }
    if ( $dev{ndc} >= $i && $n{d} >= $i ) { $ct_spc{d} = $lib{CT}{spc}{CT}{$i}; }
}
my %ct_p = (
    "t" => $ct_s + $ct_spc{t},
    "b" => $ct_s + $ct_spc{b},
    "s"  => $ct_s + $ct_spc{s},
    "d"  => $ct_s + $ct_spc{d},
);

### }}}
### Print device info {{{

print "Generating mosfet device:\n";
print "  Cell name : ".$dev{name}."\n";
print "  Width     : ".write_num($dev{w})."um\n";
print "  Length    : ".write_num($dev{l})."um\n";
print "\n";
print "  Extra :\n";
print "    Gate contacts (Top)      : ".(($dev{ntc}) ? $n{t}."x".$dev{ntc} : "N/A")."\n";
print "    Gate contacts (Bottom)   : ".(($dev{nbc}) ? $n{b}."x".$dev{nbc} : "N/A")."\n";
print "    Active contacts (Source) : ".(($dev{nsc}) ? $n{s}."x".$dev{nsc} : "N/A")."\n";
print "    Active contacts (Drain)  : ".(($dev{ndc}) ? $n{d}."x".$dev{ndc} : "N/A")."\n";
print "\n";

### }}}
### GATE top/bottom extension {{{

my $gate_t_ext = 0;
if ( $dev{ntc} < 1 ) {
    $gate_t_ext += sv($lib{GATE}{ext}{ACT});
} else {
    $gate_t_ext += $dev{ntc} * $ct_p{t} - $ct_spc{t};
    $gate_t_ext += sv($lib{GATE}{enc}{CT});
    $gate_t_ext += (sv($lib{CT}{spc}{ACT}) > sv($lib{GATE}{enc}{CT}) + sv($lib{GATE}{spc}{ACT}))
                  ? sv($lib{CT}{spc}{ACT}) : sv($lib{GATE}{enc}{CT}) + sv($lib{GATE}{spc}{ACT});
}
my $gate_b_ext = 0;
if ( $dev{nbc} < 1 ) {
    $gate_b_ext += sv($lib{GATE}{ext}{ACT});
} else {
    $gate_b_ext += $dev{nbc} * $ct_p{b} - $ct_spc{b};
    $gate_b_ext += sv($lib{GATE}{enc}{CT});
    $gate_b_ext += (sv($lib{CT}{spc}{ACT}) > sv($lib{GATE}{enc}{CT}) + sv($lib{GATE}{spc}{ACT}))
                  ? sv($lib{CT}{spc}{ACT}) : sv($lib{GATE}{enc}{CT}) + sv($lib{GATE}{spc}{ACT});
}

### }}}
### ACT source/drain extension {{{

my $act_l_ext = ($dev{nsc} < 1) ? sv($lib{ACT}{ext}{GATE})
              : ( sv($lib{CT}{spc}{GATE}) + $lib{ACT}{enc}{CT}{def}
                + $dev{nsc} * $ct_s + ($dev{nsc} - 1) * $ct_spc{s} );
my $act_r_ext = ($dev{ndc} < 1) ? sv($lib{ACT}{ext}{GATE})
              : ( sv($lib{CT}{spc}{GATE}) + $lib{ACT}{enc}{CT}{def}
                + $dev{ndc} * $ct_s + ($dev{ndc} - 1) * $ct_spc{d} );

### }}}
### N+/P+ top/bottom extension {{{

my $imp_layer = ($dev{type} eq "n") ? "NPLUS" : "PPLUS";
my $imp_t_ext = ($gate_t_ext > sv($lib{$imp_layer}{enc}{ACT}{end}))
               ? $gate_t_ext : sv($lib{$imp_layer}{enc}{ACT}{end});
my $imp_b_ext = ($gate_b_ext > sv($lib{$imp_layer}{enc}{ACT}{end}))
               ? $gate_b_ext : sv($lib{$imp_layer}{enc}{ACT}{end});

### }}}
### Draw polygons {{{

# Draw gate
print "Drawing gate ...\n";
my @gate_box = ();
$gate_box[0]{x} = 0;
$gate_box[0]{y} = -1*$gate_b_ext;
$gate_box[1]{x} = $dev{l};
$gate_box[1]{y} = $gate_t_ext + $dev{w};
print OUT draw_box( "GATE", @gate_box );

# Draw active area
print "Drawing active area ...\n";
my @act_box = ();
$act_box[0]{x} = -1*$act_l_ext;
$act_box[0]{y} = 0;
$act_box[1]{x} = $dev{l} + $act_r_ext;
$act_box[1]{y} = $dev{w};
print OUT draw_box( "ACT", @act_box );

# Draw N+/P+ area
print "Drawing diffusion ($imp_layer) ...\n";
my @imp_box = ();
$imp_box[0]{x} = $act_box[0]{x} - sv($lib{$imp_layer}{enc}{ACT}{def});
$imp_box[0]{y} = $act_box[0]{y} - $imp_b_ext;
$imp_box[1]{x} = $act_box[1]{x} + sv($lib{$imp_layer}{enc}{ACT}{def});
$imp_box[1]{y} = $act_box[1]{y} + $imp_t_ext;
print OUT draw_box( $imp_layer, @imp_box );

### }}}
### Add contacts {{{

my %gcn  = ();
my %sdcn = ();

my $ct_name  = $cell{CT}{name};
my $ct_align = $cell{CT}{align};

# Add source/drain contact arrays and metal
if ( $sd_dist >= $ct_s ) {
    my %sd_distn = (
        "s" => $n{s} * $ct_s + ($n{s} - 1) * $ct_spc{s},
        "d" => $n{d} * $ct_s + ($n{d} - 1) * $ct_spc{d},
    );

    my %y = (
        "s" => $lib{ACT}{enc}{CT}{def} + $ct_s/2,
        "d" => $lib{ACT}{enc}{CT}{def} + $ct_s/2,
    );
    if ( ($dev{ntc} > 0 && $dev{nbc} > 0) || ($dev{ntc} < 1 && $dev{nbc} < 1) ) {
        $y{s} += int(($sd_dist - $sd_distn{s}) / 2);
        $y{d} += int(($sd_dist - $sd_distn{d}) / 2);
    } elsif ( $dev{nbc} > 0 ) {
        $y{s} += $sd_dist - $sd_distn{s};
        $y{d} += $sd_dist - $sd_distn{d};
    }

    # source
    if ( $dev{nsc} > 0 ) {
        print "Adding source contacts ...\n";
        my $x = -1*sv($lib{CT}{spc}{GATE});
        $x -= $ct_s/2;
        $x -= ($dev{nsc} - 1) * $ct_p{s};
        print OUT draw_array( $ct_name, $dev{nsc}, $n{s}, $ct_p{s}, $ct_p{s},
            ax($x, $ct_s/2, $ct_align), ay($y{s}, $ct_s/2, $ct_align));

        my @m1_box = ();
        $m1_box[0]{x} = $x    - $ct_s/2 - $lib{M1}{enc}{CT};
        $m1_box[0]{y} = $y{s} - $ct_s/2 - $lib{M1}{enc}{CT};
        $m1_box[1]{x} = $x    + $ct_s/2 + $lib{M1}{enc}{CT} + ($dev{nsc} - 1) * $ct_p{s};
        $m1_box[1]{y} = $y{s} + $ct_s/2 + $lib{M1}{enc}{CT} + ($n{s} - 1) * $ct_p{s};
        print OUT draw_box( "M1", @m1_box );
    }

    # drain
    if ( $dev{ndc} > 0 ) {
        print "Adding drain contacts ...\n";
        my $x = $dev{l};
        $x += sv($lib{CT}{spc}{GATE});
        $x += $ct_s/2;
        print OUT draw_array( $ct_name, $dev{ndc}, $n{d}, $ct_p{d}, $ct_p{d},
            ax($x, $ct_s/2, $ct_align), ay($y{d}, $ct_s/2, $ct_align));

        my @m1_box = ();
        $m1_box[0]{x} = $x    - $ct_s/2 - $lib{M1}{enc}{CT};
        $m1_box[0]{y} = $y{d} - $ct_s/2 - $lib{M1}{enc}{CT};
        $m1_box[1]{x} = $x    + $ct_s/2 + $lib{M1}{enc}{CT} + ($dev{ndc} - 1) * $ct_p{d};
        $m1_box[1]{y} = $y{d} + $ct_s/2 + $lib{M1}{enc}{CT} + ($n{d} - 1) * $ct_p{d};
        print OUT draw_box( "M1", @m1_box );
    }
}

# Add top/bottom gate end contact arrays and metal
{
    my %g_distn = (
        "t" => $n{t} * $ct_s + ($n{t} - 1) * $ct_spc{t},
        "b" => $n{b} * $ct_s + ($n{b} - 1) * $ct_spc{b},
    );

    my %x = (
        "t" => sv($lib{GATE}{enc}{CT}) + $ct_s/2 + int(($g_dist - $g_distn{t}) / 2),
        "b" => sv($lib{GATE}{enc}{CT}) + $ct_s/2 + int(($g_dist - $g_distn{b}) / 2),
    );

    # top
    if ( $dev{ntc} > 0 ) {
        print "Adding top gate contacts ...\n";
        my $y = 0;
        $y += (sv($lib{CT}{spc}{ACT}) > sv($lib{GATE}{enc}{CT}) + sv($lib{GATE}{spc}{ACT}))
             ? sv($lib{CT}{spc}{ACT}) : sv($lib{GATE}{enc}{CT}) + sv($lib{GATE}{spc}{ACT});
        $y += $ct_s/2;
        $y += $dev{w};
        print OUT draw_array( $ct_name, $n{t}, $dev{ntc}, $ct_p{t}, $ct_p{t},
            ax($x{t}, $ct_s/2, $ct_align), ay($y, $ct_s/2, $ct_align));

        my @m1_box = ();
        $m1_box[0]{x} = $x{t} - $ct_s/2 - $lib{M1}{enc}{CT};
        $m1_box[0]{y} = $y    - $ct_s/2 - $lib{M1}{enc}{CT};
        $m1_box[1]{x} = $x{t} + $ct_s/2 + $lib{M1}{enc}{CT} + ($n{t} - 1) * $ct_p{t};
        $m1_box[1]{y} = $y    + $ct_s/2 + $lib{M1}{enc}{CT} + ($dev{ntc} - 1) * $ct_p{t};
        print OUT draw_box( "M1", @m1_box );

        if ( $g_dist < $ct_s + 2 * $lib{GATE}{enc}{CT} ) {
            my @gate_box = ();
            $gate_box[0]{x} = $x{t} - $ct_s/2 - $lib{GATE}{enc}{CT};
            $gate_box[0]{y} = $y    - $ct_s/2 - $lib{GATE}{enc}{CT};
            $gate_box[1]{x} = $x{t} + $ct_s/2 + $lib{GATE}{enc}{CT} + ($n{t} - 1) * $ct_p{t};
            $gate_box[1]{y} = $y    + $ct_s/2 + $lib{GATE}{enc}{CT} + ($dev{ntc} - 1) * $ct_p{t};
            print OUT draw_box( "GATE", @gate_box );
        }
    }

    # bottom
    if ( $dev{nbc} > 0 ) {
        print "Adding bottom gate contacts ...\n";
        my $y = 0;
        $y -= (sv($lib{CT}{spc}{ACT}) > sv($lib{GATE}{enc}{CT}) + sv($lib{GATE}{spc}{ACT}))
             ? sv($lib{CT}{spc}{ACT}) : sv($lib{GATE}{enc}{CT}) + sv($lib{GATE}{spc}{ACT});
        $y -= $ct_s/2;
        $y -= ($dev{nbc} - 1) * $ct_p{b};
        print OUT draw_array( $ct_name, $n{b}, $dev{nbc}, $ct_p{b}, $ct_p{b},
            ax($x{b}, $ct_s/2, $ct_align), ay($y, $ct_s/2, $ct_align));

        my @m1_box = ();
        $m1_box[0]{x} = $x{b} - $ct_s/2 - $lib{M1}{enc}{CT};
        $m1_box[0]{y} = $y    - $ct_s/2 - $lib{M1}{enc}{CT};
        $m1_box[1]{x} = $x{b} + $ct_s/2 + $lib{M1}{enc}{CT} + ($n{b} - 1) * $ct_p{b};
        $m1_box[1]{y} = $y    + $ct_s/2 + $lib{M1}{enc}{CT} + ($dev{nbc} - 1) * $ct_p{b};
        print OUT draw_box( "M1", @m1_box );

        if ( $g_dist < $ct_s + 2 * $lib{GATE}{enc}{CT} ) {
            my @gate_box = ();
            $gate_box[0]{x} = $x{b} - $ct_s/2 - $lib{GATE}{enc}{CT};
            $gate_box[0]{y} = $y    - $ct_s/2 - $lib{GATE}{enc}{CT};
            $gate_box[1]{x} = $x{b} + $ct_s/2 + $lib{GATE}{enc}{CT} + ($n{b} - 1) * $ct_p{b};
            $gate_box[1]{y} = $y    + $ct_s/2 + $lib{GATE}{enc}{CT} + ($dev{nbc} - 1) * $ct_p{b};
            print OUT draw_box( "GATE", @gate_box );
        }
    }
}

### }}}
### Parse tech specific additions {{{

my $dt = $dev{type};
my $dv = $dev{v};

### Setup geometry {{{

my %geom = ();

$geom{sd}[0][0]{x} = $act_box[0]{x};
$geom{sd}[0][0]{y} = $act_box[0]{y};
$geom{sd}[0][1]{x} = $gate_box[0]{x};
$geom{sd}[0][1]{y} = $act_box[1]{y};

$geom{sd}[1][0]{x} = $gate_box[1]{x};
$geom{sd}[1][0]{y} = $act_box[0]{y};
$geom{sd}[1][1]{x} = $act_box[1]{x};
$geom{sd}[1][1]{y} = $act_box[1]{y};

$geom{gate}[0]{x} = $gate_box[0]{x};
$geom{gate}[0]{y} = $gate_box[0]{y};
$geom{gate}[1]{x} = $gate_box[1]{x};
$geom{gate}[1]{y} = $gate_box[1]{y};

$geom{body}[0]{x} = $act_box[0]{x};
$geom{body}[0]{y} = $act_box[0]{y};
$geom{body}[1]{x} = $act_box[1]{x};
$geom{body}[1]{y} = $act_box[1]{y};

$geom{all}[0]{x} = $act_box[0]{x};
$geom{all}[0]{y} = $gate_box[0]{y};
$geom{all}[1]{x} = $act_box[1]{x};
$geom{all}[1]{y} = $gate_box[1]{y};

### }}}
### Parse ops {{{

foreach my $k ( keys %geom ) {
    my %output = ();
    my @ops = ();

    print "Parsing ".uc($k)." ops:\n";

    push( @ops, @{$mos{all}{$k}} ) if ( ref($mos{all}{$k}) eq "ARRAY" );
    push( @ops, @{$mos{$dv}{$k}} ) if ( ref($mos{$dv}{$k}) eq "ARRAY" );

    if ( ref($mos{all}{$k}) eq "HASH" ) {
        push( @ops, @{$mos{all}{$k}{all}} );
        push( @ops, @{$mos{all}{$k}{$dt}} );
    }
    if ( ref($mos{$dv}{$k}) eq "HASH" ) {
        push( @ops, @{$mos{$dv}{$k}{all}} );
        push( @ops, @{$mos{$dv}{$k}{$dt}} );
    }

    foreach my $op ( @ops ) {
        print $op."\n";
        if ( $op =~ /ADD\((\w+)\)/i ) {
            if ( $k eq "sd" ) {
                push( @{$output{$k}{$1}}, $geom{$k}[0] );
                push( @{$output{$k}{$1}}, $geom{$k}[1] );
            } else {
                push( @{$output{$k}{$1}}, $geom{$k} );
            }
        }
        if ( $op =~ /ENC\((\w+)\)/i ) {
            my @offset = ();

            if ( $k eq "sd" ) {
                next if ( !exists $lib{$1}{enc}{ACT} );

                $offset[0] = sv($lib{$1}{enc}{ACT});
                $offset[1] = 0;
            } elsif ( $k eq "gate" ) {
                next if ( !exists $lib{$1}{enc}{GATE} );

                $offset[0] = sv($lib{$1}{enc}{GATE});
                $offset[1] = sv($lib{$1}{enc}{GATE});
            } elsif ( $k eq "body" ) {
                next if ( !exists $lib{$1}{enc}{ACT} );

                $offset[0] = sv($lib{$1}{enc}{ACT});
                $offset[1] = sv($lib{$1}{enc}{ACT});
            } elsif ( $k eq "all" ) {
                next if ( !exists $lib{$1}{enc}{GATE} && !exists $lib{$1}{enc}{ACT} );

                $offset[0] = (exists $lib{$1}{enc}{ACT} ) ? sv($lib{$1}{enc}{ACT} ) : 0;
                $offset[1] = (exists $lib{$1}{enc}{GATE}) ? sv($lib{$1}{enc}{GATE}) : 0;
            }

            my @tmp = ();
            if ( $k eq "sd" ) {
                $tmp[0][0]{x} = $geom{$k}[0][0]{x} - $offset[0];
                $tmp[0][0]{y} = $geom{$k}[0][0]{y} - $offset[0];
                $tmp[0][1]{x} = $geom{$k}[0][1]{x};
                $tmp[0][1]{y} = $geom{$k}[0][1]{y} + $offset[0];

                $tmp[1][0]{x} = $geom{$k}[1][0]{x};
                $tmp[1][0]{y} = $geom{$k}[1][0]{y} - $offset[0];
                $tmp[1][1]{x} = $geom{$k}[1][1]{x} + $offset[0];
                $tmp[1][1]{y} = $geom{$k}[1][1]{y} + $offset[0];

                push( @{$output{$k}{$1}}, $tmp[0] );
                push( @{$output{$k}{$1}}, $tmp[1] );
            } else {
                $tmp[0]{x} = $geom{$k}[0]{x} - $offset[0];
                $tmp[0]{y} = $geom{$k}[0]{y} - $offset[1];
                $tmp[1]{x} = $geom{$k}[1]{x} + $offset[0];
                $tmp[1]{y} = $geom{$k}[1]{y} + $offset[1];

                push( @{$output{$k}{$1}}, \@tmp );
            }

        }
        if ( $op =~ /ENC\((\w+),\s*(\w+)\)/i ) {
            next if ( !exists $output{$k}{$1} || !exists $lib{$2}{enc}{$1} );

            my $offset = sv($lib{$2}{enc}{$1});

            my @tmp = ();
            if ( $k eq "sd" ) {
                my $i = $#{$output{$k}{$1}};
                my $p = $i - 1;
                $tmp[0][0]{x} = $output{$k}{$1}[$i][0]{x} - $offset;
                $tmp[0][0]{y} = $output{$k}{$1}[$i][0]{y} - $offset;
                $tmp[0][1]{x} = $output{$k}{$1}[$i][1]{x};
                $tmp[0][1]{y} = $output{$k}{$1}[$i][1]{y} + $offset;

                $tmp[1][0]{x} = $output{$k}{$1}[$p][0]{x};
                $tmp[1][0]{y} = $output{$k}{$1}[$p][0]{y} - $offset;
                $tmp[1][1]{x} = $output{$k}{$1}[$p][1]{x} + $offset;
                $tmp[1][1]{y} = $output{$k}{$1}[$p][1]{y} + $offset;

                push( @{$output{$k}{$2}}, $tmp[0] );
                push( @{$output{$k}{$2}}, $tmp[1] );
            } else {
                my $i = $#{$output{$k}{$1}};
                $tmp[0]{x} = $output{$k}{$1}[$i][0]{x} - $offset;
                $tmp[0]{y} = $output{$k}{$1}[$i][0]{y} - $offset;
                $tmp[1]{x} = $output{$k}{$1}[$i][1]{x} + $offset;
                $tmp[1]{y} = $output{$k}{$1}[$i][1]{y} + $offset;

                push( @{$output{$k}{$2}}, \@tmp );
            }
        }
    }

    foreach my $k ( %output ) {
        foreach my $l ( %{$output{$k}} ) {
            foreach my $cl ( @{$output{$k}{$l}} ) {
                print OUT draw_box( $l, @{$cl} );
            }
        }
    }
}

### }}}

### }}}

# Group, exit, and add cell
print OUT "EXIT ; UNSELECT ALL\n";
print OUT add_temp( $dev{name} );
print OUT "DELETE\n";
print OUT "ADD CELL ". $dev{name} ."\n";

### }}}

