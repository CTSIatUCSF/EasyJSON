#!/usr/bin/perl

package ProfilesEasyJSON::MegaUCSF;
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
        URI->new('https://ucsf.researcherprofiles.org/');
    }
);

has '+legacy_root_domains' => (
    default => sub {
        [ URI->new('http://profiles.ucsf.edu/') ]
    }
);

###############################################################################

around 'identifier_to_canonical_url' => sub {

    my ( $orig, $self, $identifier_type, $identifier, $options ) = @_;
    $options ||= {};

    my ( $final_identifier_type, $final_identifier )
        = preprocess_ucsf_identifier( $identifier_type, $identifier, $options );

    if ( $final_identifier_type and $final_identifier ) {
        return
            $orig->( $self, $final_identifier_type, $final_identifier, $options
            );
    }

    warn "Could not process this UCSF identifier (", dump($identifier_type),
        " = ", dump($identifier), ")";
    return;
};

###############################################################################

# given an identifier and type, returns a cleaned-up identifier and type

# - lets through Pretty URLs
# - translates ProfilesNodeIDs via lookup table, or lets them through
# - translates person IDs via lookup table
# - translates employee IDs into EPPN/Username via either lookup table or algorithm
# - translates FNO via lookup table
# - lets through EPPNs
# - simplifies URL, then re-runs

# we can only emit PrettyURLs and EPPNs. That's it.

my $lookup_table = _load_lookup_table();

sub preprocess_ucsf_identifier {

    my ( $identifier_type, $identifier, $options ) = @_;
    $options ||= {};

    my $identifier_types = {

        'EmployeeID'     => { lookup      => 1, translate   => 1 },
        'EPPN'           => { passthrough => 1 },
        'FNO'            => { lookup      => 1 },
        'Person'         => { lookup      => 1, translate   => 1 },
        'PrettyURL'      => { passthrough => 1 },
        'ProfilesNodeID' => { lookup      => 1, passthrough => 1 },
        'URL'            => { expand      => 1 },

    };

    # stage 0: did we even get an identifier type + identifier?
    unless ( $identifier_types->{$identifier_type} ) {
        warn 'Unknown identifier type: ' . dump($identifier_type), "\n";
        return;
    }
    unless ( defined $identifier and $identifier =~ m/\w/ ) {
        warn 'Unknown identifier: ' . dump($identifier), "\n";
        return;
    }

    # stage 1: expand
    if ( $identifier_types->{$identifier_type}->{expand} ) {

        if ( $identifier_type eq 'URL' ) {

            my $current_or_legacy_profiles_root_url_regexp
                = qr{https?://(?:profiles.ucsf.edu|(?:(?:stage|ucsf|stage-ucsf)\.)?researcherprofiles\.org)}i;

            if ( $identifier
                =~ m{$current_or_legacy_profiles_root_url_regexp/ProfileDetails\.aspx\?Person=(\d+)$}i
            ) {
                $identifier_type = 'Person';
                $identifier      = $1;
            } elsif ( $identifier
                =~ m{$current_or_legacy_profiles_root_url_regexp/([a-zA-Z\.]*[a-z-\.]+\d*)$}
            ) {
                $identifier_type = 'PrettyURL';
                $identifier      = lc $1;
            } elsif ( $identifier
                =~ m{$current_or_legacy_profiles_root_url_regexp/profile/(\d+)$}
            ) {
                $identifier_type = 'ProfilesNodeID';
                $identifier      = $1;
            } else {
                my $example_root = "http://profiles.ucsf.edu";
                warn 'Unrecognized URL ', dump($identifier),
                    qq{ (was expecting something like "$example_root/clay.johnston" or "$example_root/ProfileDetails.aspx?Person=5036574")},
                    "\n";
                return;
            }
        } else {
            warn "Don't know how to expand identifier type $identifier_type";
            return;
        }

    }

    # stage 2: lookup
    if ( $identifier_types->{$identifier_type}->{lookup} ) {

        my %identifiers_to_check;
        $identifiers_to_check{$identifier} = 1;
        $identifiers_to_check{ lc $identifier } = 1;
        if ( $identifier_type eq 'FNO' and $identifier =~ m/^(.+)@/ ) {
            $identifiers_to_check{ lc $1 } = 1;
        }

        foreach my $possible_identifier ( keys %identifiers_to_check ) {
            if (eval {
                    $lookup_table->{$identifier_type}->{$possible_identifier};
                }
            ) {
                return ( 'PrettyURL',
                      $lookup_table->{$identifier_type}->{$possible_identifier},
                      $options );
            }
        }
    }

    # stage 3: translate
    if ( $identifier_types->{$identifier_type}->{translate} ) {
        if ( $identifier_type eq 'Person' ) {
            if ( $identifier > 1_000_000 ) {
                my $new_identifier = substr( ( $identifier - 569307 ), 1, 6 );
                if ( $new_identifier >= 100000 ) {
                    return ( 'UserName', "$new_identifier\@ucsf.edu",
                             $options );
                }
            }
        } elsif ( $identifier_type eq 'EmployeeID' ) {
            if ( $identifier =~ m/^02(\d{3,})\d$/ ) {
                return ( 'UserName', "$1\@ucsf.edu", $options );
            }
        } else {
            warn "Don't know how to expand identifier type $identifier_type";
            return;
        }
    }

    # stage 4: passthrough
    if ( $identifier_types->{$identifier_type}->{passthrough} ) {

        if ( $identifier_type eq 'PrettyURL' ) {
            if ( $identifier =~ m/\./ and $identifier =~ m/[a-z]{2,}/i ) {
                return ( $identifier_type, $identifier, $options );
            } else {
                warn "Invalid Profiles URL username format: '$identifier'";
                return;
            }
        } elsif ( $identifier_type eq 'EPPN' ) {
            if ( $identifier =~ m/\w.*\@.*\w/ ) {
                return ( 'UserName', $identifier, $options );
            } else {
                warn "Invalid EPPN format: '$identifier'";
                return;
            }
        } elsif ( $identifier_type eq 'ProfilesNodeID' ) {
            if ( $identifier =~ m/^\d\d+$/ ) {
                return ( $identifier_type, $identifier, $options );
            } else {
                warn "Invalid Profiles node ID format: '$identifier'";
                return;
            }
        } else {
            warn "Don't know how to validate identifier type $identifier_type";
            return;
        }
    }

    warn
        "Could not process this UCSF identifier ($identifier_type = $identifier)";
    return;
}

sub _load_lookup_table {

    my $table = {};

    my @files;
    my @dir_options = ( "$ENV{HOME}/profiles-mega-mapping-tables",
                        "/srv/profiles-mega-mapping-tables",
                        "/etc/profiles-mega-mapping-tables"
    );
    foreach my $dir_option (@dir_options) {
        if ( -d $dir_option ) {
            @files = io->dir("$ENV{HOME}/profiles-mega-mapping-tables")->all;
            if (@files) {
                last;
            } else {
                next;
            }
        }
    }

    unless (@files) {
        warn "Could not find user mapping tables";
        return $table;
    }

    foreach my $file (@files) {

        next unless ( "$file" =~ m/\.csv$/ );

        my $data = Text::CSV::Slurp->load( string => $file->all );

        foreach my $record ( @{$data} ) {

            # can we expand to a final form?
            if ( $record->{PrettyURL} ) {

                # strip the prefix
                $record->{PrettyURL} =~ s{^.*/}{};

                foreach my $field ( keys %{$record} ) {
                    next if $field eq 'PrettyURL';
                    next if $field eq 'Name';
                    next
                        unless defined $record->{$field}
                        and length $record->{$field};

                    $table->{$field}->{ $record->{$field} }
                        = $record->{PrettyURL};
                }
            }
        }
    }

    return $table;
}

1;

# Local Variables:
# mode: perltidy
# End:
