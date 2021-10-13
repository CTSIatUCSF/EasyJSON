#!/usr/bin/perl

package ProfilesEasyJSON::MegaUCSDStage;
use lib '..';
use Moo;
use namespace::clean;
use 5.10.0;

extends 'ProfilesEasyJSON';

has '+root_domain' => (
    default => sub {
        URI->new('https://stage.researcherprofiles.org/');
    }
);

has '+themed_base_domain' => (
    default => sub {
        URI->new('https://stage-ucsd.researcherprofiles.org/');
    }
);

1;

# Local Variables:
# mode: perltidy
# End:
