package mlib::debug;

use strict;
use warnings;
use base 'Exporter';

our @EXPORT = ('print_readable');

### DEBUG Function {{{

{
    my $n = 0; # presistant variable for print_readable
    sub print_readable {                    # debug function to print out data structures
        $n++;
        foreach my $in (@_) {
            if (ref($in) eq "SCALAR") {
                print "Scalar: ".${$in}."\n";
            } elsif (ref($in) eq "ARRAY") {
                print "Array(". scalar(@{$in}) ."):\n";
                foreach my $i (0 .. $#{$in}) {
                    print ".  "x$n."[".$i."] => ";
                    print_readable($in->[$i]);
                }
            } elsif (ref($in) eq "HASH") {
                print "Hash(". scalar(keys(%{$in})) ."):\n";
                for my $k (sort keys %{$in}) {
                    print ".  "x$n."{".$k."} => ";
                    print_readable($in->{$k});
                }
            } else {
                print $in."\n";
            }
        }
        $n--;
    }
}

### }}}

1;
