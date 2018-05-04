#!/usr/bin/perl

package ProfilesEasyJSON::ClassicUSC;
use lib '..';
use Data::Dump qw( dump );
use Moo;
use namespace::clean;
use 5.10.0;

extends 'ProfilesEasyJSON';

has '+root_domain' => (
    default => sub {
        URI->new('https://profiles.sc-ctsi.org/');
    }
);

1;

# Local Variables:
# mode: perltidy
# End:
