#!/usr/bin/perl -w

use strict;
use JSON;
use Data::Dumper;

my $json = JSON->new->allow_nonref;

while ( <STDIN>  ) {
    my $perl_scalar = $json->decode( $_ );
    if ( ! defined($perl_scalar) ) {
        die "Bad JSON? $_: $!\n";
    }
    #print "Output: " . Dumper(\$perl_scalar) . "\n";

    my $new = $perl_scalar;
    foreach ( @ARGV ) {
        $new = $new->{$_};
    }

    if ( defined($new) ) {
        print "$new\n";
    }
}

