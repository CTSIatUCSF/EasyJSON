#!/usr/bin/perl

package ProfilesEasyJSON::MegaUSC;
use lib '..';
use Data::Dump qw( dump );
use IO::All;
use Moo;
use URI;
use namespace::clean;
use 5.10.0;

extends 'ProfilesEasyJSON';

has '+root_domain' => (
    default => sub {
        URI->new('https://researcherprofiles.org/');
    }
);

has '+themed_base_domain' => (
    default => sub {
        URI->new('https://usc.researcherprofiles.org/');
    }
);

has '+legacy_root_domains' => (
    default => sub {
        [ URI->new('https://profiles.sc-ctsi.org//') ]
    }
);

1;

# Local Variables:
# mode: perltidy
# End:
