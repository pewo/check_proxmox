#!/usr/bin/perl -w

use strict;
use JSON;
use Data::Dumper;

my $debug = 0;
my $json = JSON->new->allow_nonref;

#$VAR1 = \{
#            'data' => [
#                        {
#                          'dedup' => 1,
#                          'free' => '532068016',
#                          'alloc' => '64932438',
#                          'frag' => 2,
#                          'name' => 'rpool',
#                          'health' => 'ONLINE',
#                          'size' => '597000454'
#                        },
#                        {
#                          'dedup' => 1,
#                          'free' => '2155142782',
#                          'alloc' => '3239336140',
#                          'frag' => 48,
#                          'name' => 'datapool',
#                          'health' => 'ONLINE',
#                          'size' => '5394478923'
#                        }
#                      ]
#          };
#

my($pool) = shift(@ARGV);
my($key) = shift(@ARGV);

while ( <STDIN>  ) {
    my $perl_scalar = eval  { $json->decode( $_ )};
    if ( $@ ) {
	    exit;
    }
    print Dumper(\$perl_scalar) if ( $debug );

    my($value) = undef;
    my $new = $perl_scalar;
    my($ap) = $perl_scalar->{"data"};
    foreach ( @$ap ) {
	    my($hp) = $_;
	    my($lpool) = $hp->{name};
	    next unless ( $lpool );
	    if ( $lpool eq $pool ) {
		    $value = $hp->{$key};
    	}
    }

    if ( defined($value) ) {
    	print $value . "\n";
    }
}
