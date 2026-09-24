#!perl

# Comprehensive field coverage tests using three well-populated profiles:
# Vanessa Jacoby, Kirsten Bibbins-Domingo, and Claire Brindis.
#
# The strategy: verify that each output field is populated on AT LEAST ONE
# of the three profiles, rather than assuming any one person always has it.
# Identity facts (name, department, etc.) are still tied to a specific person.

use lib 'lib', '../lib';
use JSON       qw( decode_json );
use List::Util qw( any first );
use ProfilesEasyJSON::MegaUCSF;
use Test::More;
use Test::NoWarnings;
binmode STDERR, ':utf8';
binmode STDOUT, ':utf8';
use utf8;
use strict;
use warnings;

my $api = ProfilesEasyJSON::MegaUCSF->new;

my %profiles_by_username;
for my $u (
    'vanessa.jacoby',      'kirsten.bibbins-domingo',
    'claire.brindis',      'alan.ashworth',
    'elizabeth.owens',     'vincent.turon-lagot',
    'adithya.cattamanchi', 'nevan.krogan',
    'leslie.benet',        'renee.hsia',
    'steven.pantilat',     'aaron.neinstein',
    'jaime.sepulveda',     'eric.goosby',
    'dilys.walker',        'michael.lipnick',
    'craig.cohen',
  )
{
    my $json = $api->identifier_to_json( 'PrettyURL', $u );
    $profiles_by_username{$u} = decode_json($json)->{Profiles}[0] if $json;
}

my @profiles = values %profiles_by_username;
my @loaded   = grep { defined } values %profiles_by_username;

plan tests => 180;

# ---------------------------------------------------------------------------
# Helper: true if any profile satisfies the test
sub any_profile (&) {
    my $code = shift;
    return any {
        do { local $_ = $_; $code->() }
    } @profiles;
}

###############################################################################
# Basic identity checks — these are facts tied to a specific person
###############################################################################

SKIP: {
    my $p = $profiles_by_username{'vanessa.jacoby'}
      or skip 'vanessa.jacoby: no JSON', 7;
    is( $p->{Name},      'Vanessa Jacoby, MD, MAS', 'Vanessa: full name' );
    is( $p->{FirstName}, 'Vanessa',                 'Vanessa: first name' );
    is( $p->{LastName},  'Jacoby',                  'Vanessa: last name' );
    like( $p->{Department}, qr/ob.?gyn|reproductive/i, 'Vanessa: department' );
    like( $p->{School},     qr/medicine/i,             'Vanessa: school' );
    like(
        $p->{ProfilesURL},
        qr{profiles\.ucsf\.edu/vanessa\.jacoby},
        'Vanessa: ProfilesURL'
    );
    like( $p->{Narrative}, qr/fibroid/i,
        'Vanessa: narrative mentions fibroids' );
}

SKIP: {
    my $p = $profiles_by_username{'kirsten.bibbins-domingo'}
      or skip 'kirsten.bibbins-domingo: no JSON', 11;
    like( $p->{Name},       qr/Kirsten Bibbins-Domingo/, 'Kirsten: full name' );
    like( $p->{Department}, qr/epidemiology/i, 'Kirsten: department' );
    like( $p->{School},     qr/medicine/i,     'Kirsten: school' );
    like( join( ' ', @{ $p->{Keywords} } ),
        qr/cardiovascular/i, 'Kirsten: mesh keywords include cardiovascular' );
    like( $p->{ORCID} // '', qr/^\d{4}-\d{4}-\d{4}-\d{4}$/,
        'Kirsten: ORCID is well-formed' );
    like( $p->{PhotoURL} // '', qr/^https?:\/\//,
        'Kirsten: PhotoURL is an http(s) URL' );
    cmp_ok( scalar @{ $p->{FreetextKeywords} // [] },
        '>=', 5, 'Kirsten: has 5+ freetext keywords' );
    cmp_ok( scalar @{ $p->{Education_Training} // [] },
        '>=', 4, 'Kirsten: has 4+ education entries' );
    cmp_ok( scalar @{ $p->{AwardOrHonors} // [] },
        '>=', 5, 'Kirsten: has 5+ awards' );
    cmp_ok( scalar @{ $p->{NIHGrants_beta} // [] },
        '>=', 5, 'Kirsten: has 5+ NIH grants' );
    cmp_ok( scalar @{ $p->{GlobalHealth}{Locations} // [] },
        '>=', 1, 'Kirsten: has GlobalHealth locations' );
}

SKIP: {
    my $p = $profiles_by_username{'claire.brindis'}
      or skip 'claire.brindis: no JSON', 8;
    like( $p->{Name},       qr/Claire Brindis/, 'Claire: full name' );
    like( $p->{Department}, qr/health policy/i, 'Claire: department' );
    like( $p->{School},     qr/medicine/i,      'Claire: school' );
    ok(
        length( $p->{Narrative} // '' ) >= 100,
        'Claire: has a substantive narrative'
    );
    like( $p->{ORCID} // '', qr/^\d{4}-\d{4}-\d{4}-\d{4}$/,
        'Claire: ORCID is well-formed' );
    cmp_ok( scalar @{ $p->{Titles} // [] },
        '>=', 2, 'Claire: has 2+ Titles' );
    cmp_ok( scalar @{ $p->{ResearchActivitiesAndFunding} // [] },
        '>=', 10, 'Claire: has 10+ grants' );
    cmp_ok( scalar @{ $p->{FreetextKeywords} // [] },
        '>=', 10, 'Claire: has 10+ freetext keywords' );
}

SKIP: {
    my $p = $profiles_by_username{'adithya.cattamanchi'}
      or skip 'adithya.cattamanchi: no JSON', 4;
    cmp_ok( scalar @{ $p->{GlobalHealth}{Locations} // [] },
        '>=', 5, 'Adithya: has 5+ GlobalHealth locations' );
    cmp_ok( scalar @{ $p->{GlobalHealth_beta}{Countries} // [] },
        '>=', 1, 'Adithya: has GlobalHealth_beta countries' );
    cmp_ok( scalar @{ $p->{NIHGrants_beta} // [] },
        '>=', 5, 'Adithya: has 5+ NIH grants' );
    cmp_ok( scalar @{ $p->{ResearchActivitiesAndFunding} // [] },
        '>=', 5, 'Adithya: has 5+ grants/activities' );
}

SKIP: {
    my $p = $profiles_by_username{'leslie.benet'}
      or skip 'leslie.benet: no JSON', 3;
    like( $p->{Email} // '', qr/\@ucsf\.edu$/,
        'Leslie: has a @ucsf.edu email' );
    cmp_ok( scalar @{ $p->{AwardOrHonors} // [] },
        '>=', 20, 'Leslie: has 20+ awards' );
    ok( ( grep { length( $_->{AwardLabel} // '' ) > 3 }
              @{ $p->{AwardOrHonors} // [] } ),
        'Leslie: at least one award has a label' );
}

SKIP: {
    my $p = $profiles_by_username{'elizabeth.owens'}
      or skip 'elizabeth.owens: no JSON', 1;
    like( $p->{Address}{Telephone} // '', qr/^415-/,
        'Elizabeth: has a 415 phone number' );
}

###############################################################################
# Cross-profile field coverage — at least ONE of the three must have each field
###############################################################################

# --- Identity / basic fields ---

ok(
    any_profile { $_->{Title} =~ /professor/i },
    'At least one profile has a Professor title'
);

ok( any_profile { ( $_->{ORCID} // '' ) =~ /^\d{4}-\d{4}-\d{4}-\d{4}$/ },
    'At least one profile has a well-formed ORCID' );

ok(
    any_profile {
        ( eval { $_->{Twitter_beta}[0] } // '' ) =~ /^\w{2,}$/
    },
    'At least one profile has a Twitter_beta handle'
);

# Twitter_beta is either undef (no handle) or an arrayref — never a plain
# string or hash. This shape has been stable since the field was introduced.
ok(
    ( grep { defined $_->{Twitter_beta} && ref( $_->{Twitter_beta} ) ne 'ARRAY' }
          @loaded ) == 0,
    'Twitter_beta is always undef or an arrayref, never any other type'
);

ok( any_profile { ( $_->{PhotoURL} // '' ) =~ /PhotoHandler\.ashx/ },
    'At least one profile has a PhotoURL' );

ok( any_profile { ( $_->{Address}{Telephone} // '' ) =~ /^415-/ },
    'At least one profile has a 415 phone number' );

ok(
    any_profile { ( $_->{Email} // '' ) =~ /\@ucsf\.edu$/ },
    'At least one profile has a @ucsf.edu Email address'
);

ok(
    any_profile {
        defined $_->{Address}{Latitude}
          and abs( $_->{Address}{Latitude} - 37.7 ) < 1
    },
    'At least one profile has SF-area latitude'
);

ok(
    any_profile {
        defined $_->{Address}{Longitude}
          and abs( $_->{Address}{Longitude} - (-122.46) ) < 1
    },
    'At least one profile has SF-area longitude'
);

ok( any_profile { ( $_->{Address}{Address1} // '' ) =~ /\w/ },
    'At least one profile has an Address1' );

ok( any_profile { ( $_->{Address}{Address2} // '' ) =~ /San Francisco/i },
    'At least one profile has San Francisco in Address2' );

# --- Publications ---

ok(
    any_profile { ( $_->{PublicationCount} // 0 ) >= 50 },
    'At least one profile has 50+ publications'
);

ok(
    any_profile { scalar @{ $_->{Publications} // [] } >= 50 },
    'At least one profile has 50+ publications in array'
);

ok(
    any_profile {
        ( eval { $_->{Publications}[0]{PublicationTitle} } // '' ) =~
          /\w+.*\.\s+\w.*\d{4}/
    },
    'At least one profile has a well-formatted PublicationTitle'
);

ok(
    any_profile {
        scalar( grep { $_->{Featured} } @{ $_->{Publications} // [] } ) >= 1
    },
    'At least one profile has featured publications'
);

ok(
    any_profile {
        scalar( grep { $_->{Claimed} } @{ $_->{Publications} // [] } ) >= 1
    },
    'At least one profile has claimed publications'
);

ok(
    any_profile {
        ( eval { $_->{Publications}[0]{Title} } // '' ) =~ /\w{3}/
    },
    'At least one profile has a short Title on first publication'
);

ok(
    any_profile {
        ( eval { $_->{Publications}[0]{AuthorList} } // '' ) =~ /\w+\s+\w+/
    },
    'At least one profile has an AuthorList on first publication'
);

ok(
    any_profile {
        ( eval { $_->{Publications}[0]{Date} } // '' ) =~ /^\d{4}-\d{2}-\d{2}$/
    },
    'At least one profile has a YYYY-MM-DD Date on first publication'
);

ok(
    any_profile {
        ( eval { $_->{Publications}[0]{PublicationSource}[0]{PMID} } // '' ) =~
          /^\d+$/
    },
    'At least one profile has a numeric PMID in PublicationSource'
);

ok(
    any_profile {
        (
            eval {
                $_->{Publications}[0]{PublicationSource}[0]
                  {PublicationSourceURL};
            } // ''
        ) =~ m{^https?://}
    },
    'At least one profile has a PublicationSourceURL'
);

ok(
    any_profile {
        ( eval { $_->{Publications}[0]{PublicationID} } // '' ) =~ m{^https?://}
    },
    'At least one profile has a PublicationID URL'
);

ok(
    any_profile {
        ( eval { $_->{Publications}[0]{Publication} } // '' ) =~ /\w{3}/
    },
    'At least one profile has a Publication (journal name) on first publication'
);

ok(
    any_profile {
        ( eval { $_->{Publications}[0]{PublicationMedlineTA} } // '' ) =~
          /\w{2}/
    },
    'At least one profile has a PublicationMedlineTA (journal abbreviation)'
);

ok(
    any_profile {
        ( eval { $_->{Publications}[0]{Year} } // '' ) =~ /^\d{4}$/
    },
    'At least one profile has a 4-digit Year on first publication'
);

# Publications are in descending year order
ok(
    any_profile {
        my @years = map { $_->{Year} } @{ $_->{Publications} // [] };
        @years >= 2
          and join( ',', @years ) eq join( ',', sort { $b cmp $a } @years );
    },
    'At least one profile has publications sorted by year descending'
);

ok(
    any_profile {
        (
            eval {
                $_->{Publications}[0]{PublicationSource}[0]
                  {PublicationSourceName};
            } // ''
        ) =~ /\w/
    },
    'At least one profile has a PublicationSourceName on first publication'
);

ok(
    any_profile {
        grep { ( $_->{PublicationCategory} // '' ) =~ /\w/ }
          @{ $_->{Publications} // [] }
    },
    'At least one profile has a PublicationCategory on some publication'
);

# --- Keywords ---

ok(
    any_profile { scalar @{ $_->{Keywords} // [] } >= 5 },
    'At least one profile has 5+ mesh keywords'
);

ok( any_profile { scalar @{ $_->{FreetextKeywords} // [] } >= 3 },
    'At least one profile has 3+ freetext keywords' );

# --- Education & Training ---

ok( any_profile { scalar @{ $_->{Education_Training} // [] } >= 2 },
    'At least one profile has 2+ education entries' );

ok(
    any_profile {
        any { ( $_->{organization} // '' ) =~ /university|college|school/i }
          @{ $_->{Education_Training} // [] }
    },
    'At least one profile has a recognizable institution in Education_Training'
);

ok(
    any_profile {
        any { ( $_->{end_date} // '' ) =~ /^\d{4}$/ }
          @{ $_->{Education_Training} // [] }
    },
    'At least one profile has a 4-digit end_date in Education_Training'
);

ok(
    any_profile {
        any { length( $_->{location} // '' ) > 3 }
          @{ $_->{Education_Training} // [] }
    },
    'At least one profile has a location in Education_Training'
);

ok(
    any_profile {
        any { length( $_->{department_or_school} // '' ) > 3 }
          @{ $_->{Education_Training} // [] }
    },
    'At least one profile has a department_or_school in Education_Training'
);

ok(
    any_profile {
        any { length( $_->{degree} // '' ) > 1 }
          @{ $_->{Education_Training} // [] }
    },
    'At least one profile has a degree in Education_Training'
);

# --- Titles (positions) ---

ok(
    any_profile { scalar @{ $_->{Titles} // [] } >= 1 },
    'At least one profile has a Titles array'
);

ok(
    any_profile {
        scalar( grep { /\w/ } @{ $_->{Titles} // [] } ) >= 1
    },
    'At least one profile has a non-empty string in Titles'
);

# --- Address ---

ok(
    (
        grep {
            defined $profiles_by_username{$_}
              && ( $profiles_by_username{$_}{ProfilesURL} // '' ) =~
              m{profiles\.ucsf\.edu}
          }
          keys %profiles_by_username
    ) == scalar keys %profiles_by_username,
    'All fetched profiles have a ProfilesURL on profiles.ucsf.edu'
);

# --- ClinicalTrials ---

my @all_trials = map { @{ $_->{ClinicalTrials} // [] } } @profiles;

ok( any_profile { scalar @{ $_->{ClinicalTrials} // [] } >= 5 },
    'At least one profile has 5+ clinical trials' );

ok(
    ( grep { ( $_->{ID} // '' ) =~ /^NCT\d+$/ } @all_trials ) >= 5,
    'At least 5 trials across all profiles have valid NCT IDs'
);

ok( ( any { ( $_->{Title} // '' ) =~ /\w{5}/ } @all_trials ),
    'At least one trial has a title' );

ok( ( any { ( $_->{URL} // '' ) =~ m{^https?://} } @all_trials ),
    'At least one trial has a URL' );

ok(
    ( any { ( $_->{StartDate} // '' ) =~ /^\d{4}-\d{2}-\d{2}$/ } @all_trials ),
    'At least one trial has a YYYY-MM-DD StartDate'
);

ok(
    ( any { defined $_->{EndDate} && $_->{EndDate} =~ /^\d{4}/ } @all_trials ),
    'At least one trial has an EndDate'
);

ok(
    (
        any { ref( $_->{Conditions} ) eq 'ARRAY' && @{ $_->{Conditions} } >= 1 }
          @all_trials
    ),
    'At least one trial has a Conditions array'
);

# --- Videos ---

my @all_videos = map { @{ $_->{Videos} // [] } } @profiles;

ok( any_profile { scalar @{ $_->{Videos} // [] } >= 2 },
    'At least one profile has 2+ videos' );

ok( ( any { ( $_->{url} // '' ) =~ /you\.?tu\.?be|youtube/i } @all_videos ),
    'At least one video is from YouTube' );

ok( ( any { ( $_->{url} // '' ) =~ m{^https://} } @all_videos ),
    'At least one video has an https URL' );

ok( ( any { length( $_->{label} // '' ) > 3 } @all_videos ),
    'At least one video has a label' );

ok( scalar @all_videos >= 2,
    'At least 2 videos total across all profiles' );

SKIP: {
    my $p = $profiles_by_username{'kirsten.bibbins-domingo'}
      or skip 'kirsten.bibbins-domingo: no JSON', 3;
    my @vids = @{ $p->{Videos} // [] };
    cmp_ok( scalar @vids, '>=', 2, 'Kirsten: has 2+ videos' );
    ok( ( grep { ( $_->{url} // '' ) =~ /you\.?tu\.?be|youtube/i } @vids ),
        'Kirsten: at least one video is from YouTube' );
    ok( ( grep { length( $_->{label} // '' ) > 0 } @vids ),
        'Kirsten: at least one video has a label' );
}

# --- AwardOrHonors ---

ok( any_profile { scalar @{ $_->{AwardOrHonors} // [] } >= 5 },
    'At least one profile has 5+ awards' );

ok(
    any_profile {
        my $a = ( $_->{AwardOrHonors} // [] )->[0];
        $a and length( $a->{AwardLabel} // '' ) > 3
    },
    'At least one profile has an award with a label'
);

ok(
    any_profile {
        my $a = ( $_->{AwardOrHonors} // [] )->[0];
        $a and length( $a->{AwardConferredBy} // '' ) > 3
    },
    'At least one profile has an award with a conferring body'
);

ok(
    any_profile {
        my @years =
          map { $_->{AwardStartDate} // 0 } @{ $_->{AwardOrHonors} // [] };
        @years >= 2
          and join( ',', @years ) eq join( ',', sort { $b <=> $a } @years );
    },
    'At least one profile has awards sorted descending by year'
);

ok(
    any_profile {
        my $a = ( $_->{AwardOrHonors} // [] )->[0];
        $a and length( $a->{Summary} // '' ) > 5
    },
    'At least one profile has an award with a Summary'
);

ok(
    any_profile {
        grep { ( $_->{AwardEndDate} // '' ) =~ /^\d{4}$/ }
          @{ $_->{AwardOrHonors} // [] }
    },
    'At least one profile has an award with a 4-digit AwardEndDate'
);

# --- ResearchActivitiesAndFunding / Grants ---

ok( any_profile { scalar @{ $_->{ResearchActivitiesAndFunding} // [] } >= 5 },
    'At least one profile has 5+ research activities/grants' );

my @all_grants =
  map { @{ $_->{ResearchActivitiesAndFunding} // [] } } @profiles;

ok( ( any { length( $_->{Title} // '' ) > 5 } @all_grants ),
    'At least one grant has a Title' );

ok( ( any { length( $_->{Sponsor} // '' ) > 1 } @all_grants ),
    'At least one grant has a Sponsor' );

ok( ( any { length( $_->{Role} // '' ) > 1 } @all_grants ),
    'At least one grant has a Role' );

ok(
    ( any { ( $_->{StartDate} // '' ) =~ /^\d{4}-\d{2}-\d{2}$/ } @all_grants ),
    'At least one grant has a YYYY-MM-DD StartDate'
);

ok( ( any { ( $_->{EndDate} // '' ) =~ /^\d{4}-\d{2}-\d{2}$/ } @all_grants ),
    'At least one grant has a YYYY-MM-DD EndDate' );

ok( ( any { ( $_->{SponsorAwardID} // '' ) =~ /\w/ } @all_grants ),
    'At least one grant has a SponsorAwardID' );

# --- NIHGrants_beta (deprecated upstream; prefer ResearchActivitiesAndFunding) ---

my @all_nih = map { @{ $_->{NIHGrants_beta} // [] } } @profiles;

ok( scalar @all_nih >= 1, 'At least one profile has NIHGrants_beta entries' );

ok( ( any { ( $_->{NIHProjectNumber} // '' ) =~ /\w/ } @all_nih ),
    'At least one NIH grant has a project number' );

ok( ( any { ( $_->{Title} // '' ) =~ /\w/ } @all_nih ),
    'At least one NIH grant has a title' );

ok(
    (
        any { defined $_->{NIHFiscalYear} && $_->{NIHFiscalYear} =~ /^\d{4}$/ }
          @all_nih
    ),
    'At least one NIH grant has a 4-digit NIHFiscalYear'
);

# --- WebLinks ---

my @all_weblinks = map { @{ $_->{WebLinks_beta} // [] } } @profiles;

ok( scalar @all_weblinks >= 1, 'At least one profile has web links' );
ok( ( any { ( $_->{URL} // '' ) =~ m{^https?://} } @all_weblinks ),
    'At least one web link has a valid URL' );
ok( ( any { length( $_->{Label} // '' ) > 0 } @all_weblinks ),
    'At least one web link has a label' );

# --- MediaLinks (in the news) ---

my @all_media = map { @{ $_->{MediaLinks_beta} // [] } } @profiles;

ok( scalar @all_media >= 5, 'At least 5 media links across all profiles' );
ok( ( any { length( $_->{link_name} // '' ) > 3 } @all_media ),
    'At least one media link has a name' );
ok( ( any { ( $_->{link_url} // '' ) =~ m{^https?://} } @all_media ),
    'At least one media link has a URL' );
ok(
    ( any { ( $_->{link_date} // '' ) =~ m{^\d{2}/\d{2}/\d{4}$} } @all_media ),
    'At least one media link has a MM/DD/YYYY link_date'
);

# --- GlobalHealth ---
# Data comes entirely from GlobalHealthEquity pluginData.
# Projects is always [] (ORNG hasGlobalHealth gadget is defunct).
# GlobalHealth_beta.Countries should always match GlobalHealth.Locations
# (same underlying data, different shape).

ok( any_profile { scalar @{ $_->{GlobalHealth}{Locations} // [] } >= 1 },
    'At least one profile has GlobalHealth Locations' );
ok( any_profile { scalar @{ $_->{GlobalHealth}{Interests} // [] } >= 1 },
    'At least one profile has GlobalHealth Interests' );
ok( any_profile { scalar @{ $_->{GlobalHealth}{Centers} // [] } >= 1 },
    'At least one profile has GlobalHealth Centers' );
ok( any_profile { scalar @{ $_->{GlobalHealth_beta}{Countries} // [] } >= 1 },
    'At least one profile has GlobalHealth_beta Countries' );

# Projects is always empty — ORNG hasGlobalHealth gadget is defunct
ok(
    ( grep { ref( $_->{GlobalHealth}{Projects} ) eq 'ARRAY' } @loaded ) ==
      scalar @loaded,
    'GlobalHealth Projects is an arrayref on every loaded profile'
);
ok(
    ( grep { scalar @{ $_->{GlobalHealth}{Projects} // [] } == 0 } @loaded ) ==
      scalar @loaded,
    'GlobalHealth Projects is always empty (ORNG gadget defunct)'
);

SKIP: {
    my $p = $profiles_by_username{'jaime.sepulveda'}
      or skip 'jaime.sepulveda: no JSON', 6;
    my $gh  = $p->{GlobalHealth}      // {};
    my $ghb = $p->{GlobalHealth_beta} // {};
    cmp_ok( scalar @{ $gh->{Locations} // [] }, '>=', 5,
        'Jaime Sepulveda: has 5+ GlobalHealth locations' );
    ok( ( grep { /Tanzania/i } @{ $gh->{Locations} // [] } ),
        'Jaime Sepulveda: Tanzania is in GlobalHealth locations' );
    ok( ( grep { /Kenya/i } @{ $gh->{Locations} // [] } ),
        'Jaime Sepulveda: Kenya is in GlobalHealth locations' );
    ok( ( grep { /IGHS/i } @{ $gh->{Centers} // [] } ),
        'Jaime Sepulveda: has an IGHS center' );
    cmp_ok( scalar @{ $gh->{Interests} // [] }, '>=', 2,
        'Jaime Sepulveda: has 2+ GlobalHealth interests' );
    cmp_ok( scalar @{ $ghb->{Countries} // [] }, '>=', 5,
        'Jaime Sepulveda: GlobalHealth_beta has 5+ countries' );
}

SKIP: {
    my $p = $profiles_by_username{'eric.goosby'}
      or skip 'eric.goosby: no JSON', 5;
    my $gh  = $p->{GlobalHealth}      // {};
    my $ghb = $p->{GlobalHealth_beta} // {};
    cmp_ok( scalar @{ $gh->{Locations} // [] }, '>=', 5,
        'Eric Goosby: has 5+ GlobalHealth locations' );
    ok( ( grep { /Sub-Saharan Africa/i } @{ $gh->{Locations} // [] } ),
        'Eric Goosby: Sub-Saharan Africa is in GlobalHealth locations' );
    ok( ( grep { /HIV/i } @{ $gh->{Interests} // [] } ),
        'Eric Goosby: HIV/AIDS is in GlobalHealth interests' );
    ok( ( grep { /IGHS/i } @{ $gh->{Centers} // [] } ),
        'Eric Goosby: has an IGHS center' );
    cmp_ok( scalar @{ $ghb->{Countries} // [] }, '>=', 5,
        'Eric Goosby: GlobalHealth_beta has 5+ countries' );
}

SKIP: {
    my $p = $profiles_by_username{'dilys.walker'}
      or skip 'dilys.walker: no JSON', 5;
    my $gh  = $p->{GlobalHealth}      // {};
    my $ghb = $p->{GlobalHealth_beta} // {};
    cmp_ok( scalar @{ $gh->{Locations} // [] }, '>=', 5,
        'Dilys Walker: has 5+ GlobalHealth locations' );
    ok( ( grep { /Rwanda|Uganda|Kenya/i } @{ $gh->{Locations} // [] } ),
        'Dilys Walker: Africa locations present' );
    ok( ( grep { /maternal|reproductive/i } @{ $gh->{Interests} // [] } ),
        'Dilys Walker: maternal/reproductive health in interests' );
    # Countries should match Locations — this tests the array-pluginData bug fix
    cmp_ok( scalar @{ $ghb->{Countries} // [] }, '>=', 5,
        'Dilys Walker: GlobalHealth_beta has 5+ countries (requires array-pluginData fix)' );
    is_deeply(
        [ sort @{ $ghb->{Countries} // [] } ],
        [ sort @{ $gh->{Locations}  // [] } ],
        'Dilys Walker: GlobalHealth_beta Countries matches GlobalHealth Locations'
    );
}

SKIP: {
    my $p = $profiles_by_username{'michael.lipnick'}
      or skip 'michael.lipnick: no JSON', 3;
    my $gh  = $p->{GlobalHealth}      // {};
    my $ghb = $p->{GlobalHealth_beta} // {};
    cmp_ok( scalar @{ $gh->{Locations} // [] }, '>=', 1,
        'Michael Lipnick: has GlobalHealth locations' );
    ok( ( grep { /Uganda/i } @{ $gh->{Locations} // [] } ),
        'Michael Lipnick: Uganda is in GlobalHealth locations' );
    # Countries should match Locations — this tests the array-pluginData bug fix
    cmp_ok( scalar @{ $ghb->{Countries} // [] }, '>=', 1,
        'Michael Lipnick: GlobalHealth_beta has countries (requires array-pluginData fix)' );
}

SKIP: {
    my $p = $profiles_by_username{'craig.cohen'}
      or skip 'craig.cohen: no JSON', 5;
    my $gh  = $p->{GlobalHealth}      // {};
    my $ghb = $p->{GlobalHealth_beta} // {};
    cmp_ok( scalar @{ $gh->{Locations} // [] }, '>=', 5,
        'Craig Cohen: has 5+ GlobalHealth locations' );
    ok( ( grep { /Kenya/i } @{ $gh->{Locations} // [] } ),
        'Craig Cohen: Kenya is in GlobalHealth locations' );
    ok( ( grep { /HIV|Tuberculosis/i } @{ $gh->{Interests} // [] } ),
        'Craig Cohen: HIV or TB in interests' );
    ok( ( grep { /IGHS/i } @{ $gh->{Centers} // [] } ),
        'Craig Cohen: has an IGHS center' );
    cmp_ok( scalar @{ $ghb->{Countries} // [] }, '>=', 5,
        'Craig Cohen: GlobalHealth_beta has 5+ countries' );
}

# --- FacultyMentoring ---

ok( any_profile { scalar @{ $_->{FacultyMentoring}{Types} // [] } >= 3 },
    'At least one profile has 3+ FacultyMentoring types' );
ok(
    any_profile { length( $_->{FacultyMentoring}{Narrative} // '' ) > 20 },
    'At least one profile has a FacultyMentoring narrative'
);
ok(
    any_profile {
        my @types = @{ $_->{FacultyMentoring}{Types} // [] };
        @types >= 1 and ( grep { /\w/ } @types ) == scalar @types
    },
    'At least one profile has non-empty FacultyMentoring type strings'
);

SKIP: {
    my $p = $profiles_by_username{'claire.brindis'}
      or skip 'claire.brindis: no JSON', 4;
    cmp_ok( scalar @{ $p->{FacultyMentoring}{Types} // [] },
        '>=', 5, 'Claire: has 5+ FacultyMentoring types' );
    ok( ( grep { /\w/ } @{ $p->{FacultyMentoring}{Types} // [] } ),
        'Claire: FacultyMentoring types are non-empty strings' );
    ok( length( $p->{FacultyMentoring}{Narrative} // '' ) > 20,
        'Claire: has a FacultyMentoring narrative' );
    is( ref( $p->{FacultyMentoring}{Types} ),
        'ARRAY', 'Claire: FacultyMentoring Types is an arrayref' );
}

SKIP: {
    my $p = $profiles_by_username{'aaron.neinstein'}
      or skip 'aaron.neinstein: no JSON', 2;
    cmp_ok( scalar @{ $p->{FacultyMentoring}{Types} // [] },
        '>=', 1, 'Aaron Neinstein: has FacultyMentoring types' );
    is( ref( $p->{FacultyMentoring}{Types} ),
        'ARRAY', 'Aaron Neinstein: FacultyMentoring Types is an arrayref' );
}

# --- CollaborationInterests ---

ok(
    any_profile { length( $_->{CollaborationInterests}{Summary} // '' ) > 5 },
    'At least one profile has CollaborationInterests Summary'
);
ok(
    any_profile {
        ref( $_->{CollaborationInterests}{Details} ) eq 'HASH'
          and keys %{ $_->{CollaborationInterests}{Details} } >= 1
    },
    'At least one profile has CollaborationInterests Detail entries'
);
ok(
    any_profile { length( $_->{CollaborationInterests}{Narrative} // '' ) > 20 },
    'At least one profile has CollaborationInterests Narrative'
);
ok(
    any_profile {
        ( $_->{CollaborationInterests}{Summary} // '' ) =~ /\w/
    },
    'At least one profile has a CollaborationInterests Summary with content'
);

SKIP: {
    my $p = $profiles_by_username{'claire.brindis'}
      or skip 'claire.brindis: no JSON', 4;
    ok( length( $p->{CollaborationInterests}{Summary} // '' ) > 5,
        'Claire: has CollaborationInterests Summary' );
    ok( length( $p->{CollaborationInterests}{Narrative} // '' ) > 20,
        'Claire: has CollaborationInterests Narrative' );
    cmp_ok( scalar keys %{ $p->{CollaborationInterests}{Details} // {} },
        '>=', 2, 'Claire: has 2+ CollaborationInterests Detail entries' );
    is( ref( $p->{CollaborationInterests}{Details} ),
        'HASH', 'Claire: CollaborationInterests Details is a hashref' );
}

SKIP: {
    my $p = $profiles_by_username{'aaron.neinstein'}
      or skip 'aaron.neinstein: no JSON', 2;
    ok( length( $p->{CollaborationInterests}{Summary} // '' ) > 5,
        'Aaron Neinstein: has CollaborationInterests Summary' );
    cmp_ok( scalar keys %{ $p->{CollaborationInterests}{Details} // {} },
        '>=', 1, 'Aaron Neinstein: has CollaborationInterests Detail entries' );
}

# --- Twitter_beta backfill from WebLinks ---

SKIP: {
    my $p = $profiles_by_username{'renee.hsia'}
      or skip 'renee.hsia: no JSON', 2;
    my @tw = @{ $p->{Twitter_beta} // [] };
    ok( @tw >= 1,
        'Renee Hsia: has Twitter_beta handle (backfilled from x.com)' );
    like( $tw[0], qr/^ReneeYHsia$/i,
        'Renee Hsia: Twitter handle is ReneeYHsia' );
}

SKIP: {
    my $p = $profiles_by_username{'steven.pantilat'}
      or skip 'steven.pantilat: no JSON', 2;
    my @tw = @{ $p->{Twitter_beta} // [] };
    ok( @tw >= 1,
        'Steven Pantilat: has Twitter_beta handle (backfilled from x.com)' );
    like( $tw[0], qr/^stevepantilat$/i,
        'Steven Pantilat: Twitter handle is stevepantilat' );
}

SKIP: {
    my $p = $profiles_by_username{'aaron.neinstein'}
      or skip 'aaron.neinstein: no JSON', 3;
    my @tw = @{ $p->{Twitter_beta} // [] };
    ok(
        @tw >= 1,
'Aaron Neinstein: has Twitter_beta handle (twitter.com + x.com backfill)'
    );
    like( $tw[0], qr/^AaronNeinstein$/i,
        'Aaron Neinstein: Twitter handle is AaronNeinstein' );
    is(
        scalar @tw,
        1,
'Aaron Neinstein: twitter.com and x.com duplicates collapsed to one entry'
    );
}

# ---------------------------------------------------------------------------
# Structural type guarantees — these fields must be arrayrefs on every loaded
# profile, even when empty. Ensures data-level compatibility is preserved when
# ORNG fallback paths are removed.
# ---------------------------------------------------------------------------

ok(
    ( grep { ref( $_->{SlideShare_beta} ) eq 'ARRAY' } @loaded ) ==
      scalar @loaded,
    'SlideShare_beta is an arrayref on every loaded profile'
);

ok(
    ( grep { ref( $_->{WebLinks_beta} ) eq 'ARRAY' } @loaded ) ==
      scalar @loaded,
    'WebLinks_beta is an arrayref on every loaded profile'
);

ok(
    ( grep { ref( $_->{MediaLinks_beta} ) eq 'ARRAY' } @loaded ) ==
      scalar @loaded,
    'MediaLinks_beta is an arrayref on every loaded profile'
);

ok(
    ( grep { ref( $_->{Videos} ) eq 'ARRAY' } @loaded ) == scalar @loaded,
    'Videos is an arrayref on every loaded profile'
);

ok(
    ( grep { ref( $_->{Publications} ) eq 'ARRAY' } @loaded ) ==
      scalar @loaded,
    'Publications is an arrayref on every loaded profile'
);

ok(
    ( grep { ref( $_->{ClinicalTrials} ) eq 'ARRAY' } @loaded ) ==
      scalar @loaded,
    'ClinicalTrials is an arrayref on every loaded profile'
);

ok(
    ( grep { ref( $_->{AwardOrHonors} ) eq 'ARRAY' } @loaded ) ==
      scalar @loaded,
    'AwardOrHonors is an arrayref on every loaded profile'
);

ok(
    ( grep { ref( $_->{Education_Training} ) eq 'ARRAY' } @loaded ) ==
      scalar @loaded,
    'Education_Training is an arrayref on every loaded profile'
);

ok(
    (
        grep { ref( $_->{FacultyMentoring}{Types} ) eq 'ARRAY' } @loaded
    ) == scalar @loaded,
    'FacultyMentoring Types is an arrayref on every loaded profile'
);

ok(
    ( grep { ref( $_->{CollaborationInterests} ) eq 'HASH' } @loaded ) ==
      scalar @loaded,
    'CollaborationInterests is a hashref on every loaded profile'
);

ok(
    (
        grep {
            !exists $_->{CollaborationInterests}{Details}
              || ref( $_->{CollaborationInterests}{Details} ) eq 'HASH'
        } @loaded
    ) == scalar @loaded,
    'CollaborationInterests Details, when present, is a hashref'
);
