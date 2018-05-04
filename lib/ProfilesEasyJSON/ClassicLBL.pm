#!/usr/bin/perl

package ProfilesEasyJSON::ClassicLBL;
use lib '..';
use Data::Dump qw( dump );
use Moo;
use namespace::clean;
use 5.10.0;

extends 'ProfilesEasyJSON';

has '+root_domain' => (
    default => sub {
        URI->new('http://profiles.lbl.gov/');
    }
);

1;

# Local Variables:
# mode: perltidy
# End:
