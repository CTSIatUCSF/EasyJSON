#!perl

use lib 'lib', '../lib';
use Data::Dump;
use ProfilesEasyJSON::MegaUCSF;
use Test::More;
use Test::NoWarnings;
use strict;
use warnings;

plan tests => 17;

*preprocess_ucsf_identifier
    = \&ProfilesEasyJSON::MegaUCSF::preprocess_ucsf_identifier;

is_deeply(
    [ preprocess_ucsf_identifier( 'PrettyURL', 'anirvan.chatterjee' ) ],
    [ 'PrettyURL', 'anirvan.chatterjee', {} ],
    'valid PrettyURL'
);

is_deeply(
    [ preprocess_ucsf_identifier( 'Person', '5396511' ) ],
    [ 'PrettyURL', 'anirvan.chatterjee', {} ],
    'valid Person'
);

is_deeply(
    [ preprocess_ucsf_identifier( 'Person', '2570262' ) ],
    [ 'UserName', '000955@ucsf.edu', {} ],
    'valid short person ID (regression)'
);

is_deeply(
    [ preprocess_ucsf_identifier( 'FNO', 'anirvan.chatterjee@ucsf.edu' ) ],
    [ 'PrettyURL', 'anirvan.chatterjee', {} ],
    'valid FNO'
);

is_deeply(
    [ preprocess_ucsf_identifier( 'EmployeeID', '028272045' ) ],
    [ 'UserName', '827204@ucsf.edu', {} ],
    'valid EmployeeID'
);

is_deeply(
    [ preprocess_ucsf_identifier( 'EPPN', '827204@ucsf.edu' ) ],
    [ 'UserName', '827204@ucsf.edu', {} ],
    'valid EPPN'
);

is_deeply(
    [   preprocess_ucsf_identifier(
            'URL', 'https://profiles.ucsf.edu/anirvan.chatterjee'
        )
    ],
    [ 'PrettyURL', 'anirvan.chatterjee', {} ],
    'valid URL with PrettyURL'
);

is_deeply(
    [   preprocess_ucsf_identifier(
            'URL', 'https://profiles.ucsf.edu/ProfileDetails.aspx?Person=5396511'
        )
    ],
    [ 'PrettyURL', 'anirvan.chatterjee', {} ],
    'valid URL with Person ID'
);

is_deeply(
    [   preprocess_ucsf_identifier(
            'URL', 'https://profiles.ucsf.edu/profile/1234567'
        )
    ],
    [ 'ProfilesNodeID', '1234567', {} ],
    'valid URL with node ID'
);

is_deeply(
    [ preprocess_ucsf_identifier( 'FNO', 'christina.yau@ucsf.edu' ) ],
    [ 'PrettyURL', 'christina.yau', {} ],
    'valid FNO not in lookup table'
);

{
    local $SIG{__WARN__} = sub { };
    is_deeply( [ preprocess_ucsf_identifier( 'PrettyURL', '99' ) ],
        [], 'invalid PrettyURL' );
    is_deeply( [ preprocess_ucsf_identifier( 'Person', '99' ) ],
        [], 'invalid Person' );
    is_deeply( [ preprocess_ucsf_identifier( 'EmployeeID', '99' ) ],
        [], 'invalid EmployeeID' );
    is_deeply( [ preprocess_ucsf_identifier( 'ProfilesNodeID', 'a' ) ],
        [], 'invalid ProfilesNodeID' );
    is_deeply( [ preprocess_ucsf_identifier( 'URL', 'http://google.com/' ) ],
        [], 'cannot expand random URL' );
    is_deeply( [ preprocess_ucsf_identifier( 'FNO', '99' ) ],
        [], 'cannot expand FNO without a lookup' );
}

# Local Variables:
# mode: perltidy
# End:
