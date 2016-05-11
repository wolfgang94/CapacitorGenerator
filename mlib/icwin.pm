package mlib::icwin;

use strict;
use warnings;
use base 'Exporter';
use bignum;
use POSIX;

our @EXPORT = (
    'read_num', 'write_num', 'write_coord',
    'parse_lib', 'ax', 'ay', 'mod_box',
    'draw_box', 'draw_polygon', 'draw_wire', 'draw_array',
    'edit_temp', 'add_temp',
);

### ICWIN Functios {{{

{
    my $step = 0.005;

    sub read_num ($) {
        my $a = shift;
        return int(sprintf("%.3f", $a)/$step);
    }

    sub write_num ($) {
        my $a = shift;
        return sprintf("%.3f", $a*$step);
    }
}

sub write_coord {
    my $c = shift;

    if    (ref($c) =~ /ARRAY/) { return sprintf( "(%.3f,%.3f) ", write_num($c->[0]), write_num($c->[1]) ) ; }
    elsif (ref($c) =~ /HASH/ ) { return sprintf( "(%.3f,%.3f) ", write_num($c->{x}), write_num($c->{y}) ) ; }
    else { return "" ; }
}


sub parse_lib {
    my $in = shift;
    if (ref($in) eq "HASH") {
        foreach my $k (keys %{$in}) {
            if (ref($in->{$k}) eq "HASH") {
                parse_lib($in->{$k});
            } else {
                $in->{$k} = read_num($in->{$k});
            }
        }
    }
}

sub ax ($$$) {
    my $val = shift;
    my $offset = shift;
    my $align = shift;

    if    ($align =~ /l./) { $val -= $offset; }
    elsif ($align =~ /r./) { $val += $offset; }
    return $val;
}

sub ay ($$$) {
    my $val = shift;
    my $offset = shift;
    my $align = shift;

    if    ($align =~ /.b/) { $val -= $offset; }
    elsif ($align =~ /.t/) { $val += $offset; }
    return $val;
}

sub mod_box ($@) {
    my $offset = shift;
    my @cl = ();

    $cl[0]{x} = $_[0]{x};
    $cl[0]{y} = $_[0]{y};
    $cl[1]{x} = $_[1]{x};
    $cl[1]{y} = $_[1]{y};

    $cl[0]{x} += ($cl[0]{x} > $cl[1]{x} ? 1 : -1) * $offset;
    $cl[0]{y} += ($cl[0]{y} > $cl[1]{y} ? 1 : -1) * $offset;
    $cl[1]{x} += ($cl[1]{x} > $cl[0]{x} ? 1 : -1) * $offset;
    $cl[1]{y} += ($cl[1]{y} > $cl[0]{y} ? 1 : -1) * $offset;

    return @cl;
}

sub draw_box ($@) {
    my $l = shift;
    my @cl = @_;

    my $txt = "";

    $txt .= "ADD BOX ";
    $txt .= "LAYER=${l} ";
    $txt .= "AT ";
    my $i = 0;
    foreach my $c (@cl) { $txt .= write_coord($c) ; }
    continue { $i++ ; last if ($i==2) ; }
    $txt .= "; SELECT NEW\n";

    return $txt;
}

sub draw_polygon ($@) {
    my $l = shift;
    my @cl = @_;

    my $txt = "";

    $txt .= "ADD POLYGON ";
    $txt .= "LAYER=${l} ";
    $txt .= "AT ";
    foreach my $c (@cl) { $txt .= write_coord($c) ; }
    $txt .= "; SELECT NEW\n";

    return $txt;
}

sub draw_wire ($$@) {
    my $l = shift;
    my $w = shift;
    my @cl = @_;

    my $txt = "";

    $txt .= "ADD WIRE ";
    $txt .= "LAYER=${l} ";
    $txt .= "WIDTH=".write_num(${w})." ";
    $txt .= "AT ";
    foreach my $c (@cl) { $txt .= write_coord($c) ; }
    $txt .= "; SELECT NEW\n";

    return $txt;
}

sub draw_array {
    my $name = shift;
    my @n = (shift, shift);
    my $s = [shift, shift];
    my $c = [shift, shift];

    my $txt = "";

    $txt .= "ADD ARRAY ${name} ";
    $txt .= "N=($n[0],$n[1]) ";
    $txt .= "STEP=".write_coord($s);
    $txt .= "AT ".write_coord($c)."; SELECT NEW\n";

    return $txt;
}

{
    my $temp_cell = 'TRANS$TMP$';

    sub edit_temp {
        my $txt = "";

        $txt .= "EDIT CELL ${temp_cell}";
        $txt .= " ; SELECT ALL";
        $txt .= " ; DELETE\n";

        return $txt;
    }

    sub add_temp ($) {
        my $name = shift;

        my $txt = "";

        $txt .= "ADD CELL ${temp_cell}";
        $txt .= " AT (0,0) ; SELECT NEW\n";
        $txt .= "UNGROUP ; SELECT NEW\n";

        if ( $name ne "" ) {
            $txt .= "GROUP ${name} YES";
            $txt .= " AT (0,0) ; SELECT NEW\n";
        }

        return $txt;
    }
}

### }}}

1;
