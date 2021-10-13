#!/usr/bin/perl

package ProfilesEasyJSON::MegaUCSD;
use lib '..';
use Data::Dump qw( dump );
use IO::All;
use Moo;
use URI;
use Text::CSV::Slurp;
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
        URI->new('https://profiles.ucsd.edu/');
    }
);

has '+legacy_root_domains' => (
    default => sub {
        [ URI->new('http://profiles.ucsd.edu/') ]
    }
);

1;

# Local Variables:
# mode: perltidy
# End:
