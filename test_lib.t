#!perl

use lib '.';
use Data::Dump;
use JSON qw( decode_json );
use ProfilesEasyJSON
    qw( identifier_to_json identifier_to_canonical_url canonical_url_to_json );
use Test::More;
use Test::NoWarnings;
binmode STDOUT, ':utf8';
use utf8;
use strict;
use warnings;

plan tests => 47;

is( identifier_to_canonical_url( 'ProfilesNodeID', '370974' ),
    'http://profiles.ucsf.edu/profile/370974',
    'identifier_to_canonical_url ProfilesNodeID'
);
is( identifier_to_canonical_url( 'FNO', 'anirvan.chatterjee@ucsf.edu' ),
    'http://profiles.ucsf.edu/profile/370974',
    'identifier_to_canonical_url FNO'
);
is( identifier_to_canonical_url( 'Person', '5396511' ),
    'http://profiles.ucsf.edu/profile/370974',
    'identifier_to_canonical_url Person'
);
is( identifier_to_canonical_url( 'EmployeeID', '028272045' ),
    'http://profiles.ucsf.edu/profile/370974',
    'identifier_to_canonical_url EmployeeID' );
is( identifier_to_canonical_url( 'PrettyURL', 'anirvan.chatterjee' ),
    'http://profiles.ucsf.edu/profile/370974',
    'identifier_to_canonical_url PrettyURL'
);
is( identifier_to_canonical_url( 'PrettyURL', 'Anirvan.Chatterjee' ),
    'http://profiles.ucsf.edu/profile/370974',
    'identifier_to_canonical_url PrettyURL bad case'
);
is( identifier_to_canonical_url( 'URL',
                                 'http://profiles.ucsf.edu/anirvan.chatterjee'
    ),
    'http://profiles.ucsf.edu/profile/370974',
    'identifier_to_canonical_url profile with pretty URL'
);
is( identifier_to_canonical_url( 'URL',
                                 'http://profiles.ucsf.edu/profile/370974'
    ),
    'http://profiles.ucsf.edu/profile/370974',
    'identifier_to_canonical_url canonical URL'
);
is( identifier_to_canonical_url(
                 'URL',
                 'http://profiles.ucsf.edu/ProfileDetails.aspx?Person=5396511'
    ),
    'http://profiles.ucsf.edu/profile/370974',
    'identifier_to_canonical_url old ProfileDetails URL'
);
is( identifier_to_canonical_url( 'URL',
                                 'http://profiles.ucsf.edu/michael.reyes.2'
    ),
    'http://profiles.ucsf.edu/profile/369982',
    'identifier_to_canonical_url profile with pretty URL with number'
);

{
    my $test_name = 'Anirvan Chatterjee';
    my $json
        = canonical_url_to_json('http://profiles.ucsf.edu/profile/370974');
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 3 unless $json;
        my $data = decode_json($json);

        is( $data->{Profiles}->[0]->{Name},
            'Anirvan Chatterjee',
            'Anirvan name' );
        is( $data->{Profiles}->[0]->{Email},
            'anirvan.chatterjee@ucsf.edu', 'Anirvan email' );
        like(
            $data->{Profiles}->[0]->{ProfilesURL},
            qr{^(http://profiles.ucsf.edu/profile/370974|http://profiles.ucsf.edu/anirvan.chatterjee)$},
            'Anirvan URL'
        );
    }
}

{
    my $test_name = 'Anirvan Chatterjee, force cache';
    my $json =
        canonical_url_to_json( 'http://profiles.ucsf.edu/profile/370974',
                               { cache => 'always' } );
    ok( $json, "$test_name: got back JSON" );
SKIP: {
        skip "$test_name: got back no JSON", 1 unless $json;
        my $data = decode_json($json);

        is( $data->{Profiles}->[0]->{Name},
            'Anirvan Chatterjee',
            "$test_name: name cached"
        );
    }
}

{
    my $test_name = 'Clay Johnston';
    my $json =
        identifier_to_json( 'URL',
                            'http://profiles.ucsf.edu/clay.johnston',
                            { mobile => 1 } );
    ok( $json, "$test_name: got back JSON" );
SKIP: {
        skip "$test_name: got back no JSON", 3 unless $json;
        my $data = decode_json($json);
        like( $data->{Profiles}->[0]->{Name}, qr/Johnston/, 'Clay name' );
        like( $data->{Profiles}->[0]->{Department},
              qr/neurology/i, "$test_name: department" );
        like( $data->{Profiles}->[0]->{School},
              qr/school of medicine/i,
              "$test_name: school" );
        like( $data->{Profiles}->[0]->{FirstName},
              qr/^Clay$/i, "$test_name: first name" );
        like( $data->{Profiles}->[0]->{LastName},
              qr/^Johnston$/i, "$test_name: last name" );

        like( $data->{Profiles}->[0]->{Publications}->[0]->{PublicationSource}
                  ->[0]->{PublicationSourceURL},
              qr{/m/pubmed/}, "$test_name: mobile URL"
        );
        cmp_ok( scalar( @{ $data->{Profiles}->[0]->{Publications} } ),
                '>=', 50, "$test_name: got 50+ publications" );

        my @publication_years
            = map { $_->{Year} } @{ $data->{Profiles}->[0]->{Publications} };
        is_deeply( \@publication_years,
                   [ sort { $b cmp $a } @publication_years ],
                   "$test_name: publications are sorted" );

        my @featured_pubs = grep { $_->{Featured} }
            @{ $data->{Profiles}->[0]->{Publications} };

        cmp_ok( @featured_pubs,
                '>=',
                5,
                "$test_name: found at least 5 featured publications ("
                    . scalar(@featured_pubs) . ')'
        );

        isa_ok( $data->{Profiles}->[0]->{AwardOrHonors},
                'ARRAY', "$test_name: got back list of awards" );
        cmp_ok( scalar( @{ $data->{Profiles}->[0]->{AwardOrHonors} } ),
                '>=', 5, "$test_name: got 5+ awards" );
        my @award_start_years = map { $_->{AwardStartDate} }
            @{ $data->{Profiles}->[0]->{AwardOrHonors} };
        is_deeply( \@award_start_years,
                   [ sort { $b <=> $a } @award_start_years ],
                   "$test_name: awards are sorted" );
    }
}

{
    my $test_name = 'Jeanette Brown';

    my $canonical_url
        = identifier_to_canonical_url( 'FNO', 'jeanette.brown@ucsf.edu' );
    my $json = canonical_url_to_json($canonical_url);
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 6 unless $json;

        my $data = decode_json($json);

        like( $data->{Profiles}->[0]->{Name},
              qr/Jeanette Brown/,
              "$test_name: Got name" );
        like( $data->{Profiles}->[0]->{PhotoURL},
              qr/^http/, "$test_name: Got photo URL" );
        like( $data->{Profiles}->[0]->{Keywords}->[0],
              qr/\w/, "$test_name: Got keyword" );
        cmp_ok( eval { @{ $data->{Profiles}->[0]->{Publications} } },
                '>=', 50, "$test_name: Got enough publications" );
        like( join( ' ', @{ $data->{Profiles}->[0]->{Keywords} } ),
              qr/urinary/i, "$test_name: matching keyword" );
        like( $data->{Profiles}->[0]->{Publications}->[0]->{PublicationTitle},
              qr/Brown.*\. \w.*?\. .*2\d\d\d/,
              "$test_name: Valid publication title"
        );
    }
}

{
    my $test_name = 'Kirsten Bibbins-Domingo';

    my $json
        = identifier_to_json( 'FNO', 'Kirsten.Bibbins-Domingo@ucsf.edu' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 5 unless $json;
        my $data = decode_json($json);

        like( $data->{Profiles}->[0]->{Name},
              qr/^Kirsten Bibbins-Domingo/,
              "$test_name: Got name"
        );
        like( $data->{Profiles}->[0]->{PhotoURL},
              qr/^http/, "$test_name: Got photo URL" );
        like( join( ' ', @{ $data->{Profiles}->[0]->{Keywords} } ),
              qr/coronary/i, "$test_name: matching keyword" );

        $data->{Profiles}->[0]->{FreetextKeywords} ||= [];
        like( join( ' ', @{ $data->{Profiles}->[0]->{FreetextKeywords} } ),
              qr/Health disparities/i,
              "$test_name: matching freetext keyword"
        );
        cmp_ok( eval { @{ $data->{Profiles}->[0]->{Publications} } },
                '>=', 90, "$test_name: Got enough publications" );
        like( $data->{Profiles}->[0]->{Publications}->[0]->{PublicationTitle},
              qr/(Bibbins|Moyer VA).*\. \w.*?\. .*2\d\d\d/,
              "$test_name: Valid publication title"
        );
    }
}

{
    my $test_name = 'Kirsten Bibbins-Domingo no publications';
    my $json =
        identifier_to_json( 'FNO',
                            'Kirsten.Bibbins-Domingo@ucsf.edu',
                            { no_publications => 1 } );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 2 unless $json;
        my $data = decode_json($json);
        ok( eval { !@{ $data->{Profiles}->[0]->{Publications} } },
            'Disabling publications works' );
        cmp_ok( $data->{Profiles}->[0]->{PublicationCount},
                '>=', 90, "$test_name: Got enough publications" );
    }
}

# Local Variables:
# mode: perltidy
# End:
