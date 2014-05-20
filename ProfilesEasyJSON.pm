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

# e.g. if we load contents of http://profiles.ucsf.edu/CustomAPI/v2/Default.aspx?Person=4617024
            if ( $response->decoded_content
                 =~ m/The given key was not present in the dictionary/ ) {
                warn
                    "Tried to look up user '$identifier', but got no results\n";
                return;
            } else {
                my $status_line = $response->status_line;
                warn
                    "Sorry, we could not return results due to an internal UCSF Profiles error (couldn't load internal URL $url / $status_line)\n";
                return;
            }
        } elsif ( $response->base->path =~ m{^/Error/} ) {  # still happening?
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

    my $expanded_jsonld_url
        = 'http://profiles.ucsf.edu/ORNG/JSONLD/Default.aspx?expand=true&showdetails=true&subject='
        . $node_id;

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
        if ( grep { $_ eq 'vivo:Authorship' } @{ $item->{'@type'} } ) {
            if (     $item->{'vivo:linkedAuthor'}
                 and $item->{'vivo:linkedInformationResource'} ) {
                push @{ $publications_by_author{ $item->{'vivo:linkedAuthor'}
                            ->{'@id'} } },
                    $item->{'vivo:linkedInformationResource'}->{'@id'};
            }
        }

        $items_by_url_id{ $item->{'@id'} } = $item;
    }    # end each item

    unless ($person) {
        warn
            "Tried to look up user specified, but got no results in underlying JSON data source. You can verify whether or not this is a valid Profiles user by visiting $canonical_url\n";
        return;
    }

    # ensure there's only one of the following...
    foreach my $field ( 'vivo:email',
                        'prns:fullName',
                        'foaf:firstName',
                        'foaf:lastName',
                        'vivo:mailingAddress',
                        'vivo:phoneNumber',
                        'vivo:faxNumber',
                        'prns:latitude',
                        'prns:longitude',
                        'prns:mainImage',
                        'vivo:preferredTitle',
                        'prns:personInPrimaryPosition'
        ) {
        if ( eval { ref $person->{$field} eq 'ARRAY' } ) {
            $person->{$field} = $person->{$field}->[0];
        }
    }

    # merge with return if there are multiple of the following...
    foreach my $field ( 'vivo:freetextKeyword', 'vivo:overview' ) {
        if ( eval { ref $person->{$field} eq 'ARRAY' } ) {
            $person->{$field} = join "\n", @{ $person->{$field} };
        }
    }

    # ensure that repeatable fields are set up as an array
    foreach my $field ( 'vivo:hasResearchArea', 'vivo:awardOrHonor',
                        'vivo:personInPosition' ) {
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
    foreach my $field ( 'orng:hasFeaturedPublications',
                        'orng:hasGlobalHealth',
                        'orng:hasLinks',
                        'orng:hasMentor',
                        'orng:hasNIHGrantList',
                        'orng:hasTwitter',
                        'orng:hasSlideShare',
                        'orng:hasMediaLinks',
        ) {

        if (     eval { ref $person->{$field} eq 'HASH' }
             and $person->{$field}->{'@id'}
             and $person->{$field}->{'@id'} =~ m/^(\d+)$/ ) {

            my $field_jsonld_url
                = 'http://profiles.ucsf.edu/ORNG/JSONLD/Default.aspx?expand=true&showdetails=true&subject='
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

                        if ( defined $item->{
                                 'orng:applicationInstanceDataValue'}
                             and defined $item->{'rdfs:label'} ) {

                            my $item_data = $item->{
                                'orng:applicationInstanceDataValue'};
                            my $item_label = $item->{'rdfs:label'};

                            if ( length $item_data ) {
                                my $decoded = eval {
                                    no warnings;
                                    $json_obj->decode($item_data);
                                };
                                if ( !$@ and $decoded ) {
                                    $item_data = $decoded;
                                }
                            }
                            $orng_data{$field}->{$item_label} = $item_data;
                        }
                    }
                }
            }    # end if we have JSON for an ORNG field
        }    # end if we have node ID for ORNG field
    }    # end foreach ORNG field

    my %featured_publication_order_by_id;

    if ( $orng_data{'orng:hasFeaturedPublications'} ) {

        for my $i ( 0 .. 199 ) {
            my $featured_num = $i + 1;
            my $pub          = $orng_data{'orng:hasFeaturedPublications'}
                ->{"featured_pub_$i"};

            # we double-check if $pub is a hash because we found at least
            # one case (Kirsten Bibbins-Domingo) where the data was
            # accidentally encoded as a JSON string, probably due to
            # accidental double-JSON encoding.
            if ( $pub and ref $pub and ref $pub eq 'HASH' ) {

                my $pmid = $pub->{pmid};
                my $id   = $pub->{id};

                if ( defined $id and $id =~ m/^\d+$/ ) {

                    $featured_publication_order_by_id{$id} = $featured_num;

                } elsif ( $pmid and $pmid =~ m/^\d+$/ ) {

                    # If no ID is given but we have a PMID, go through
                    # every publication to see which one matches that
                    # PMID, and use the corresponding ID. This is
                    # inefficient, but not worth speeding up.

                    foreach my $candidate_pub_id (
                          @{ $publications_by_author{ $person->{'@id'} } } ) {
                        my $candidate_pmid
                            = $items_by_url_id{$candidate_pub_id}
                            ->{'bibo:pmid'};
                        if ( $candidate_pmid and $candidate_pmid == $pmid ) {
                            $featured_publication_order_by_id{
                                $candidate_pub_id} = $featured_num;
                        }
                    }

                }
            }
        }
    }

    # if person has multiple job role and titles, sort them appropriately
    my @sorted_positions;
    if ( $person->{'vivo:personInPosition'}
         and @{ $person->{'vivo:personInPosition'} } ) {
        @sorted_positions = @{ $person->{'vivo:personInPosition'} };
    } elsif ( $person->{'prns:personInPrimaryPosition'} ) {
        @sorted_positions = $person->{'prns:personInPrimaryPosition'};
    }

    @sorted_positions = grep {defined}
        map { $items_by_url_id{ $_->{'@id'} } } @sorted_positions;
    @sorted_positions
        = sort { $a->{'prns:sortOrder'} <=> $b->{'prns:sortOrder'} }
        @sorted_positions;

    # get all the address lines into a series of 1-4 lines of text
    my @address;
    {
        my $address_data
            = $items_by_url_id{ $person->{'vivo:mailingAddress'}->{'@id'} };
        foreach my $field (
              qw( vivo:address1 vivo:address2 vivo:address3 vivo:address4 )) {
            if ( $address_data->{$field} ) {
                push @address, $address_data->{$field};
            }
        }

        my $last_line = '';
        if ( $address_data->{'vivo:addressCity'} ) {
            $last_line = $address_data->{'vivo:addressCity'};

            if ( $address_data->{'vivo:addressState'} ) {
                $last_line .= ', ' . $address_data->{'vivo:addressState'};
            }
            if ( $address_data->{'vivo:addressPostalCode'} ) {
                $last_line .= ' ' . $address_data->{'vivo:addressPostalCode'};
            }

            push @address, $last_line;
        }
    }

    my $final_data = {
        Profiles => [
            {  Name        => $person->{'prns:fullName'},
               FirstName   => $person->{'foaf:firstName'},
               LastName    => $person->{'foaf:lastName'},
               ProfilesURL => "$profiles_profile_root_url$node_id",
               Email       => $person->{'vivo:email'},
               Address     => {
                            Address1  => $address[0],
                            Address2  => $address[1],
                            Address3  => $address[2],
                            Address4  => $address[3],
                            Telephone => $person->{'vivo:phoneNumber'},
                            Fax       => $person->{'vivo:faxNumber'},
                            Latitude  => $person->{'prns:latitude'} + 0,
                            Longitude => $person->{'prns:longitude'} + 0,
               },

               # only handling primary department at this time
               Department => eval {
                   if ( $sorted_positions[0]->{'prns:positionInDepartment'} )
                   {
                       my $dept_id = $sorted_positions[0]
                           ->{'prns:positionInDepartment'}->{'@id'};
                       return $items_by_url_id{$dept_id}->{'rdfs:label'};
                   } else {
                       return undef;
                   }
               },

               # only handling primary school at this time
               School => eval {
                   if ($sorted_positions[0]->{'vivo:positionInOrganization'} )
                   {
                       my $school_id = $sorted_positions[0]
                           ->{'vivo:positionInOrganization'}->{'@id'};
                       return $items_by_url_id{$school_id}->{'rdfs:label'};
                   } else {
                       return undef;
                   }
               },

               # can handle multiple titles
               # but we're only listing first title at this time
               Title  => $person->{'vivo:preferredTitle'},
               Titles => [
                   eval {
                       my @titles
                           = map { $_->{'rdfs:label'} } @sorted_positions;

                       # multiple titles sometimes concatenated "A; B"
                       @titles = map { split /; / } @titles;

                       @titles = grep {m/\w/} @titles;
                       return @titles;
                   }
               ],

               Narrative => $person->{'vivo:overview'},

               PhotoURL => eval {
                   if ( $person->{'prns:mainImage'} ) {
                       my $img_url_segment
                           = $person->{'prns:mainImage'}->{'@id'};
                       return "$profiles_profile_root_url$img_url_segment";
                   } else {
                       return undef;
                   }
               },

               PublicationCount => eval {
                   scalar @{ $person->{'vivo:authorInAuthorship'} } + 0;
                   }
                   || 0,

               #CoAuthors     => ['???'], # need to handle <- name
               #SimilarPeople => ['???'], # need to handle <- name

               Keywords => [
                   eval {
                       my @research_area_ids
                           = map { $_->{'@id'} }
                           @{ $person->{'vivo:hasResearchArea'} };

                       return
                           map { $items_by_url_id{$_}->{'rdfs:label'} }
                           @research_area_ids;
                   }
               ],

               FreetextKeywords => [
                   eval {
                       if ( defined $person->{'vivo:freetextKeyword'} ) {
                           return map { trim($_) }
                               split qr/\s*,\s*|\s*[\r\n]+\s*/,
                               $person->{'vivo:freetextKeyword'};
                       } else {
                           return ();
                       }
                   }
               ],

               AwardOrHonors => eval {
                   my @awards;
                   if ( $person->{'vivo:awardOrHonor'} ) {
                       my @award_ids = map { $_->{'@id'} }
                           @{ $person->{'vivo:awardOrHonor'} };

                       foreach my $id (@award_ids) {
                           my $item = $items_by_url_id{$id};
                           my $award = {
                                  AwardLabel => $item->{'rdfs:label'},
                                  AwardConferredBy =>
                                      $item->{'prns:awardConferredBy'},
                                  AwardStartDate => $item->{'prns:startDate'},
                                  AwardEndDate   => $item->{'prns:endDate'},
                           };
                           $award->{Summary}
                               = join( ', ',
                                       grep { defined and length } (
                                             $award->{AwardLabel},
                                             $award->{AwardConferredBy},
                                             join( '-',
                                                 grep {defined}
                                                     $award->{AwardStartDate},
                                                 $award->{AwardEndDate} )
                                       )
                               );
                           push @awards, $award;
                       }
                   }

                   @awards = sort {
                       $b->{'AwardStartDate'} cmp $a->{'AwardStartDate'}
                   } @awards;
                   return \@awards;
               },

               Publications => eval {
                   my @publications;
                   unless ( $options->{no_publications} ) {

                       foreach my $pub_id (
                            @{ $publications_by_author{ $person->{'@id'} } } )
                       {
                           my $pub = $items_by_url_id{$pub_id};

                           push @publications, {

                               # PublicationAddedBy => '?',
                               PublicationID => $profiles_profile_root_url
                                   . $pub_id,
                               AuthorList =>
                                   ( $pub->{'prns:hasAuthorList'} || undef ),
                               Publication => (
                                   $pub->{'prns:hasPublicationVenue'} || undef
                               ),
                               PublicationMedlineTA =>
                                   ( $pub->{'prns:medlineTA'} || undef ),
                               Title => ( $pub->{'rdfs:label'} || undef ),
                               Date => (
                                       $pub->{'prns:publicationDate'} || undef
                               ),
                               Year => ( $pub->{'prns:year'} || undef ),

                               PublicationTitle => $pub->{
                                   'prns:informationResourceReference'},
                               PublicationSource => [
                                   {  PublicationSourceName => (
                                                           $pub->{'bibo:pmid'}
                                                           ? 'PubMed'
                                                           : undef
                                      ),
                                      PublicationSourceURL => (
                                          $pub->{'bibo:pmid'}
                                          ? ( $options->{mobile}
                                              ? "http://www.ncbi.nlm.nih.gov/m/pubmed/$pub->{'bibo:pmid'}"
                                              : "http://www.ncbi.nlm.nih.gov/pubmed/$pub->{'bibo:pmid'}"
                                              )
                                          : undef
                                      ),
                                      PMID =>
                                          ( $pub->{'bibo:pmid'} || undef ),
                                   }
                               ],

                               Featured => (
                                    $featured_publication_order_by_id{$pub_id}
                                        || undef
                               ),
                           };
                       }    # end foreach publication
                   }    # end if we should include pubs

                   return \@publications;
               },

               # ORNG data

               WebLinks_beta => [
                   eval {
                       my @links;

                       if (     $orng_data{'orng:hasLinks'}->{VISIBLE}
                            and $orng_data{'orng:hasLinks'}->{links}
                            and @{ $orng_data{'orng:hasLinks'}->{links} } ) {

                           foreach my $link (
                                 @{ $orng_data{'orng:hasLinks'}->{links} } ) {
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
                       if ( @{ $orng_data{'orng:hasMediaLinks'}->{links} } ) {
                           foreach my $link (
                                @{ $orng_data{'orng:hasMediaLinks'}->{links} }
                               ) {

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
                       $orng_data{'orng:hasTwitter'}->{twitter_username};
                       }
                   ? [ $orng_data{'orng:hasTwitter'}->{twitter_username} ]
                   : []
               ),

               SlideShare_beta => (
                   eval {
                       $orng_data{'orng:hasSlideShare'}->{username};
                       }
                   ? [ $orng_data{'orng:hasSlideShare'}->{username} ]
                   : []
               ),

               GlobalHealth_beta => eval {
                   if (    $orng_data{'orng:hasGlobalHealth'}
                       and $orng_data{'orng:hasGlobalHealth'}->{countries} ) {
                       return { 'Countries' => [
                                        split(
                                            /;\s*/,
                                            $orng_data{'orng:hasGlobalHealth'}
                                                ->{countries}
                                        )
                                ]
                       };
                   } else {
                       return undef;
                   }
               },

               NIHGrants_beta => [
                   eval {
                       my @grants;
                       my %seen_project_number;
                       for my $i ( 0 .. 199 ) {
                           if ( my $grant = $orng_data{'orng:hasNIHGrantList'}
                                ->{"nih_$i"} ) {

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

1;

# Local Variables:
# mode: perltidy
# End:
