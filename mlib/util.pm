package mlib::util;

use strict;
use warnings;
use base 'Exporter';
use POSIX;

our @EXPORT = ('max', 'min', 'sign', 'round');

### Utility Functions {{{

sub max ($$) {
    my $a = shift ;
    my $b = shift ;
    return ( $a > $b ) ? $a : $b ;
}

sub min ($$) {
    my $a = shift ;
    my $b = shift ;
    return ( $a < $b ) ? $a : $b ;
}

sub sign ($) {
    my $a = shift ;
    return ($a != 0) ? int( $a / abs( $a ) ) : 0 ;
}

sub round ($$) {
    my $a = shift ;
    my $s = abs(shift) ;

    if ( $a != 0 ) {

        my $f = $s - int($s);

        my $e = 10 ** (($f == 0) ? 0 : ceil(-1 * log($f) / log(10)));
        my $b = $s * $e;

        $a  = ($a > 0) ? floor($a * $e) : ceil($a * $e);
        $a -= (($a > 0) ? 1 : -1) * (abs($a) % $b);
        $a /= $e;
    }
    return $a;
}

### }}}

1;
