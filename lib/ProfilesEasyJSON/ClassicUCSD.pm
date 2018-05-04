#!/usr/bin/perl

package ProfilesEasyJSON::ClassicUCSD;
use lib '..';
use Data::Dump qw( dump );
use Moo;
use namespace::clean;
use 5.10.0;

extends 'ProfilesEasyJSON';

has '+root_domain' => (
    default => sub {
        URI->new('http://profiles.ucsd.edu/');
    }
);

1;

# Local Variables:
# mode: perltidy
# End:
