#!/usr/bin/perl

package ProfilesEasyJSON::MegaUCSFDev;
use lib '..';
use Moo;
use namespace::clean;
use 5.10.0;

extends 'ProfilesEasyJSON';

has '+root_domain' => (
    default => sub {
        URI->new('https://dev.researcherprofiles.org/');
    }
);

has '+themed_base_domain' => (
    default => sub {
        URI->new('https://dev-ucsf.researcherprofiles.org/');
    }
);

1;

# Local Variables:
# mode: perltidy
# End:
