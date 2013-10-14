#!/usr/bin/perl

# TODO:
# disable JSON pretty encoding in mobile view?
# add timeout support?

package ProfilesEasyJSON;
use CHI;
use Data::Dump qw( dump );
use Encode qw( encode );
use JSON;
use LWP::UserAgent 6.0;
use String::Util qw( trim );
use URI::Escape qw( uri_escape );
binmode STDOUT, ':utf8';
use parent qw( Exporter );
use strict;
use warnings;

our @EXPORT_OK
    = qw( identifier_to_json identifier_to_canonical_url canonical_url_to_json );

my ( $i2c_cache, $c2j_cache, $json_obj, $ua );

sub identifier_to_json {
    my ( $identifier_type, $identifier, $options ) = @_;
    $options ||= {};

    my $canonical_url
        = identifier_to_canonical_url( $identifier_type, $identifier,
                                       $options );
    if ($canonical_url) {
        my $json = canonical_url_to_json( $canonical_url, $options );
        if ($json) {
            return $json;
        }
    }
    return;
}

# given an identifier (like an FNO), returns the canonical Profiles URL
sub identifier_to_canonical_url {
    my ( $identifier_type, $identifier, $options ) = @_;
    $options ||= {};

    unless ( defined $identifier and $identifier =~ m/\w/ ) {
        warn 'Unknown identifier: ' . dump($identifier), "\n";
        return;
    }

    $i2c_cache ||= CHI->new(
                 driver    => 'File',
                 namespace => 'Profiles JSON API identifier_to_canonical_url',
                 expires_variance => 0.25,
    );

    my $cache_key = join "\t", ( $identifier_type || '' ),
        ( $identifier || '' );

    # cache_key should usually work, but in case the identifier is
    # something like "John.Smith" we actually want to check to see if
    # we can match that against "john.smith"
    my $cache_key_alt = join "\t", ( $identifier_type || '' ),
        lc( $identifier || '' );

    unless ( $options->{cache} and $options->{cache} eq 'never' ) {
        my $canonical_url = $i2c_cache->get($cache_key);
        if ( !$canonical_url and $cache_key_alt ne $cache_key ) {
            $canonical_url = $i2c_cache->get($cache_key_alt);
        }
        if ($canonical_url) {
            return $canonical_url;
        }
    }

    my $node_uri;

    if (    $identifier_type eq 'FNO'
         or $identifier_type eq 'Person'
         or $identifier_type eq 'EmployeeID'
         or $identifier_type eq 'PrettyURL'
         or $identifier_type eq 'ProfilesNodeID'
         or $identifier_type eq 'URL' ) {

        if ( $identifier_type eq 'ProfilesNodeID' ) {
            if ( $identifier =~ m/^(\d\d+)$/ ) {
                return "http://profiles.ucsf.edu/profile/$1";
            } else {
                warn "Expected to see an all-numeric ProfilesNodeID";
                return;
            }
        } elsif ( $identifier_type eq 'PrettyURL' ) {
            $identifier = lc $identifier;
        } elsif ( $identifier_type eq 'URL' ) {
            if ( $identifier
                =~ m{^https?://profiles.ucsf.edu/ProfileDetails\.aspx\?Person=(\d+)$}
                ) {
                $identifier      = $1;
                $identifier_type = 'Person';
            } elsif ( $identifier
                 =~ m{^https?://profiles.ucsf.edu/([a-zA-Z][a-z-\.]+\d*)$} ) {
                $identifier      = lc $1;
                $identifier_type = 'PrettyURL';
            } elsif (
                $identifier =~ m{^https?://profiles.ucsf.edu/profile/(\d+)$} )
            {
                return $identifier;    # if passed a canonical URL, return it
            } else {
                warn 'Unrecognized URL ', dump($identifier),
                    ' (was expecting something like "http://profiles.ucsf.edu/clay.johnston" or "http://profiles.ucsf.edu/ProfileDetails.aspx?Person=5036574")',
                    "\n";
                return;
            }
        }

        my $url
            = "http://profiles.ucsf.edu/CustomAPI/v2/Default.aspx?"
            . uri_escape($identifier_type) . '='
            . uri_escape($identifier);

        _init_ua() unless $ua;
        my $response = $ua->get($url);
        if ( !$response->is_success ) {

            if ( $i2c_cache->exists_and_is_expired($url) ) {
                my $potential_expired_cache_object
                    = $i2c_cache->get_object($url);
                if ($potential_expired_cache_object) {
                    $node_uri = $potential_expired_cache_object->value();
                    if ($node_uri) {
                        return $node_uri;
                    }
                }
            }

            my $status_line = $response->status_line;
            warn
                "Sorry, we could not return results due to an internal UCSF Profiles error (couldn't load internal URL $url / $status_line)\n";
            return;
        } elsif ( $response->base->path =~ m{^/Error/} ) {
            warn "Tried to look up user '$identifier', but got no results\n";
            return;
        }

        my $raw = $response->decoded_content;
        if ( $raw =~ m{rdf:about="(http.*?)"} ) {
            $node_uri = $1;
            eval { $i2c_cache->set( $cache_key, $node_uri, '3 months' ) };
            return $node_uri;
        } else {
            warn
                "Scanned URL $url for the original rdf:about node URI, but couldn't find it\n";
            return;
        }

    } else {
        warn 'Unknown identifier type ', dump($identifier_type), "\n";
        return;
    }
    return;
}

# given a canonical URL, returns our custom JSON for that person
sub canonical_url_to_json {

    my $canonical_url = shift;
    my $options = shift || {};
    my @api_notes;

    unless (     $options->{cache}
             and $options->{cache} =~ m/^(fallback|always|never)$/ ) {
        $options->{cache} = 'fallback';
    }

    unless ( defined $canonical_url
         and $canonical_url =~ m{^http://profiles.ucsf.edu/profile/(\d+)$} ) {
        warn 'Invalid canonical URL: ', dump($canonical_url), "\n";
        return;
    }

    $c2j_cache ||= CHI->new(
             driver    => 'File',
             namespace => 'Profiles JSON API canonical_url_to_json URL cache',
             expires_variance => 0.25,
    );

    my $node_id = $1;
    my $expanded_rdf_url
        = 'http://profiles.ucsf.edu/CustomAPI/v2/Default.aspx?Subject='
        . uri_escape($node_id)
        . '&ShowDetails=True&Expand=True';
    my $expanded_jsonld_url
        = 'http://stage-profiles.ucsf.edu/shindigorng/rest/rdf?userId='
        . uri_escape($expanded_rdf_url);
    my $raw_json;

    if ( $options->{cache} eq 'always' ) {
        my $cache_object = $c2j_cache->get_object($expanded_jsonld_url);
        if ($cache_object) {
            $raw_json = $cache_object->value;
            if ($raw_json) {
                push @api_notes,
                      'You requested cached data. This data was cached on '
                    . scalar( localtime( $cache_object->created_at() ) )
                    . '.';
            }
        }
    } elsif ( $options->{cache} eq 'fallback' ) {
        $raw_json = $c2j_cache->get($expanded_jsonld_url);
        if ($raw_json) {
            my $cache_object = $c2j_cache->get_object($expanded_jsonld_url);
            if ($cache_object) {
                push @api_notes,
                    'To maximize performance, we are providing recently-cached data. This data was cached on '
                    . scalar( localtime( $cache_object->created_at() ) )
                    . '.';
            }
        }
    }
    if ( !$raw_json ) {
        _init_ua() unless $ua;
        my $response = $ua->get($expanded_jsonld_url);
        if ( $response->is_success ) {
            push @api_notes,
                'This data was retrieved live from our database at '
                . scalar(localtime);
            $raw_json = $response->decoded_content;
            eval {
                $c2j_cache->set( $expanded_jsonld_url, $raw_json,
                                 '23.5 hours' );
            };
        } else {
            warn "Could not load URL ", dump($expanded_jsonld_url),
                " to look up JSON-LD (",
                $response->status_line, ")\n";
            if (     $options->{cache} ne 'never'
                 and $c2j_cache->exists_and_is_expired($expanded_jsonld_url) )
            {
                my $cache_object
                    = $c2j_cache->get_object($expanded_jsonld_url);
                if ($cache_object) {
                    $raw_json = $cache_object->value() || undef;
                    if ($raw_json) {
                        push @api_notes,
                            'We could not connect to our database right now, so we are providing cached data. This data was cached on '
                            . scalar(
                                    localtime( $cache_object->created_at() ) )
                            . '.';
                    }
                }
            }
        }
    }
    if ( !$raw_json ) {
        return;
    }

    $json_obj ||= JSON->new->pretty(1);
    my $data = $json_obj->decode($raw_json);

    my $person;
    my %items_by_url_id;
    my %publications_by_author;

    foreach my $item ( @{ $data->{entry}->{jsonld}->{'@graph'} } ) {

        next unless $item->{'@type'};

        # ensure list of types ALWAYS represented as an array
        unless ( ref $item->{'@type'} eq 'ARRAY' ) {
            $item->{'@type'} = [ $item->{'@type'} ];
        }

        # handle main person
        if ( $item->{'@id'} eq $canonical_url ) {
            $person = $item;
        }

        # handle authorship
        if ( grep { $_ eq 'Authorship' } @{ $item->{'@type'} } ) {
            if (     $item->{linkedAuthor}
                 and $item->{linkedInformationResource} ) {
                push @{ $publications_by_author{ $item->{linkedAuthor} } },
                    $item->{linkedInformationResource};
            }
        }

        $items_by_url_id{ $item->{'@id'} } = $item;
    }

    unless ($person) {
        warn
            "Scanned the contents of URL $expanded_jsonld_url, but could not find a person\n";
        return;
    }

    # ensure there's only one of the following...
    foreach my $field (
        qw( email fullName firstName lastName mailingAddress phoneNumber faxNumber latitude longitude mainImage preferredTitle personInPrimaryPosition )
        ) {
        if ( eval { ref $person->{$field} eq 'ARRAY' } ) {
            $person->{$field} = $person->{$field}->[0];
        }
    }

    # merge with return if there are multiple of the following...
    foreach my $field (qw( freetextKeyword overview )) {
        if ( eval { ref $person->{$field} eq 'ARRAY' } ) {
            $person->{$field} = join "\n", @{ $person->{$field} };
        }
    }

    # ensure that data is set up as an array
    foreach my $field (qw( hasResearchArea awardOrHonor personInPosition )) {
        if ( !defined $person->{$field} ) {
            $person->{$field} = [];
        } elsif ( !ref $person->{$field} or ref $person->{$field} ne 'ARRAY' )
        {
            $person->{$field} = [ $person->{$field} ];
        }
    }

    # warn $json_obj->encode($person);

    my $final_data = {
        Profiles => [
            {  Name        => $person->{fullName},
               FirstName   => $person->{firstName},
               LastName    => $person->{lastName},
               ProfilesURL => $person->{'@id'},

               Email   => $person->{email},
               Address => {
                   Address1 => eval {
                       $items_by_url_id{ $person->{mailingAddress} }
                           ->{address1};
                   },
                   Address2 => eval {
                       $items_by_url_id{ $person->{mailingAddress} }
                           ->{address2};
                   },
                   Address3 => eval {
                       $items_by_url_id{ $person->{mailingAddress} }
                           ->{address3};
                   },
                   Address4 => eval {
                       $items_by_url_id{ $person->{mailingAddress} }
                           ->{address4};
                   },
                   Telephone => $person->{phoneNumber},
                   Fax       => $person->{faxNumber},
                   Latitude  => $person->{latitude} + 0,
                   Longitude => $person->{longitude} + 0,
               },

               # only handling primary department at this time
               Department => eval {
                   $items_by_url_id{
                       $items_by_url_id{
                                  $person->{personInPrimaryPosition}
                               || $person->{personInPosition}->[0]
                           }->{positionInDepartment}
                       }->{label};
               },

               # only handling primary school at this time
               School => eval {
                   no warnings;
                   return
                       $items_by_url_id{ $items_by_url_id{ $person
                               ->{personInPosition}->[0] }
                           ->{positionInOrganization} }->{label};
               },

               # can handle multiple titles
               # but we're only listing first title at this time
               Title  => $person->{preferredTitle},
               Titles => [ $person->{preferredTitle} ],

               Narrative => $person->{overview},

               PhotoURL => $person->{mainImage},
               PublicationCount =>
                   eval { scalar @{ $person->{authorInAuthorship} } + 0 }
                   || 0,

               #CoAuthors     => ['???'], # need to handle <- name
               #SimilarPeople => ['???'], # need to handle <- name

               Keywords => [
                   eval {
                       map { $items_by_url_id{$_}->{label} }
                           @{ $person->{hasResearchArea} };
                   }
               ],

               FreetextKeywords => [
                   eval {
                       if ( defined $person->{freetextKeyword} ) {
                           return map { trim($_) }
                               split qr/\s*,\s*|\s*[\r\n]+\s*/,
                               $person->{freetextKeyword};
                       } else {
                           return;
                       }
                   }
               ],

               AwardOrHonors => [
                   sort {
                       $b->{AwardStartDate} cmp $a->{AwardStartDate}
                       } eval {
                       map {
                           {  Summary =>
                                  join(
                                     ', ',
                                     grep {defined}
                                         $items_by_url_id{$_}->{label},
                                     $items_by_url_id{$_}->{awardConferredBy},
                                     ( join '-',
                                       grep {defined} (
                                            $items_by_url_id{$_}->{startDate},
                                            $items_by_url_id{$_}->{endDate}
                                       )
                                     )
                                  ),
                              AwardLabel => $items_by_url_id{$_}->{label},
                              AwardConferredBy =>
                                  $items_by_url_id{$_}->{awardConferredBy},
                              AwardStartDate =>
                                  $items_by_url_id{$_}->{startDate},
                              AwardEndDate => $items_by_url_id{$_}->{endDate},
                           }
                       } @{ $person->{awardOrHonor} };
                   }
               ],

               Publications => [
                   (  $options->{no_publications}
                      ? ()
                      : map {
                          {

                              # PublicationAddedBy => '?',
                              PublicationID => $_,

#                              _title_to_title_parts(
#                                          $items_by_url_id{$_}
#                                              ->{informationResourceReference}
#                              ),

                              AuthorList => (
                                         $items_by_url_id{$_}->{hasAuthorList}
                                             || undef
                              ),
                              Publication => (
                                   $items_by_url_id{$_}->{hasPublicationVenue}
                                       || undef
                              ),
                              PublicationMedlineTA => (
                                    $items_by_url_id{$_}->{medlineTA} || undef
                              ),
                              Title =>
                                  ( $items_by_url_id{$_}->{label} || undef ),
                              Date => ($items_by_url_id{$_}->{publicationDate}
                                           || undef
                              ),
                              Year =>
                                  ( $items_by_url_id{$_}->{year} || undef ),

                              PublicationTitle => $items_by_url_id{$_}
                                  ->{informationResourceReference},
                              PublicationSource => [
                                  {  PublicationSourceName => (
                                                  $items_by_url_id{$_}->{pmid}
                                                  ? 'PubMed'
                                                  : undef
                                     ),
                                     PublicationSourceURL => (
                                         $items_by_url_id{$_}->{pmid}
                                         ? ( $options->{mobile}
                                             ? "http://www.ncbi.nlm.nih.gov/m/pubmed/$items_by_url_id{$_}->{pmid}"
                                             : "http://www.ncbi.nlm.nih.gov/pubmed/$items_by_url_id{$_}->{pmid}"
                                             )
                                         : undef
                                     ),
                                     PMID => (
                                         $items_by_url_id{$_}->{pmid} || undef
                                     ),
                                  }
                              ],

                              # add other details?
                              #		    src => $items_by_url_id{$_},
                          }
                          } @{ $publications_by_author{ $person->{'@id'} } }
                   )
               ],

            }
        ]
    };

    foreach my $person_data ( @{ $final_data->{Profiles} } ) {
        @{ $person_data->{Publications} } = sort { $b->{Date} cmp $a->{Date} }
            @{ $person_data->{Publications} };
    }

    if (@api_notes) {
        $final_data->{api_notes} = join ' ', @api_notes;
    }

    my $out = encode( 'utf8', $json_obj->encode($final_data) );
    return $out;
}

###############################################################################

sub _init_ua {
    unless ($ua) {
        $ua = LWP::UserAgent->new;
        $ua->timeout(5);
        $ua->agent(
            'UCSF Profiles EasyJSON Interface/1.0 (anirvan.chatterjee@ucsf.edu)'
        );
    }
}

1;

# Local Variables:
# mode: perltidy
# End:
