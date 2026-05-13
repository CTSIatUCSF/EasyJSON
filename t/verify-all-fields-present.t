#!perl

# Comprehensive field coverage tests using three well-populated profiles:
# Vanessa Jacoby, Kirsten Bibbins-Domingo, and Claire Brindis.
#
# The strategy: verify that each output field is populated on AT LEAST ONE
# of the three profiles, rather than assuming any one person always has it.
# Identity facts (name, department, etc.) are still tied to a specific person.

use lib 'lib', '../lib';
use JSON qw( decode_json );
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

my %profile_for;
for my $u ( 'vanessa.jacoby', 'kirsten.bibbins-domingo', 'claire.brindis' ) {
    my $json = $api->identifier_to_json( 'PrettyURL', $u );
    $profile_for{$u} = decode_json($json)->{Profiles}[0] if $json;
}

my @profiles = values %profile_for;

plan tests => 67;

# ---------------------------------------------------------------------------
# Helper: true if any profile satisfies the test
sub any_profile (&) {
    my $code = shift;
    return any { do { local $_ = $_; $code->() } } @profiles;
}

###############################################################################
# Basic identity checks — these are facts tied to a specific person
###############################################################################

SKIP: {
    my $p = $profile_for{'vanessa.jacoby'}
        or skip 'vanessa.jacoby: no JSON', 7;
    is( $p->{Name},      'Vanessa Jacoby, MD, MAS', 'Vanessa: full name'     );
    is( $p->{FirstName}, 'Vanessa',                  'Vanessa: first name'    );
    is( $p->{LastName},  'Jacoby',                   'Vanessa: last name'     );
    like( $p->{Department}, qr/ob.?gyn|reproductive/i, 'Vanessa: department' );
    like( $p->{School},     qr/medicine/i,              'Vanessa: school'     );
    like( $p->{ProfilesURL}, qr{profiles\.ucsf\.edu/vanessa\.jacoby},
        'Vanessa: ProfilesURL' );
    like( $p->{Narrative}, qr/fibroid/i, 'Vanessa: narrative mentions fibroids' );
}

SKIP: {
    my $p = $profile_for{'kirsten.bibbins-domingo'}
        or skip 'kirsten.bibbins-domingo: no JSON', 4;
    like( $p->{Name},       qr/Kirsten Bibbins-Domingo/, 'Kirsten: full name'   );
    like( $p->{Department}, qr/epidemiology/i,           'Kirsten: department'  );
    like( $p->{School},     qr/medicine/i,               'Kirsten: school'      );
    like( join( ' ', @{ $p->{Keywords} } ), qr/cardiovascular/i,
        'Kirsten: mesh keywords include cardiovascular' );
}

SKIP: {
    my $p = $profile_for{'claire.brindis'}
        or skip 'claire.brindis: no JSON', 4;
    like( $p->{Name},       qr/Claire Brindis/,  'Claire: full name'   );
    like( $p->{Department}, qr/health policy/i,  'Claire: department'  );
    like( $p->{School},     qr/medicine/i,        'Claire: school'      );
    ok( length( $p->{Narrative} // '' ) >= 100,   'Claire: has a substantive narrative' );
}

###############################################################################
# Cross-profile field coverage — at least ONE of the three must have each field
###############################################################################

# --- Identity / basic fields ---

ok( any_profile { $_->{Title} =~ /professor/i },
    'At least one profile has a Professor title' );

ok( any_profile { ( $_->{ORCID} // '' ) =~ /^\d{4}-\d{4}-\d{4}-\d{4}$/ },
    'At least one profile has a well-formed ORCID' );

ok( any_profile { ( $_->{PhotoURL} // '' ) =~ /PhotoHandler\.ashx/ },
    'At least one profile has a PhotoURL' );

ok( any_profile { ( $_->{Address}{Telephone} // '' ) =~ /^415-/ },
    'At least one profile has a 415 phone number' );

ok( any_profile {
        defined $_->{Address}{Latitude}
        and abs( $_->{Address}{Latitude} - 37.7 ) < 1
    },
    'At least one profile has SF-area latitude'
);

ok( any_profile {
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

ok( any_profile { ( $_->{PublicationCount} // 0 ) >= 50 },
    'At least one profile has 50+ publications' );

ok( any_profile { scalar @{ $_->{Publications} // [] } >= 50 },
    'At least one profile has 50+ publications in array' );

ok( any_profile {
        ( eval { $_->{Publications}[0]{PublicationTitle} } // '' )
            =~ /\w+.*\.\s+\w.*\d{4}/
    },
    'At least one profile has a well-formatted PublicationTitle'
);

ok( any_profile { scalar( grep { $_->{Featured} } @{ $_->{Publications} // [] } ) >= 1 },
    'At least one profile has featured publications' );

ok( any_profile { scalar( grep { $_->{Claimed}  } @{ $_->{Publications} // [] } ) >= 1 },
    'At least one profile has claimed publications' );

# Publications are in descending year order
ok( any_profile {
        my @years = map { $_->{Year} } @{ $_->{Publications} // [] };
        @years >= 2
            and join( ',', @years ) eq join( ',', sort { $b cmp $a } @years );
    },
    'At least one profile has publications sorted by year descending'
);

# --- Keywords ---

ok( any_profile { scalar @{ $_->{Keywords} // [] } >= 5 },
    'At least one profile has 5+ mesh keywords' );

ok( any_profile { scalar @{ $_->{FreetextKeywords} // [] } >= 3 },
    'At least one profile has 3+ freetext keywords' );

# --- Education & Training ---

ok( any_profile { scalar @{ $_->{Education_Training} // [] } >= 2 },
    'At least one profile has 2+ education entries' );

ok( any_profile {
        any { ( $_->{organization} // '' ) =~ /university|college|school/i }
            @{ $_->{Education_Training} // [] }
    },
    'At least one profile has a recognizable institution in Education_Training'
);

# --- Titles (positions) ---

ok( any_profile { scalar @{ $_->{Titles} // [] } >= 1 },
    'At least one profile has a Titles array' );

# --- Address ---

ok( ( grep { defined $profile_for{$_} && ( $profile_for{$_}{ProfilesURL} // '' ) =~ m{profiles\.ucsf\.edu} }
        keys %profile_for ) == scalar keys %profile_for,
    'All fetched profiles have a ProfilesURL on profiles.ucsf.edu'
);

# --- ClinicalTrials ---

ok( any_profile { scalar @{ $_->{ClinicalTrials} // [] } >= 3 },
    'At least one profile has 3+ clinical trials' );

my @all_trials = map { @{ $_->{ClinicalTrials} // [] } } @profiles;

ok( ( grep { ( $_->{ID} // '' ) =~ /^NCT\d+$/ } @all_trials ) >= 3,
    'At least 3 trials across all profiles have valid NCT IDs' );

ok( (any { ( $_->{Title} // '' ) =~ /\w{5}/ } @all_trials),
    'At least one trial has a title' );

ok( (any { ( $_->{URL} // '' ) =~ m{^https?://} } @all_trials),
    'At least one trial has a URL' );

ok( (any { ( $_->{StartDate} // '' ) =~ /^\d{4}-\d{2}-\d{2}$/ } @all_trials),
    'At least one trial has a YYYY-MM-DD StartDate' );

ok( (any { defined $_->{EndDate} && $_->{EndDate} =~ /^\d{4}/ } @all_trials),
    'At least one trial has an EndDate' );

ok( (any { ref( $_->{Conditions} ) eq 'ARRAY' && @{ $_->{Conditions} } >= 1 } @all_trials),
    'At least one trial has a Conditions array' );

# --- Videos ---

my @all_videos = map { @{ $_->{Videos} // [] } } @profiles;

ok( scalar @all_videos >= 1,
    'At least one profile has videos' );

ok( (any { ( $_->{url} // '' ) =~ /you\.?tu\.?be|youtube/i } @all_videos),
    'At least one video is from YouTube' );

ok( (any { length( $_->{label} // '' ) > 3 } @all_videos),
    'At least one video has a label' );

# --- AwardOrHonors ---

ok( any_profile { scalar @{ $_->{AwardOrHonors} // [] } >= 5 },
    'At least one profile has 5+ awards' );

ok( any_profile {
        my $a = ( $_->{AwardOrHonors} // [] )->[0];
        $a and length( $a->{AwardLabel} // '' ) > 3
    },
    'At least one profile has an award with a label'
);

ok( any_profile {
        my $a = ( $_->{AwardOrHonors} // [] )->[0];
        $a and length( $a->{AwardConferredBy} // '' ) > 3
    },
    'At least one profile has an award with a conferring body'
);

ok( any_profile {
        my @years = map { $_->{AwardStartDate} // 0 } @{ $_->{AwardOrHonors} // [] };
        @years >= 2
            and join( ',', @years ) eq join( ',', sort { $b <=> $a } @years );
    },
    'At least one profile has awards sorted descending by year'
);

# --- ResearchActivitiesAndFunding / Grants ---

ok( any_profile { scalar @{ $_->{ResearchActivitiesAndFunding} // [] } >= 5 },
    'At least one profile has 5+ research activities/grants' );

# --- WebLinks ---

my @all_weblinks = map { @{ $_->{WebLinks_beta} // [] } } @profiles;

ok( scalar @all_weblinks >= 1, 'At least one profile has web links' );
ok( (any { ( $_->{URL}   // '' ) =~ m{^https?://} } @all_weblinks),
    'At least one web link has a valid URL' );
ok( (any { length( $_->{Label} // '' ) > 0 } @all_weblinks),
    'At least one web link has a label' );

# --- MediaLinks (in the news) ---

my @all_media = map { @{ $_->{MediaLinks_beta} // [] } } @profiles;

ok( scalar @all_media >= 5, 'At least 5 media links across all profiles' );
ok( (any { length( $_->{link_name} // '' ) > 3 } @all_media),
    'At least one media link has a name' );
ok( (any { ( $_->{link_url} // '' ) =~ m{^https?://} } @all_media),
    'At least one media link has a URL' );

# --- GlobalHealth ---

ok( any_profile { scalar @{ $_->{GlobalHealth}{Locations} // [] } >= 1 },
    'At least one profile has GlobalHealth Locations' );
ok( any_profile { scalar @{ $_->{GlobalHealth}{Interests} // [] } >= 1 },
    'At least one profile has GlobalHealth Interests' );
ok( any_profile { scalar @{ $_->{GlobalHealth}{Centers} // [] } >= 1 },
    'At least one profile has GlobalHealth Centers' );

# --- FacultyMentoring ---

ok( any_profile { scalar @{ $_->{FacultyMentoring}{Types} // [] } >= 3 },
    'At least one profile has 3+ FacultyMentoring types' );
ok( any_profile { length( $_->{FacultyMentoring}{Narrative} // '' ) > 20 },
    'At least one profile has a FacultyMentoring narrative' );
ok( any_profile {
        my @types = @{ $_->{FacultyMentoring}{Types} // [] };
        @types >= 1 and ( grep { /\w/ } @types ) == scalar @types
    },
    'At least one profile has non-empty FacultyMentoring type strings'
);

# --- CollaborationInterests ---

ok( any_profile { length( $_->{CollaborationInterests}{Summary} // '' ) > 5 },
    'At least one profile has CollaborationInterests Summary' );
ok( any_profile {
        ref( $_->{CollaborationInterests}{Details} ) eq 'HASH'
        and keys %{ $_->{CollaborationInterests}{Details} } >= 1
    },
    'At least one profile has CollaborationInterests Detail entries'
);
ok( any_profile { length( $_->{CollaborationInterests}{Narrative} // '' ) > 20 },
    'At least one profile has CollaborationInterests Narrative' );
ok( any_profile {
        ( $_->{CollaborationInterests}{Summary} // '' ) =~ /\w/
    },
    'At least one profile has a CollaborationInterests Summary with content'
);
