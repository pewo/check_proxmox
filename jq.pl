#!/usr/bin/perl -w

use strict;
use JSON;
use Data::Dumper;

my $json = JSON->new->allow_nonref;

while ( <STDIN>  ) {
    my $perl_scalar = eval  { $json->decode( $_ )};
    if ( $@ ) {
	    exit;
    }

    my $new = $perl_scalar;

    foreach ( @ARGV ) {
        $new = $new->{$_};
    }

    if ( defined($new) ) {
        print "$new\n";
    }
}
