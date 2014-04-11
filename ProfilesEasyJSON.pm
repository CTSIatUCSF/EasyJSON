#!/usr/bin/perl

# TODO:
# disable JSON pretty encoding in mobile view?
# add timeout support?

package ProfilesEasyJSON;
use CHI;
use Data::Dump qw( dump );
use Encode qw( encode );
use HTTP::Message 6.06;
use JSON;
use LWP::UserAgent 6.0;
use String::Util qw( trim );
use URI::Escape qw( uri_escape );
binmode STDOUT, ':utf8';
use parent qw( Exporter );
use strict;
use utf8;
use warnings;

our @EXPORT_OK
    = qw( identifier_to_json identifier_to_canonical_url canonical_url_to_json );

my ( $i2c_cache, $c2j_cache, $url_cache, $ua );
my $json_obj = JSON->new->utf8->pretty(1);

my $profiles_profile_root_url = 'http://profiles.ucsf.edu/profile/';

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

    # Identifier to Canonical URL cache
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

    # Canonical URL was not in cache
    # Need to retrieve from server

    my $node_uri;

    if (    $identifier_type eq 'FNO'
         or $identifier_type eq 'Person'
         or $identifier_type eq 'EmployeeID'
         or $identifier_type eq 'PrettyURL'
         or $identifier_type eq 'ProfilesNodeID'
         or $identifier_type eq 'URL' ) {

        if ( $identifier_type eq 'ProfilesNodeID' ) {
            if ( $identifier =~ m/^(\d\d+)$/ ) {
                return "$profiles_profile_root_url$1";
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

            if ( $i2c_cache->exists_and_is_expired($cache_key) ) {
                my $potential_expired_cache_object
                    = $i2c_cache->get_object($cache_key);
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
            my $http_code = $response->code;
            my $excerpt = substr( ( $raw || '[UNDEF]' ), 0, 20 );
            warn
                "Scanned URL $url for the original rdf:about node URI, but couldn't find it (got HTTP $http_code, '$excerpt...')\n";
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
    my $node_id = $1;

    # Canonical URL to JSON cache
    $c2j_cache ||= CHI->new(
             driver    => 'File',
             namespace => 'Profiles JSON API canonical_url_to_json URL cache',
             expires_variance => 0.25,
    );

    my $expanded_rdf_url
        = 'http://profiles.ucsf.edu/CustomAPI/v2/Default.aspx?Subject='
        . uri_escape($node_id)
        . '&ShowDetails=True&Expand=True';
    my $expanded_jsonld_url
        = profiles_rdf_url_to_jsonld_url($expanded_rdf_url);
    my $raw_json;

    # print STDERR ">> $expanded_jsonld_url\n";

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

    my $data = $json_obj->decode($raw_json);

    # print STDERR dump($data);

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
        if ( $item->{'@id'} eq $node_id or $item->{'@id'} eq $canonical_url )
        {
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
            "Scanned the contents of URL $expanded_jsonld_url, but could not find a person (we were looking for something with \@id '$canonical_url')\n";
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

    my %orng_data;
    $url_cache ||= CHI->new(
              driver    => 'File',
              namespace => 'Profiles JSON API cache of raw Profiles API URLs',
              expires_variance => 0.25,
    );

    # load ORNG data
    foreach my $field (
        qw( hasMediaLinks hasTwitter hasucsfprofile hasGlobalHealth hasFeaturedPublications hasLinks hasMentor hasNIHGrantList )
        ) {
        if ( exists $person->{$field}
             and $person->{$field}
             =~ m{^(?:\Q$profiles_profile_root_url\E)?(\d+)$} ) {

            my $field_jsonld_url
                = 'http://profiles.ucsf.edu/ORNG/JSONLD/Default.aspx?expand=true&subject='
                . $1;

            # grab from cache, if available
            my $raw_json_for_field = $url_cache->get($field_jsonld_url);

            # ...or get from server, and cache if found
            unless ($raw_json_for_field) {
                _init_ua() unless $ua;
                my $field_jsonld_response = $ua->get($field_jsonld_url);
                if ( $field_jsonld_response->is_success ) {
                    $raw_json_for_field
                        = $field_jsonld_response->decoded_content;
                    eval {
                        $url_cache->set( $field_jsonld_url,
                                         $raw_json_for_field, '23.5 hours' );
                    };
                }
            }

            # ...or try to get from expired cache
            unless ($raw_json_for_field) {
                if ( $url_cache->exists_and_is_expired($field_jsonld_url) ) {
                    my $potential_expired_cache_object
                        = $url_cache->get_object($field_jsonld_url);
                    if ($potential_expired_cache_object) {
                        if ( $potential_expired_cache_object->value() ) {
                            $raw_json_for_field
                                = $potential_expired_cache_object->value();
                        }
                    }
                }
            }

            # got some raw JSON? start using it
            if ($raw_json_for_field) {
                my $field_data
                    = eval { $json_obj->decode($raw_json_for_field) };
                if (     $field_data
                     and ref $field_data
                     and eval { $field_data->{entry}->{jsonld}->{'@graph'} } )
                {
                    foreach my $item (
                           @{ $field_data->{entry}->{jsonld}->{'@graph'} } ) {
                        if (     defined $item->{applicationInstanceDataValue}
                             and defined $item->{label} ) {
                            my $item_label = $item->{label};
                            my $item_data
                                = $item->{applicationInstanceDataValue};
                            if ( length $item_data ) {
                                my $decoded
                                    = eval { $json_obj->decode($item_data) };
                                if ( !$@ and $decoded ) {
                                    $item_data = $decoded;
                                }
                            }
                            $orng_data{$field}->{$item_label} = $item_data;
                        }
                    }
                }
            }

        }
    }

    my %featured_publication_order_by_id;

    for my $i ( 0 .. 199 ) {
        my $featured_num = $i + 1;
        my $pub = $orng_data{hasFeaturedPublications}->{"featured_pub_$i"};

        # we double-check if $pub is a hash because we found at least
        # one case (Kirsten Bibbins-Domingo) where the data was
        # accidentally encoded as a JSON string, probably due to
        # accidental double-JSON encoding.
        if ( $pub and ref $pub and ref $pub eq 'HASH' ) {

            my $pmid = $pub->{pmid};
            my $id   = $pub->{id};
            my $PublicationID;

            if ( defined $id and $id =~ m/^\d+$/ ) {

                $featured_publication_order_by_id{
                    "http://profiles.ucsf.edu/profile/$id"} = $featured_num;

            } elsif ( $pmid and $pmid =~ m/^\d+$/ ) {

                # If no ID is given but we have a PMID, go through
                # every publication to see which one matches that
                # PMID, and use the corresponding ID. This is
                # inefficient, but not worth speeding up.

                foreach my $candidate_pub_id (
                          @{ $publications_by_author{ $person->{'@id'} } } ) {
                    my $candidate_pmid
                        = $items_by_url_id{$candidate_pub_id}->{pmid};
                    if ( $candidate_pmid and $candidate_pmid == $pmid ) {
                        $featured_publication_order_by_id{
                            "http://profiles.ucsf.edu/profile/$candidate_pub_id"
                            } = $featured_num;
                    }
                }

            }
        }
    }

    # if person has multiple job role and titles, sort them appropriately
    my @sorted_positions;
    if ( $person->{personInPosition} and @{ $person->{personInPosition} } ) {
        @sorted_positions = @{ $person->{personInPosition} };
    } elsif ( $person->{personInPrimaryPosition} ) {
        @sorted_positions = $person->{personInPrimaryPosition};
    }
    @sorted_positions
        = grep {defined} map { $items_by_url_id{$_} } @sorted_positions;
    @sorted_positions
        = sort { $a->{'sortOrder'} <=> $b->{'sortOrder'} } @sorted_positions;

    my $final_data = {
        Profiles => [
            {  Name        => $person->{fullName},
               FirstName   => $person->{firstName},
               LastName    => $person->{lastName},
               ProfilesURL => "$profiles_profile_root_url$node_id",
               Email       => $person->{email},
               Address     => {
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
                   $items_by_url_id{ $sorted_positions[0]
                           ->{positionInDepartment} }->{label};
               },

               # only handling primary school at this time
               School => eval {
                   no warnings;
                   $items_by_url_id{ $sorted_positions[0]
                           ->{positionInOrganization} }->{label};
               },

               # can handle multiple titles
               # but we're only listing first title at this time
               Title  => $person->{preferredTitle},
               Titles => [
                   eval {
                       my @titles = map { $_->{label} } @sorted_positions;
                       @titles = map  { split /; / } @titles;
                       @titles = grep {m/\w/} @titles;
                       return @titles;
                   }
               ],

               Narrative => $person->{overview},

               PhotoURL => eval {
                   if ( $person->{mainImage} ) {
                       if ( $person->{mainImage} =~ m/^http/ ) {
                           return $person->{mainImage};
                       } else {
                           return
                               "$profiles_profile_root_url$person->{mainImage}";
                       }
                   } else {
                       return undef;
                   }
               },

               PublicationCount =>
                   eval { scalar @{ $person->{authorInAuthorship} } + 0; }
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
                              PublicationID => (
                                              m/^http/
                                              ? $_
                                              : "$profiles_profile_root_url$_"
                              ),

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

                              Featured => (
                                    $featured_publication_order_by_id{
                                        "http://profiles.ucsf.edu/profile/$_"}
                                        || JSON::null
                              ),
                          }
                          } @{ $publications_by_author{ $person->{'@id'} } }
                   )
               ],

               # ORNG data

               WebLinks_beta => [
                   eval {
                       my @links;

                       if (     $orng_data{hasLinks}->{VISIBLE}
                            and $orng_data{hasLinks}->{links}
                            and @{ $orng_data{hasLinks}->{links} } ) {

                           foreach
                               my $link ( @{ $orng_data{hasLinks}->{links} } )
                           {
                               push @links,
                                   { Label => $link->{link_name},
                                     URL   => $link->{link_url}
                                   };
                           }
                       }
                       return @links;
                   }
               ],

               MediaLinks_beta => [
                   eval {
                       my @links;
                       if ( @{ $orng_data{hasMediaLinks}->{links} } ) {
                           foreach my $link (
                                   @{ $orng_data{hasMediaLinks}->{links} } ) {

                               my $date = $link->{link_date};
                               if ( $date
                                   =~ s{^(\d+)/(\d+)/((?:19|20)\d\d)$}{$3-$1-$2}
                                   ) {
                                   push @links,
                                       { Label => $link->{link_name},
                                         URL   => $link->{link_url},
                                         Date  => $date
                                       };
                               }
                           }
                           return @links;
                       }
                   }
               ],

               Twitter_beta => (
                   eval {
                       $orng_data{hasTwitter}->{twitter_username};
                       }
                   ? [ $orng_data{hasTwitter}->{twitter_username} ]
                   : []
               ),

               GlobalHealth_beta => {
                   eval {
                       if (     $orng_data{hasGlobalHealth}
                            and $orng_data{hasGlobalHealth}->{countries} ) {
                           return ( 'Countries' => [
                                               split(
                                                   /;\s*/,
                                                   $orng_data{hasGlobalHealth}
                                                       ->{countries}
                                               )
                                    ]
                           );
                       } else {
                           return;
                       }
                   }
               },

               NIHGrants_beta => [
                   eval {
                       my @grants;
                       my %seen_project_number;
                       for my $i ( 0 .. 199 ) {
                           if ( my $grant
                                = $orng_data{hasNIHGrantList}->{"nih_$i"} ) {

                               # remove dupes
                               next
                                   if $seen_project_number{ $grant->{fpn} }++;
                               push @grants,
                                   { Title            => $grant->{t},
                                     NIHFiscalYear    => $grant->{fy},
                                     NIHProjectNumber => $grant->{fpn}
                                   };
                           }
                       }

                       # sort grants by date
                       @grants = sort {
                           $b->{NIHFiscalYear} <=> $a->{NIHFiscalYear}
                       } @grants;
                       return @grants;
                   }
               ],

            }
        ]
    };

    foreach my $person_data ( @{ $final_data->{Profiles} } ) {
        foreach my $key (qw( Publications MediaLinks MediaLinks_beta )) {
            if (     $person_data->{$key}
                 and @{ $person_data->{$key} }
                 and $person_data->{$key}->[0]
                 and $person_data->{$key}->[0]->{Date} ) {
                @{ $person_data->{$key} } = sort { $b->{Date} cmp $a->{Date} }
                    @{ $person_data->{$key} };
            }
        }
    }

    if (@api_notes) {
        $final_data->{api_notes} = join ' ', @api_notes;
    }

    my $out = $json_obj->encode($final_data);
    utf8::upgrade($out);
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

sub profiles_rdf_url_to_jsonld_url {
    my $profiles_rdf_url = shift;
    my $expanded_jsonld_url
        = 'http://profiles.ucsf.edu/shindigorng/rest/rdf?userId='
        . uri_escape($profiles_rdf_url);
    return $expanded_jsonld_url;
}

1;

# Local Variables:
# mode: perltidy
# End:
