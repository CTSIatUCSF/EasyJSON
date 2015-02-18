#!/usr/bin/perl

# TODO:
# add timeout support?

package ProfilesEasyJSON;
use CHI;
use Data::Dump qw( dump );
use Encode qw( encode );
use HTTP::Message 6.06;
use JSON;
use List::MoreUtils qw( uniq );
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

my $profiles_native_api_root_url = 'http://profiles.ucsf.edu/';
my $profiles_profile_root_url    = 'http://profiles.ucsf.edu/profile/';

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

    # Canonical URL was not a valid cache entry
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
                warn "Expected to see an all-numeric ProfilesNodeID\n";
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
            = "${profiles_native_api_root_url}CustomAPI/v2/Default.aspx?"
            . uri_escape($identifier_type) . '='
            . uri_escape($identifier);

        _init_ua() unless $ua;
        my $response = $ua->get($url);

   # if there was an error loading the content, figure out an error message...

        my $error_warning;
        if ( $response->is_success ) {
            if ( $response->base->path =~ m{^/Error/} ) {   # still happening?
                $error_warning
                    = "Tried to look up user '$identifier', but got no results\n";
            }
        } else {

           # e.g. if we load contents of
           # http://profiles.ucsf.edu/CustomAPI/v2/Default.aspx?Person=4617024
            if ( $response->decoded_content
                 =~ m/The given key was not present in the dictionary/ ) {
                $error_warning
                    = "Tried to look up user '$identifier', but got no results\n";
            } else {
                my $status_line = $response->status_line;
                $error_warning
                    = "Sorry, we could not return results due to an internal UCSF Profiles error (couldn't load internal URL $url / $status_line)\n";
            }
        }

        # if there was an error...

        if ($error_warning) {

            # first, maybe we can just return expired content?
            foreach my $key ( $cache_key, $cache_key_alt ) {
                if ( $i2c_cache->exists_and_is_expired($key) ) {
                    my $potential_expired_cache_object
                        = $i2c_cache->get_object($key);
                    if ($potential_expired_cache_object) {
                        $node_uri = $potential_expired_cache_object->value();
                        if ($node_uri) {
                            $error_warning = undef;
                            return $node_uri;
                        }
                    }
                }
            }

            # nope, I guess we have to return an error
            warn $error_warning;
            return;

        }

        # now we know we have a valid HTTP response

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
        = $profiles_native_api_root_url
        . 'ORNG/JSONLD/Default.aspx?expand=true&showdetails=true&subject='
        . $node_id;

    my $raw_json;
    my $decoded_json;

    # attempt to get it from the cache, if possible
    unless ( $options->{cache} eq 'never' ) {
        my $cache_object = $c2j_cache->get_object($expanded_jsonld_url);
        if ($cache_object) {

            $raw_json = $cache_object->value;
            $decoded_json = eval { $json_obj->decode($raw_json) };

            if ( $raw_json and $decoded_json ) {

                my $api_note_preamble
                    = 'To maximize performance, we are providing recently-cached data.';
                if ( $options->{cache} eq 'always' ) {
                    $api_note_preamble = 'You requested cached data.';
                }

                my $printable_cache_time
                    = scalar( localtime( $cache_object->created_at() ) );

                push @api_notes,
                    "$api_note_preamble This data was cached on $printable_cache_time";
            }
        }
    }

    # if we didn't get back valid JSON from the cache, and we're
    # allowed to do an HTTP lookup, then go do it

    if ( !$decoded_json and $options->{cache} ne 'always' ) {
        _init_ua() unless $ua;
        my $response = $ua->get($expanded_jsonld_url);

        if ( $response->is_success ) {
            $raw_json = $response->decoded_content;
            $decoded_json = eval { $json_obj->decode($raw_json) };

            if ( $raw_json and $decoded_json ) {
                push @api_notes,
                    'This data was retrieved live from our database at '
                    . scalar(localtime);

                eval {
                    $c2j_cache->set( $expanded_jsonld_url, $raw_json,
                                     '24 hours' );
                };
            } else {
                warn 'Loaded URL ', dump($expanded_jsonld_url),
                    " to look up JSON-LD, but JSON was either missing or invalid\n";
            }
        } else {    # if we got an error message from upstream
            warn 'Could not load URL ', dump($expanded_jsonld_url),
                ' to look up JSON-LD (', $response->status_line, ")\n";
        }
    }

    # if we STILL don't have valid JSON, we look for it in expired
    # cache results, if we're allowed to...

    unless ( $raw_json and $decoded_json ) {
        if ( $options->{cache} ne 'never' ) {
            if ( $c2j_cache->exists_and_is_expired($expanded_jsonld_url) ) {

                my $cache_object
                    = $c2j_cache->get_object($expanded_jsonld_url);

                if ($cache_object) {
                    $raw_json = $cache_object->value || undef;
                    if ($raw_json) {
                        $decoded_json = eval { $json_obj->decode($raw_json) };
                    }

                    if ( $raw_json and $decoded_json ) {
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

    unless ( $raw_json and $decoded_json ) {
        return;
    }

    my $data = $decoded_json;

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
        if ( ref $item and $item->{'@type'} ) {
            foreach my $type ( @{ $item->{'@type'} } ) {
                if ( $type eq 'vivo:Authorship' ) {
                    if (     $item->{'linkedAuthor'}
                         and $item->{'linkedInformationResource'} ) {

                        push @{ $publications_by_author{ $item->{
                                    'linkedAuthor'} } },
                            $item->{'linkedInformationResource'};
                    }

                }
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
    foreach my $field ( 'email',          'fullName',
                        'firstName',      'lastName',
                        'mailingAddress', 'phoneNumber',
                        'faxNumber',      'latitude',
                        'longitude',      'mainImage',
                        'preferredTitle', 'personInPrimaryPosition'
        ) {
        if ( eval { ref $person->{$field} eq 'ARRAY' } ) {
            $person->{$field} = $person->{$field}->[0];
        }
    }

    # merge with return if there are multiple of the following...
    foreach my $field ( 'freetextKeyword', 'overview' ) {
        if ( eval { ref $person->{$field} eq 'ARRAY' } ) {
            $person->{$field} = join "\n", @{ $person->{$field} };
        }
    }

    # ensure that repeatable fields are set up as an array
    foreach my $field ( 'hasResearchArea',  'awardOrHonor',
                        'personInPosition', 'educationalTraining'
        ) {
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
    foreach my $field ( 'hasFeaturedPublications', 'hasGlobalHealth',
                        'hasLinks',                'hasMentor',
                        'hasNIHGrantList',         'hasTwitter',
                        'hasSlideShare',           'hasMediaLinks',
                        'hasYouTube',
        ) {

        if (     $person->{$field}
             and $person->{$field}
             =~ m{^http://profiles.ucsf.edu/profile/(\d+)$} ) {

            my $field_jsonld_url
                = $profiles_native_api_root_url
                . 'ORNG/JSONLD/Default.aspx?expand=true&showdetails=true&subject='
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
                                         $raw_json_for_field, '24 hours' );
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

                        if ( defined $item->{'applicationInstanceDataValue'}
                             and (    defined $item->{'label'}
                                   or defined $item->{'rdfs:label'} )
                            ) {

                            my $item_data
                                = $item->{'applicationInstanceDataValue'};
                            my $item_label = $item->{'label'}
                                || $item->{'rdfs:label'};

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

    if ( $orng_data{'hasFeaturedPublications'} ) {

        for my $i ( 0 .. 199 ) {
            my $featured_num = $i + 1;
            my $pub
                = $orng_data{'hasFeaturedPublications'}->{"featured_pub_$i"};

            # we double-check if $pub is a hash because we found at least
            # one case (kirsten.bibbins-domingo) where the data was
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
                            = $items_by_url_id{$candidate_pub_id}->{'pmid'};
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
    if ( $person->{'personInPosition'}
         and @{ $person->{'personInPosition'} } ) {
        @sorted_positions = @{ $person->{'personInPosition'} };
    } elsif ( $person->{'personInPrimaryPosition'} ) {
        @sorted_positions = $person->{'personInPrimaryPosition'};
    }

    @sorted_positions = map  { $items_by_url_id{$_} } @sorted_positions;
    @sorted_positions = grep {defined} @sorted_positions;

    @sorted_positions
        = sort { $a->{'sortOrder'} <=> $b->{'sortOrder'} } @sorted_positions;

    # get all the address lines into a series of 1-4 lines of text
    my @address;
    {

        my $address_data = $items_by_url_id{ $person->{'mailingAddress'} };
        foreach my $field (qw( address1 address2 address3 address4 )) {
            if ( $address_data->{$field} ) {
                push @address, $address_data->{$field};
            }
        }

        my $last_line = '';
        if ( $address_data->{'addressCity'} ) {
            $last_line = $address_data->{'addressCity'};

            if ( $address_data->{'addressState'} ) {
                $last_line .= ', ' . $address_data->{'addressState'};
            }
            if ( $address_data->{'addressPostalCode'} ) {
                $last_line .= ' ' . $address_data->{'addressPostalCode'};
            }

            push @address, $last_line;
        }
    }

    my $final_data = {
        Profiles => [
            {  Name        => $person->{'fullName'},
               FirstName   => $person->{'firstName'},
               LastName    => $person->{'lastName'},
               ProfilesURL => "$profiles_profile_root_url$node_id",
               Email       => $person->{'email'},
               Address     => {
                            Address1  => $address[0],
                            Address2  => $address[1],
                            Address3  => $address[2],
                            Address4  => $address[3],
                            Telephone => $person->{'phoneNumber'},
                            Fax       => $person->{'faxNumber'},
                            Latitude  => (defined( $person->{'latitude'} )
                                          ? ( $person->{'latitude'} + 0 )
                                          : undef
                            ),
                            Longitude => ( defined( $person->{'longitude'} )
                                           ? ( $person->{'longitude'} + 0 )
                                           : undef
                            ),
               },

               # only handling primary department at this time
               Department => eval {
                   if ( $sorted_positions[0]->{'positionInDepartment'} ) {
                       my $dept_id
                           = $sorted_positions[0]->{'positionInDepartment'};
                       return $items_by_url_id{$dept_id}->{'label'};
                   } else {
                       return undef;
                   }
               },

               # only handling primary school at this time
               School => eval {
                   if ( $sorted_positions[0]->{'positionInOrganization'} ) {
                       my $school_id
                           = $sorted_positions[0]->{'positionInOrganization'};
                       return $items_by_url_id{$school_id}->{'label'};
                   } else {
                       return undef;
                   }
               },

               # can handle multiple titles
               # but we're only listing first title at this time
               Title  => $person->{'preferredTitle'},
               Titles => [
                   eval {
                       my @titles = map { $_->{'label'} } @sorted_positions;

                       # multiple titles sometimes concatenated "A; B"
                       @titles = map { split /; / } @titles;

                       @titles = grep {m/\w/} @titles;
                       return @titles;
                   }
               ],

               Narrative => $person->{'overview'},

               PhotoURL => eval {
                   if ( $person->{'mainImage'} ) {
                       my $img_url_segment = $person->{'mainImage'};
                       if ( $img_url_segment =~ m/^http/ ) {
                           return $img_url_segment;
                       } else {
                           return
                               "$profiles_profile_root_url$img_url_segment";
                       }
                   } else {
                       return undef;
                   }
               },

               PublicationCount => eval {
                   if ( $publications_by_author{ $person->{'@id'} } ) {
                       return
                           scalar
                           @{ $publications_by_author{ $person->{'@id'} } };
                   } else {
                       return 0;
                   }
               },

               #CoAuthors     => ['???'], # need to handle <- name
               #SimilarPeople => ['???'], # need to handle <- name

               Keywords => [
                   eval {
                       my @research_area_ids
                           = @{ $person->{'hasResearchArea'} };

                       return
                           map { $items_by_url_id{$_}->{'label'} }
                           @research_area_ids;
                   }
               ],

               Education_Training => [
                   eval {
                       my @education_training;
                       if ( defined $person->{'educationalTraining'} ) {
                           my @ed_training_ids
                               = @{ $person->{'educationalTraining'} };
                           foreach my $id (@ed_training_ids) {
                               my $item = $items_by_url_id{$id};
                               push @education_training,
                                   {degree => trim( $item->{'degreeEarned'} ),
                                    end_date => trim( $item->{'endDate'} ),
                                    organization =>
                                        trim($item->{'trainingAtOrganization'}
                                        ),
                                    department_or_school =>
                                        trim( $item->{"departmentOrSchool"} ),
                                   };
                           }

                           @education_training = sort {
                               ( $b->{end_date} || '' )
                                   cmp( $a->{end_date} || '' )
                           } @education_training;

                           return @education_training;
                       } else {
                           return ();
                       }
                   }
               ],

               FreetextKeywords => [
                   eval {
                       if ( defined $person->{'freetextKeyword'} ) {
                           return map { trim($_) }
                               split qr/\s*,\s*|\s*;\s*|\s*[\r\n]+\s*/,
                               $person->{'freetextKeyword'};
                       } else {
                           return ();
                       }
                   }
               ],

               AwardOrHonors => eval {
                   my @awards;
                   if ( $person->{'awardOrHonor'} ) {

                       my @award_ids = @{ $person->{'awardOrHonor'} };

                       foreach my $id (@award_ids) {
                           my $item = $items_by_url_id{$id};
                           my $award = {
                                       AwardLabel => $item->{'label'},
                                       AwardConferredBy =>
                                           $item->{'awardConferredBy'},
                                       AwardStartDate => $item->{'startDate'},
                                       AwardEndDate   => $item->{'endDate'},
                           };

                           $award->{Summary}
                               = join(
                                     ', ',
                                     grep { defined and length } (
                                         $award->{AwardLabel},
                                         $award->{AwardConferredBy},
                                         join(
                                             '-',
                                             uniq(
                                                 grep {defined}
                                                     $award->{AwardStartDate},
                                                 $award->{AwardEndDate}
                                             )
                                         )
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
                               PublicationID => $pub_id,
                               AuthorList =>
                                   ( $pub->{'hasAuthorList'} || undef ),
                               Publication =>
                                   ( $pub->{'hasPublicationVenue'} || undef ),
                               PublicationMedlineTA =>
                                   ( $pub->{'medlineTA'} || undef ),
                               Title => ( $pub->{'label'} || undef ),
                               Date => ( $pub->{'publicationDate'} || undef ),
                               Year => ( $pub->{'year'}            || undef ),

                               PublicationCategory =>
                                   ( $pub->{'hmsPubCategory'} || undef ),

                               PublicationTitle =>
                                   $pub->{'informationResourceReference'},
                               PublicationSource => [
                                   {  PublicationSourceName => (
                                                     $pub->{'pmid'} ? 'PubMed'
                                                     : undef
                                      ),
                                      PublicationSourceURL => (
                                          $pub->{'pmid'}
                                          ? "http://www.ncbi.nlm.nih.gov/pubmed/$pub->{'pmid'}"
                                          : undef
                                      ),
                                      PMID => ( $pub->{'pmid'} || undef ),
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

                       if (     $orng_data{'hasLinks'}->{VISIBLE}
                            and $orng_data{'hasLinks'}->{links_count}
                            and $orng_data{'hasLinks'}->{links_count}
                            =~ m/^\d+$/ ) {

                           my $max_links_count
                               = $orng_data{'hasLinks'}->{links_count};

                           for ( my $i = 0; $i < $max_links_count; $i++ ) {
                               if ( $orng_data{hasLinks}->{"link_$i"}
                                   and ref $orng_data{hasLinks}->{"link_$i"} )
                               {
                                   my $link
                                       = $orng_data{hasLinks}->{"link_$i"};
                                   push @links,
                                       { Label => $link->{name},
                                         URL   => $link->{url}
                                       };
                               }
                           }
                       }
                       return @links;
                   }
               ],

               MediaLinks_beta => [
                   eval {
                       my @links;
                       if ( @{ $orng_data{'hasMediaLinks'}->{links} } ) {
                           foreach my $link (
                                 @{ $orng_data{'hasMediaLinks'}->{links} } ) {

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
                               $orng_data{'hasTwitter'}->{twitter_username}
                           and $orng_data{'hasTwitter'}->{twitter_username}
                           =~ /^([A-Za-z0-9_]+)$/;
                       }
                   ? [ $orng_data{'hasTwitter'}->{twitter_username} ]
                   : []
               ),

               Videos => (
                   eval {
                       my @videos;
                       if ( eval { @{ $orng_data{'hasYouTube'}->{videos} } } )
                       {
                           foreach my $entry (
                                   @{ $orng_data{'hasYouTube'}->{videos} } ) {
                               next unless $entry->{url}  =~ m/^http/;
                               next unless $entry->{name} =~ m/\w/;
                               if (     $entry->{url} !~ m/youtube/i
                                    and $entry->{id}
                                    and $entry->{id} =~ m/\w/ ) {
                                   $entry->{url}
                                       = 'https://www.youtube.com/watch?v='
                                       . $entry->{id};
                               }
                               push @videos,
                                   { url   => $entry->{url},
                                     label => $entry->{name}
                                   };
                           }
                       }
                       return \@videos;
                   }
               ),

               SlideShare_beta => (
                   eval {
                       $orng_data{'hasSlideShare'}->{username};
                       }
                   ? [ $orng_data{'hasSlideShare'}->{username} ]
                   : []
               ),

               GlobalHealth_beta => (
                   eval {
                       my %countries;
                       if ( $orng_data{'hasGlobalHealth'} ) {

                           my $gh = $orng_data{'hasGlobalHealth'};
                           if ( $gh->{gh_0} ) {
                               foreach my $value ( values %{$gh} ) {
                                   if (     ref($value) eq 'HASH'
                                        and $value->{Locations}
                                        and ref $value->{Locations} eq
                                        'ARRAY' ) {
                                       foreach my $country (
                                                  @{ $value->{Locations} } ) {
                                           $countries{$country} = 1;
                                       }
                                   }
                               }
                           }
                       }

                       if (%countries) {
                           return { Countries => [ sort keys %countries ] };
                       } else {
                           return {};
                       }
                   }
               ),

               NIHGrants_beta => [
                   eval {
                       my @grants;
                       my %seen_project_number;
                       for my $i ( 0 .. 199 ) {
                           if ( my $grant
                               = $orng_data{'hasNIHGrantList'}->{"nih_$i"} ) {

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
            'UCSF Profiles EasyJSON Interface/1.1 (anirvan.chatterjee@ucsf.edu)'
        );
    }
}

1;

# Local Variables:
# mode: perltidy
# End:
