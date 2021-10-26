#!/usr/bin/perl

package ProfilesEasyJSON::MegaUCLA;
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
        URI->new('https://profiles.ucla.edu/');
    }
);

has '+legacy_root_domains' => (
    default => sub {
        [ URI->new('http://profiles.ucla.edu/') ]
    }
);

1;

# Local Variables:
# mode: perltidy
# End:
