#!perl

use lib '.', '..';
use Data::Dump;
use JSON qw( decode_json );
use ProfilesEasyJSON
    qw( identifier_to_json identifier_to_canonical_url canonical_url_to_json );
use Test::More;
use Test::NoWarnings;
use Test::Warn;
binmode STDOUT, ':utf8';
use utf8;
use strict;
use warnings;

my $anirvans_profile_node_url = 'http://profiles.ucsf.edu/profile/370974';

plan tests => 88;

# looking up users by different identifiers

is( identifier_to_canonical_url( 'ProfilesNodeID', '370974',
                                 { cache => 'never' }
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using ProfilesNodeID'
);
is( identifier_to_canonical_url( 'FNO',
                                 'anirvan.chatterjee@ucsf.edu',
                                 { cache => 'never' }
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using FNO'
);
is( identifier_to_canonical_url( 'EmployeeID', '028272045',
                                 { cache => 'never' }
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using EmployeeID'
);
is( identifier_to_canonical_url( 'Person', '5396511', { cache => 'never' } ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using Person ID'
);
is( identifier_to_canonical_url( 'PrettyURL', 'anirvan.chatterjee',
                                 { cache => 'never' }
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using standalone pretty URL name'
);
is( identifier_to_canonical_url( 'PrettyURL', 'Anirvan.Chatterjee',
                                 { cache => 'never' }
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using standalone pretty URL name (incorrect case)'
);
is( identifier_to_canonical_url( 'URL',
                                 'http://profiles.ucsf.edu/anirvan.chatterjee',
                                 { cache => 'never' }
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using URL (pretty)'
);
is( identifier_to_canonical_url( 'URL',
                                 'http://profiles.ucsf.edu/michael.reyes.2',
                                 { cache => 'never' }
    ),
    'http://profiles.ucsf.edu/profile/369982',
    'identifier_to_canonical_url, using URL (pretty, with number)'
);
is( identifier_to_canonical_url( 'URL',
                                 $anirvans_profile_node_url,
                                 { cache => 'never' }
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using URL (canonical)'
);
is( identifier_to_canonical_url(
                  'URL',
                  'http://profiles.ucsf.edu/ProfileDetails.aspx?Person=5396511',
                  { cache => 'never' },
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using URL (historical)'
);
is( identifier_to_canonical_url(
                 'URL',
                 'https://profiles.ucsf.edu/ProfileDetails.aspx?Person=5396511',
                 { cache => 'never' },
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using URL (historical+SSL)'
);

{
    local $SIG{__WARN__} = sub { };    # override warnings
    is( identifier_to_canonical_url( 'Person', '4617024', { cache => 'never' }
        ),
        undef,
        'identifier_to_canonical_url, with an outdated person'
    );
}
is( identifier_to_canonical_url( 'Person', '5195436', { cache => 'never' } ),
    'http://profiles.ucsf.edu/profile/141411399',
    'identifier_to_canonical_url, regression testing person among formerly broken set',
);

{
    my $test_name = 'Anirvan Chatterjee';
    my $json      = canonical_url_to_json($anirvans_profile_node_url);
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 4 unless $json;
        my $data = decode_json($json);

        is( $data->{Profiles}->[0]->{Name},
            'Anirvan Chatterjee',
            'Anirvan name' );

    TODO: {
            local $TODO
                = "Email should show up, but isn't always available at source";
            like( $data->{Profiles}->[0]->{Email},
                  qr/^anirvan\.chatterjee\@ucsf\.edu$/i,
                  'Anirvan email' );
        }

        like(
            $data->{Profiles}->[0]->{ProfilesURL},
            qr{^(http://profiles.ucsf.edu/profile/370974|http://profiles.ucsf.edu/anirvan.chatterjee)$},
            'Anirvan URL'
        );
        cmp_ok( eval { @{ $data->{Profiles}->[0]->{MediaLinks_beta} } },
                '>=', 1, "$test_name: Got enough in the news" );
    }
}

{
    my $test_name = 'Anirvan Chatterjee, force cache';
    my $json =
        canonical_url_to_json( $anirvans_profile_node_url,
                               { cache => 'always' } );
    ok( $json, "$test_name: got back JSON" );
SKIP: {
        skip "$test_name: got back no JSON", 2 unless $json;
        my $data = decode_json($json);

        is( $data->{Profiles}->[0]->{Name},
            'Anirvan Chatterjee',
            "$test_name: name cached"
        );

        ok( (  (  eval {
                      $data->{Profiles}->[0]->{Publications}->[0]
                          ->{PublicationTitle};
                      }
                      || ''
               ) =~ m/Chatterjee/
            ),
            "$test_name: Anirvan's pub PublicationTitle includes his own names [regression]"
        );

    }
}

{
    my $test_name = 'Jennifer Grandis';
    my $json
        = identifier_to_json( 'URL',
                              'http://profiles.ucsf.edu/jennifer.grandis' );
    ok( $json, "$test_name: got back JSON" );
SKIP: {
        skip "$test_name: got back no JSON", 12 unless $json;
        my $data = decode_json($json);
        like( $data->{Profiles}->[0]->{Name}, qr/Grandis/, 'Jenny name' );
        like( $data->{Profiles}->[0]->{Department},
              qr/Otolaryngology/i, "$test_name: department" );
        like( $data->{Profiles}->[0]->{School},
              qr/school of medicine/i,
              "$test_name: school" );
        like( $data->{Profiles}->[0]->{FirstName},
              qr/^Jenn/i, "$test_name: first name" );
        like( $data->{Profiles}->[0]->{LastName},
              qr/^Grandis$/i, "$test_name: last name" );
        like( $data->{Profiles}->[0]->{Email},
              qr/^jennifer\.grandis\@ucsf\.edu$/i,
              "$test_name: email" );
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
                2,
                "$test_name: found at least 2 featured publications ("
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
    my $test_name = 'Daniel Lowenstein';

    my $canonical_url
        = identifier_to_canonical_url( 'FNO', 'daniel.lowenstein@ucsf.edu' );
    like( $canonical_url, qr/^http/, "$test_name: got a canonical URL" );
    my $json = canonical_url_to_json($canonical_url);
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 6 unless $json;

        my $data = decode_json($json);

        like( $data->{Profiles}->[0]->{Name},
              qr/Daniel Lowenstein/,
              "$test_name: Got name" );
        like( $data->{Profiles}->[0]->{PhotoURL},
              qr/^http/, "$test_name: Got photo URL" );
        like( $data->{Profiles}->[0]->{Keywords}->[0],
              qr/\w/, "$test_name: Got keyword" );
        cmp_ok( eval { @{ $data->{Profiles}->[0]->{Publications} } },
                '>=', 50, "$test_name: Got enough publications" );
        like( join( ' ', @{ $data->{Profiles}->[0]->{Keywords} } ),
              qr/epilepsy/i, "$test_name: matching keyword" );
        like( $data->{Profiles}->[0]->{Publications}->[0]->{PublicationTitle},
              qr/Lowenstein.*\. \w.*?\. .*2\d\d\d/,
              "$test_name: Valid publication title"
        );
    }
}

{
    my $test_name = 'Kirsten Bibbins-Domingo';

    my $json = identifier_to_json( 'FNO', 'Kirsten.Bibbins-Domingo@ucsf.edu' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 7 unless $json;
        my $data = decode_json($json);

        like( $data->{Profiles}->[0]->{Name},
              qr/^Kirsten Bibbins-Domingo/,
              "$test_name: Got name"
        );
        like( $data->{Profiles}->[0]->{PhotoURL},
              qr/^http/, "$test_name: Got photo URL" );
        like( join( ' ', @{ $data->{Profiles}->[0]->{Keywords} } ),
              qr/cardiovascular/i, "$test_name: matching keyword" );

        $data->{Profiles}->[0]->{FreetextKeywords} ||= [];
        like( join( ' ', @{ $data->{Profiles}->[0]->{FreetextKeywords} } ),
              qr/Health disparities/i,
              "$test_name: matching freetext keyword" );
        cmp_ok( eval { @{ $data->{Profiles}->[0]->{Publications} } },
                '>=', 90, "$test_name: Got enough publications" );
        like(
            $data->{Profiles}->[0]->{Publications}->[0]->{PublicationTitle},
            qr/(Bibbins|Moyer VA|LeFevre ML|US Preventive Services Task Force).*\. \w.*?\. .*2\d\d\d/,
            "$test_name: Valid publication title"
        );
        cmp_ok( eval { @{ $data->{Profiles}->[0]->{MediaLinks_beta} } },
                '>=', 3, "$test_name: Got enough in the news" );
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

# regression
{
    my $test_name = 'Steve Shiboski';
    my $json = identifier_to_json( 'Person', '5329027' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 3 unless $json;
        my $data = decode_json($json);
        cmp_ok( $data->{Profiles}->[0]->{PublicationCount},
                '>=', 10, "$test_name: Got enough publications" );

        cmp_ok(
            eval {
                scalar(
                    @{  $data->{Profiles}->[0]->{GlobalHealth_beta}->{Countries}
                    }
                );
            },
            '>=',
            1,
            "$test_name: got 1+ global health countries"
        );

        like( $data->{Profiles}->[0]->{PhotoURL},
              qr{^https?://profiles.ucsf.edu/},
              "$test_name: Got photo, as expected"
        );
    }
}

# regression
{
    my $test_name = 'Aaloke Mody';
    my $json      = identifier_to_json( 'URL',
                                   'http://profiles.ucsf.edu/aaloke.mody',
                                   { cache => 'never' } );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 1 unless $json;
        my $data = decode_json($json);
        is_deeply( $data->{Profiles}->[0]->{Address}->{Latitude},
                   undef,
                   "$test_name: Latitude is undef as expected [regression]" );
    }
}

{
    my $test_name = 'Leslie Yuan';
    my $json =
        identifier_to_json( 'URL',
                            'http://profiles.ucsf.edu/leslie.yuan',
                            { cache => 'never' } );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 2 unless $json;
        my $data = decode_json($json);
        cmp_ok( $data->{Profiles}->[0]->{PublicationCount},
                '>=', 5, "$test_name: Got enough publications" );

        is_deeply( $data->{Profiles}->[0]->{GlobalHealth_beta},
                   {}, "$test_name: no global health experience" );
    }
}

{
    my $test_name = 'George Rutherford';
    my $json      = identifier_to_json( 'URL',
                                 'http://profiles.ucsf.edu/george.rutherford' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 2 unless $json;
        my $data = decode_json($json);
        cmp_ok( $data->{Profiles}->[0]->{PublicationCount},
                '>=', 5, "$test_name: Got enough publications" );

        cmp_ok(
            eval {
                scalar(
                    @{  $data->{Profiles}->[0]->{GlobalHealth_beta}->{Countries}
                    }
                );
            },
            '>=',
            3,
            "$test_name: got 3+ global health countries"
        );

    }
}

{
    my $test_name = 'Shinya Yamanaka';
    my $json      = identifier_to_json( 'URL',
                                   'http://profiles.ucsf.edu/shinya.yamanaka' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 1 unless $json;
        my $data = decode_json($json);
        ok( eval {
                scalar @{ $data->{Profiles}->[0]->{MediaLinks_beta} } >= 2; },
            "$test_name: has 2+ news stories"
        );

    }
}

{
    my $test_name = 'Brian Turner';
    my $json = identifier_to_json( 'PrettyURL', 'brian.turner' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 1 unless $json;
        my $data = decode_json($json);

        my @claimed_pubs = grep { $_->{Claimed} }
            @{ $data->{Profiles}->[0]->{Publications} };
        cmp_ok( @claimed_pubs,
                '>=',
                2,
                "$test_name: found at least 2 claimed publications ("
                    . scalar(@claimed_pubs) . ')'
        );
    }

}

{
    my $test_name = 'Harold Chapman';
    my $json
        = identifier_to_json( 'URL',
                              'http://profiles.ucsf.edu/harold.chapman' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 1 unless $json;
        my $data = decode_json($json);
        ok( eval { scalar @{ $data->{Profiles}->[0]->{WebLinks_beta} } >= 3; },
            "$test_name: has 3+ web links" );

    }
}

{
    my $test_name = 'Andrew Auerbach';
    my $json      = identifier_to_json( 'URL',
                                   'http://profiles.ucsf.edu/andrew.auerbach' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 1 unless $json;
        my $data = decode_json($json);
        my @featured_pubs = grep { $_->{Featured} }
            @{ $data->{Profiles}->[0]->{Publications} };
        cmp_ok( @featured_pubs,
                '>=',
                5,
                "$test_name: found at least 5 featured publications ("
                    . scalar(@featured_pubs) . ')'
        );
    }
}

{
    my $test_name = 'Melinda Bender';
    my $json
        = identifier_to_json( 'URL',
                              'http://profiles.ucsf.edu/melinda.bender' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 1 unless $json;
        my $data = decode_json($json);

        my @awards = @{ $data->{Profiles}->[0]->{AwardOrHonors} };
        skip "$test_name: got back no JSON", 1 unless @awards;

        my $found_a_leading_tab = 0;
        foreach my $award (@awards) {
            if ( $award->{AwardLabel} =~ m/^\s/ ) {
                $found_a_leading_tab++;
            }
        }

        ok( !$found_a_leading_tab, 'We killed any leading tabs in her awards' );

    }
}

{
    my $test_name = 'Erin Van Blarigan';
    my $json
        = identifier_to_json( 'URL', 'http://profiles.ucsf.edu/erin.richman' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 2 unless $json;
        my $data = decode_json($json);

        is( ref( $data->{Profiles}->[0]->{ResearchActivitiesAndFunding} ),
            'ARRAY', "$test_name: Grants list should be an array" );

        cmp_ok( scalar(
                     @{ $data->{Profiles}->[0]->{ResearchActivitiesAndFunding} }
                ),
                '<=', 4,
                "$test_name: No more than 4 grants"
        );

    }
}

{
    my $test_name = 'Bad identifier_to_json identifier should fail';
    warnings_exist(
        sub {
            identifier_to_json( 'Fail', 99, { cache => 'never' } );
        },
        [ qr/Fail/i, qr/99/ ],
        "$test_name: Failed?"
    );
}
{
    my $test_name
        = 'Bad identifier_to_canonical_url identifier type should fail';
    warnings_exist( sub { identifier_to_canonical_url( 'Fail', 'eric.meeks' ) },
                    [qr/\w/], "$test_name: Failed?" );
}

{
    my $test_name = 'Bad identifier_to_canonical_url identifier should fail';
    warnings_exist( sub { identifier_to_canonical_url( 'PrettyURL', undef ) },
                    [qr/\w/], "$test_name: Failed?" );
}
{
    my $test_name = 'Bad identifier_to_canonical_url Person should fail';
    warnings_exist( sub { identifier_to_canonical_url( 'Person', undef ) },
                    [qr/\w/], "$test_name: Failed?" );
}
{
    my $test_name = 'Gone identifier_to_canonical_url Person should fail';
    warnings_exist( sub { identifier_to_canonical_url( 'Person', 4617024 ) },
                    [qr/\w/], "$test_name: Failed?" );
}
{
    my $test_name = 'Bad canonical_url_to_json should fail';
    warnings_exist( sub { canonical_url_to_json('http://foo/') },
                    [qr/\w/], "$test_name: Failed?" );
}

# Local Variables:
# mode: perltidy
# End:
