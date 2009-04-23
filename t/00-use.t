#!perl

use Test::More tests => 1;

BEGIN {
	use_ok( 'HTML::Laundry' );
}

diag( "Testing HTML::Laundry $HTML::Laundry::VERSION, Perl $], $^X" );
