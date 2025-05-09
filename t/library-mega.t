#!perl

# add web links, education, keywords, news

use lib 'lib', '../lib';
use Data::Dump;
use JSON qw( decode_json );
use ProfilesEasyJSON::MegaUCSF;
use Test::More;
use Test::NoWarnings;
use Test::Warn 0.31;
binmode STDERR, ':utf8';
binmode STDOUT, ':utf8';
use utf8;
use strict;
use warnings;

my $api = new ProfilesEasyJSON::MegaUCSF;

my $anirvans_profile_node_url = 'https://researcherprofiles.org/profile/176004';
my $patrick_philips_node_url  = 'https://researcherprofiles.org/profile/188475';
my $michael_reyes_node_url    = 'https://researcherprofiles.org/profile/182724';

plan tests => 138;

# looking up users by different identifiers

is( $api->identifier_to_canonical_url(
        'ProfilesNodeID', '370974', { cache => 'never' }
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using ProfilesNodeID'
);
is( $api->identifier_to_canonical_url(
        'FNO', 'anirvan.chatterjee@ucsf.edu', { cache => 'never' }
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using FNO'
);
is( $api->identifier_to_canonical_url(
        'EmployeeID', '028272045', { cache => 'never' }
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using EmployeeID'
);
is( $api->identifier_to_canonical_url(
        'EPPN', '827204@ucsf.edu', { cache => 'never' }
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using EPPN'
);
is( $api->identifier_to_canonical_url(
        'Person', '5396511', { cache => 'never' }
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using Person ID'
);
is( $api->identifier_to_canonical_url(
        'PrettyURL', 'anirvan.chatterjee', { cache => 'never' }
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using standalone pretty URL name'
);
is( $api->identifier_to_canonical_url(
        'PrettyURL', 'Anirvan.Chatterjee', { cache => 'never' }
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using standalone pretty URL name (incorrect case)'
);
is( $api->identifier_to_canonical_url(
        'URL', 'http://profiles.ucsf.edu/anirvan.chatterjee',
        { cache => 'never' }
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using URL (pretty)'
);
is( $api->identifier_to_canonical_url(
        'URL',
        'http://profiles.ucsf.edu/michael.reyes.2',
        { cache => 'never' }
    ),
    $michael_reyes_node_url,
    'identifier_to_canonical_url, using URL (pretty, with number)'
);
is( $api->identifier_to_canonical_url(
        'URL', $anirvans_profile_node_url, { cache => 'never' }
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using URL (canonical)'
);
is( $api->identifier_to_canonical_url(
        'URL',
        'http://profiles.ucsf.edu/ProfileDetails.aspx?Person=5396511',
        { cache => 'never' },
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using URL (historical)'
);
is( $api->identifier_to_canonical_url(
        'URL',
        'https://profiles.ucsf.edu/ProfileDetails.aspx?Person=5396511',
        { cache => 'never' },
    ),
    $anirvans_profile_node_url,
    'identifier_to_canonical_url, using URL (historical+SSL)'
);

{
    local $SIG{__WARN__} = sub { };    # override warnings
    is( $api->identifier_to_canonical_url(
            'Person', '4617024', { cache => 'never' }
        ),
        undef,
        'identifier_to_canonical_url, with an outdated person'
    );
}
is( $api->identifier_to_canonical_url(
        'Person', '5195436', { cache => 'never' }
    ),
    $patrick_philips_node_url,
    'identifier_to_canonical_url, regression testing person among formerly broken set',
);

{
    my $test_name = 'Anirvan Chatterjee';
    my $json      = $api->canonical_url_to_json($anirvans_profile_node_url);
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 5 unless $json;
        my $data = decode_json($json);

        is( $data->{Profiles}->[0]->{Name}, 'Anirvan Chatterjee', 'Anirvan name' );

        like(
            $data->{Profiles}->[0]->{Address}->{Address1},
            qr/490 Illinois Street/,
            "$test_name: address line 1"
        );
        like(
            $data->{Profiles}->[0]->{Address}->{Address2},
            qr/San Francisco/,
            "$test_name: address line 2"
        );

    TODO: {
            local $TODO = "Email should show up, but isn't always available at source";
            like(
                $data->{Profiles}->[0]->{Email},
                qr/^anirvan\.chatterjee\@ucsf\.edu$/i,
                'Anirvan email'
            );
        }

        like(
            $data->{Profiles}->[0]->{ProfilesURL},
            qr{^(http://profiles.ucsf.edu/profile/370974|https?://(profiles.ucsf.edu|(stage-)?ucsf\.researcherprofiles\.org)/anirvan.chatterjee)$},
            'Anirvan URL'
        );
    }
}

{
    my $test_name = 'Anirvan Chatterjee, force cache';
    my $json      = $api->canonical_url_to_json( $anirvans_profile_node_url,
        { cache => 'always' } );
    ok( $json, "$test_name: got back JSON" );
SKIP: {
        skip "$test_name: got back no JSON", 2 unless $json;
        my $data = decode_json($json);

        is( $data->{Profiles}->[0]->{Name},
            'Anirvan Chatterjee',
            "$test_name: name cached"
        );

        ok( (   (
                    eval { $data->{Profiles}->[0]->{Publications}->[0]->{PublicationTitle} }
                        || ''
                ) =~ m/Chatterjee/
            ),
            "$test_name: Anirvan's pub PublicationTitle includes his own name [regression]"
        );

    }
}

{
    my $test_name = 'Jennifer Grandis';
    my $json      = $api->identifier_to_json( 'URL',
        'http://profiles.ucsf.edu/jennifer.grandis' );
    ok( $json, "$test_name: got back JSON" );
SKIP: {
        skip "$test_name: got back no JSON", 12 unless $json;
        my $data = decode_json($json);
        like( $data->{Profiles}->[0]->{Department},
            qr/Otolaryngology/i, "$test_name: department" );
        like(
            $data->{Profiles}->[0]->{School},
            qr/school of medicine/i,
            "$test_name: school"
        );
        like( $data->{Profiles}->[0]->{FirstName},
            qr/^Jenn/i, "$test_name: first name" );
        like( $data->{Profiles}->[0]->{LastName},
            qr/^Grandis$/i, "$test_name: last name" );
        like(
            $data->{Profiles}->[0]->{Email},
            qr/^jennifer\.grandis\@ucsf\.edu$/i,
            "$test_name: email"
        );
        cmp_ok( scalar( @{ $data->{Profiles}->[0]->{Publications} } ),
            '>=', 50, "$test_name: got 50+ publications" );

        my @publication_years
            = map { $_->{Year} } @{ $data->{Profiles}->[0]->{Publications} };
        is_deeply(
            \@publication_years,
            [ sort { $b cmp $a } @publication_years ],
            "$test_name: publications are sorted"
        );

        my @featured_pubs
            = grep { $_->{Featured} } @{ $data->{Profiles}->[0]->{Publications} };

        cmp_ok( @featured_pubs, '>=', 2,
                  "$test_name: found at least 2 featured publications ("
                . scalar(@featured_pubs)
                . ')' );

        isa_ok( $data->{Profiles}->[0]->{AwardOrHonors},
            'ARRAY', "$test_name: got back list of awards" );
        cmp_ok( scalar( @{ $data->{Profiles}->[0]->{AwardOrHonors} } ),
            '>=', 5, "$test_name: got 5+ awards" );
        my @award_start_years
            = map { $_->{AwardStartDate} } @{ $data->{Profiles}->[0]->{AwardOrHonors} };
        is_deeply(
            \@award_start_years,
            [ sort { $b <=> $a } @award_start_years ],
            "$test_name: awards are sorted"
        );
    }
}

{
    my $test_name = 'Daniel Lowenstein';

    my $canonical_url
        = $api->identifier_to_canonical_url( 'FNO', 'daniel.lowenstein@ucsf.edu' );
    like( $canonical_url, qr/^http/, "$test_name: got a canonical URL" );
    my $json = $api->canonical_url_to_json($canonical_url);
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 6 unless $json;

        my $data = decode_json($json);

        like(
            $data->{Profiles}->[0]->{Name},
            qr/Daniel Lowenstein/,
            "$test_name: Got name"
        );
        like( $data->{Profiles}->[0]->{PhotoURL},
            qr/^http/, "$test_name: Got photo URL" );
        like( $data->{Profiles}->[0]->{Keywords}->[0],
            qr/\w/, "$test_name: Got keyword" );
        cmp_ok( eval { @{ $data->{Profiles}->[0]->{Publications} } },
            '>=', 50, "$test_name: Got enough publications" );
        like( join( ' ', @{ $data->{Profiles}->[0]->{Keywords} } ),
            qr/epilepsy/i, "$test_name: matching keyword" );
        like(
            $data->{Profiles}->[0]->{Publications}->[0]->{PublicationTitle},
            qr/Lowenstein.*\. \w.*?\. .*2\d\d\d/,
            "$test_name: Valid publication title"
        );
    }
}

{
    my $test_name = 'Kirsten Bibbins-Domingo';

    my $json
        = $api->identifier_to_json( 'FNO', 'Kirsten.Bibbins-Domingo@ucsf.edu' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 7 unless $json;
        my $data = decode_json($json);

        like(
            $data->{Profiles}->[0]->{Name},
            qr/^Kirsten Bibbins-Domingo/,
            "$test_name: Got name"
        );
        like( $data->{Profiles}->[0]->{PhotoURL},
            qr/^http/, "$test_name: Got photo URL" );
        like( join( ' ', @{ $data->{Profiles}->[0]->{Keywords} } ),
            qr/cardiovascular/i, "$test_name: matching keyword" );

        $data->{Profiles}->[0]->{FreetextKeywords} ||= [];
        like(
            join( ' ', @{ $data->{Profiles}->[0]->{FreetextKeywords} } ),
            qr/health disparities/i,
            "$test_name: matching freetext keyword"
        );
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
    my $json      = $api->identifier_to_json(
        'FNO',
        'Kirsten.Bibbins-Domingo@ucsf.edu',
        { no_publications => 1 }
    );
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
    my $test_name = 'Hope Rugo';
    my $json      = $api->identifier_to_json( 'PrettyURL', 'hope.rugo' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 2 unless $json;
        my $data = decode_json($json);
        cmp_ok( $data->{Profiles}->[0]->{PublicationCount},
            '>=', 100, "$test_name: Got enough publications" );
        cmp_ok( $data->{Profiles}->[0]->{ClinicalTrials},
            '>=', 2, "$test_name: Got enough clinical trials" );
    }
}

# regression
{
    my $test_name = 'Steve Shiboski';
    my $json      = $api->identifier_to_json( 'Person', '5329027' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 3 unless $json;
        my $data = decode_json($json);
        cmp_ok( $data->{Profiles}->[0]->{PublicationCount},
            '>=', 10, "$test_name: Got enough publications" );
        like( $data->{Profiles}->[0]->{PhotoURL},
            qr{PhotoHandler\.ashx}, "$test_name: Got photo, as expected" );
    }
}

{
    my $test_name = 'Leslie Yuan';
    my $json      = $api->identifier_to_json(
        'URL',
        'http://profiles.ucsf.edu/leslie.yuan',
        { cache => 'never' }
    );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 2 unless $json;
        my $data = decode_json($json);
        cmp_ok( $data->{Profiles}->[0]->{PublicationCount},
            '>=', 4, "$test_name: Got enough publications" );

        is_deeply( $data->{Profiles}->[0]->{GlobalHealth_beta},
            {}, "$test_name: no global health experience" );

        my @claimed_pubs
            = grep { $_->{Claimed} } @{ $data->{Profiles}->[0]->{Publications} };
        cmp_ok( @claimed_pubs, '>=', 2,
                  "$test_name: found at least 2 claimed publications ("
                . scalar(@claimed_pubs)
                . ')' );

        my $geolocated_ok = 0;
        if (   ( !defined $data->{Profiles}->[0]->{Address}->{Latitude} )
            or ( abs( $data->{Profiles}->[0]->{Address}->{Latitude} - 37.7 ) < 1 ) ) {
            $geolocated_ok = 1;
        }
        ok( $geolocated_ok, "$test_name: Latitude is either undef, or around SF" );
    }
}

{
    my $test_name = 'George Rutherford';
    my $json      = $api->identifier_to_json( 'URL',
        'http://profiles.ucsf.edu/george.rutherford' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 3 unless $json;
        my $data = decode_json($json);
        cmp_ok( $data->{Profiles}->[0]->{PublicationCount},
            '>=', 5, "$test_name: Got enough publications" );
        is_deeply( $data->{Profiles}->[0]->{ClinicalTrials},
            [], "$test_name: Got no clinical trials" );
        my $countries
            = eval { $data->{Profiles}->[0]->{GlobalHealth_beta}->{Countries} }
            || [];
        cmp_ok( scalar(@$countries), '>=', 3,
            "$test_name: got 3+ global health countries" );
        my $centers = eval { $data->{Profiles}->[0]->{GlobalHealth}->{Centers} }
            || [];
        cmp_ok( scalar(@$centers), '>=', 1,
            "$test_name: got some global health centers" );
    }
}

{
    my $test_name = 'Paul Wesson';
    my $json
        = $api->identifier_to_json( 'URL', 'http://profiles.ucsf.edu/paul.wesson' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 1 unless $json;
        my $data    = decode_json($json);
        my $centers = eval { $data->{Profiles}->[0]->{GlobalHealth}->{Centers} }
            || [];
        cmp_ok( scalar(@$centers), '>=', 1,
            "$test_name: got some global health centers" );
    }
}

{
    my $test_name = 'Adithya Cattamanchi';
    my $json      = $api->identifier_to_json( 'URL',
        'http://profiles.ucsf.edu/adithya.cattamanchi' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 1 unless $json;
        my $data    = decode_json($json);
        my $centers = eval { $data->{Profiles}->[0]->{GlobalHealth}->{Centers} }
            || [];
        cmp_ok( scalar(@$centers), '>=', 1,
            "$test_name: got some global health centers" );
    }
}

{
    my $test_name = 'Shinya Yamanaka';
    my $json      = $api->identifier_to_json( 'URL',
        'http://profiles.ucsf.edu/shinya.yamanaka' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 1 unless $json;
        my $data = decode_json($json);
        ok( eval { scalar @{ $data->{Profiles}->[0]->{MediaLinks_beta} } >= 2; },
            "$test_name: has 2+ news stories" );

    }
}

{
    my $test_name = 'Brian Turner';
    my $json      = $api->identifier_to_json( 'PrettyURL', 'brian.turner' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 1 unless $json;
        my $data = decode_json($json);
        is( eval { $data->{Profiles}->[0]->{Name} // '' },
            'Brian Turner, MBA',
            "$test_name: name is as expected"
        );
    }
}

{
    my $test_name = 'Peter Chin-Hong';
    my $json      = $api->identifier_to_json( 'URL',
        'http://profiles.ucsf.edu/peter.chin-hong' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 1 unless $json;
        my $data = decode_json($json);
        ok( eval { scalar @{ $data->{Profiles}->[0]->{WebLinks_beta} } >= 2; },
            "$test_name: has 2+ web links" );

    }
}

{
    my $test_name = 'Andrew Auerbach';
    my $json      = $api->identifier_to_json( 'URL',
        'http://profiles.ucsf.edu/andrew.auerbach' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 1 unless $json;
        my $data = decode_json($json);
        my @featured_pubs
            = grep { $_->{Featured} } @{ $data->{Profiles}->[0]->{Publications} };
        cmp_ok( @featured_pubs, '>=', 5,
                  "$test_name: found at least 5 featured publications ("
                . scalar(@featured_pubs)
                . ')' );
    }
}

{
    my $test_name = 'Brian Schwartz';
    my $json      = $api->identifier_to_json( 'URL',
        'http://profiles.ucsf.edu/brian.schwartz' );
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

        ok( !$found_a_leading_tab, "$test_name: We killed any leading tabs in awards" );

    }
}

{
    my $test_name = 'Alka Kanaya';
    my $json
        = $api->identifier_to_json( 'URL', 'http://profiles.ucsf.edu/alka.kanaya' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 2 unless $json;
        my $data = decode_json($json);

        is( ref( $data->{Profiles}->[0]->{ResearchActivitiesAndFunding} ),
            'ARRAY', "$test_name: Grants list should be an array" );

        cmp_ok( scalar( @{ $data->{Profiles}->[0]->{ResearchActivitiesAndFunding} } ),
            '<=', 20, "$test_name: No more than 20 grants" );

    }
}

{
    my $test_name = 'Peggy Tahir';
    my $json      = $api->identifier_to_json( 'URL',
        'https://profiles.ucsf.edu/peggy.tahir' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 5 unless $json;
        my $data = decode_json($json);

        like( $data->{Profiles}->[0]->{Title}, qr/librar/i, "$test_name: title" );
        like( $data->{Profiles}->[0]->{Department},
            qr/library/i, "$test_name: department" );
        like( $data->{Profiles}->[0]->{Address}->{Telephone},
            qr/^415-/i, "$test_name: telephone" );
        like(
            $data->{Profiles}->[0]->{Email},
            qr/^peggy\.tahir\@ucsf\.edu$/i,
            "$test_name: email"
        );
        cmp_ok( scalar( @{ $data->{Profiles}->[0]->{Publications} } ),
            '>=', 10, "$test_name: got 10+ publications" );
    }
}

{
    my $test_name = 'Michael Schembri';
    my $json      = $api->identifier_to_json( 'URL',
        'http://profiles.ucsf.edu/michael.schembri' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 8 unless $json;
        my $data = decode_json($json);

        like( $data->{Profiles}->[0]->{Title}, qr/analyst/i, "$test_name: title" );
        like( $data->{Profiles}->[0]->{Department},
            qr/Medicine/i, "$test_name: department" );
        like( $data->{Profiles}->[0]->{Address}->{Telephone},
            qr/^415-/i, "$test_name: telephone" );
        like(
            $data->{Profiles}->[0]->{Email},
            qr/^michael\.schembri\@ucsf\.edu$/i,
            "$test_name: email"
        );
        cmp_ok( scalar( @{ $data->{Profiles}->[0]->{Publications} } ),
            '>=', 1, "$test_name: got 1+ publications" );
        ok( eval { scalar @{ $data->{Profiles}->[0]->{WebLinks_beta} } >= 1; },
            "$test_name: has 1+ web links" );
        cmp_ok( scalar( @{ $data->{Profiles}->[0]->{Education_Training} } ),
            '>=', 1, "$test_name: got 1+ education items" );
        like(
            (   eval { $data->{Profiles}->[0]->{Education_Training}->[0]->{organization} }
                    // ''
            ),
            qr/Davis/,
            "$test_name: was educated at Davis"
        );
        is_deeply( $data->{Profiles}->[0]->{ClinicalTrials},
            [], "$test_name: Got no clinical trials" );
    }
}

{
    my $test_name = 'Aayush Khadka';
    my $json      = $api->identifier_to_json( 'URL',
        'http://profiles.ucsf.edu/aayush.khadka' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 4 unless $json;
        my $data = decode_json($json);

        like( $data->{Profiles}->[0]->{Title},  qr/postdoc/i, "$test_name: title" );
        like( $data->{Profiles}->[0]->{School}, qr/Medicine/, "$test_name: school" );
        like(
            $data->{Profiles}->[0]->{Email},
            qr/^aayush\.khadka\@ucsf\.edu$/i,
            "$test_name: email"
        );
        like( $data->{Profiles}->[0]->{Narrative},
            qr/cognitive|environmental/i, "$test_name: narrative" );
    }
}

{
    my $test_name = 'Tung Nguyen';
    my $json
        = $api->identifier_to_json( 'URL', 'http://profiles.ucsf.edu/tung.nguyen' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 13 unless $json;
        my $data = decode_json($json);

        like( $data->{Profiles}->[0]->{Title},  qr/professor/i, "$test_name: title" );
        like( $data->{Profiles}->[0]->{School}, qr/Medicine/,   "$test_name: school" );
        like(
            $data->{Profiles}->[0]->{Email},
            qr/^tung\.nguyen\@ucsf\.edu$/i,
            "$test_name: email"
        );
        like( $data->{Profiles}->[0]->{Narrative},
            qr/Vietnamese/, "$test_name: narrative" );
        ok( eval { scalar @{ $data->{Profiles}->[0]->{WebLinks_beta} } >= 1; },
            "$test_name: has 1+ web links" );
        cmp_ok( scalar( @{ $data->{Profiles}->[0]->{Education_Training} } ),
            '>=', 2, "$test_name: got 2+ education items" );
        ok( eval {
                grep { $_->{organization} =~ m/Harvard/ }
                    @{ $data->{Profiles}->[0]->{Education_Training} };
            },
            "$test_name: was educated at Harvard"
        );

        like( join( ' ', @{ $data->{Profiles}->[0]->{FreetextKeywords} } ),
            qr/immigrant/i, "$test_name: matching freetext keyword" );
        cmp_ok( eval { @{ $data->{Profiles}->[0]->{MediaLinks_beta} } },
            '>=', 3, "$test_name: Got enough in the news" );
    }
}

{
    my $test_name = 'Robert Hiatt';
    my $json      = $api->identifier_to_json( 'URL',
        'http://profiles.ucsf.edu/robert.hiatt' );
    ok( $json, "$test_name: got back JSON" );

SKIP: {
        skip "$test_name: got back no JSON", 11 unless $json;
        my $data = decode_json($json);

        like( $data->{Profiles}->[0]->{Title},  qr/^Professor$/i, "$test_name: title" );
        like( $data->{Profiles}->[0]->{School}, qr/Medicine/, "$test_name: school" );
        like(
            $data->{Profiles}->[0]->{Department},
            qr/Epidemiology.{1,5}Biostatistics/,
            "$test_name: department"
        );
        unlike( $data->{Profiles}->[0]->{Address}->{Address1},
            qr/Varies|Flexible|0000/i, "$test_name: address line 1 is not stupid" );
        unlike( $data->{Profiles}->[0]->{Address}->{Address2},
            qr/Varies|Flexible|0000/i, "$test_name: address line 2 is not stupid" );
        like( $data->{Profiles}->[0]->{Address}->{Telephone},
            qr/^415-514-8113$/i, "$test_name: telephone" );
        like(
            $data->{Profiles}->[0]->{Email},
            qr/^robert\.hiatt\@ucsf\.edu$/i,
            "$test_name: email"
        );
        like(
            $data->{Profiles}->[0]->{Narrative},
            qr/cancer epidemiology/,
            "$test_name: narrative"
        );
        like(
            join( ' ', @{ $data->{Profiles}->[0]->{FreetextKeywords} } ),
            qr/implementation science/i,
            "$test_name: matching freetext keyword"
        );
        ok( eval {
                grep { $_->{degree} =~ m/residency/i }
                    @{ $data->{Profiles}->[0]->{Education_Training} };
            },
            "$test_name: includes residency"
        );
        cmp_ok( eval { @{ $data->{Profiles}->[0]->{MediaLinks_beta} } },
            '>=', 1, "$test_name: Was in the news" );
        ok( eval {
                grep { $_->{organization} =~ m/Berkeley|University of California/ }
                    @{ $data->{Profiles}->[0]->{Education_Training} };
            },
            "$test_name: was educated at Berkeley"
        );
    }
}

{
    my $test_name = 'Bad $api->identifier_to_json identifier should fail';
    local $SIG{__WARN__} = sub { };
    is( $api->identifier_to_json( 'Fail', 99, { cache => 'never' } ),
        undef, "$test_name: Failed?" );
}
{
    my $test_name
        = 'Bad $api->identifier_to_canonical_url identifier type should fail';
    local $SIG{__WARN__} = sub { };
    is( $api->identifier_to_canonical_url( 'Fail', 'eric.meeks' ),
        undef, "$test_name: Failed?" );
}

{
    my $test_name = 'Bad $api->identifier_to_canonical_url identifier should fail';
    local $SIG{__WARN__} = sub { };
    is( $api->identifier_to_canonical_url( 'PrettyURL', undef ),
        undef,

        "$test_name: Failed?"
    );
}
{
    my $test_name = 'Bad $api->identifier_to_canonical_url Person should fail';
    local $SIG{__WARN__} = sub { };
    is( $api->identifier_to_canonical_url( 'Person', undef ),
        undef, "$test_name: Failed?" );
}
{
    my $test_name = 'Gone $api->identifier_to_canonical_url Person should fail';
    local $SIG{__WARN__} = sub { };
    is( $api->identifier_to_canonical_url( 'Person', 4617024 ),
        undef, "$test_name: Failed?" );
}
{
    my $test_name = 'Bad $api->canonical_url_to_json should fail';
    local $SIG{__WARN__} = sub { };
    is( $api->canonical_url_to_json('http://foo/'), undef, "$test_name: Failed?" );
}

# Local Variables:
# mode: perltidy
# End:
