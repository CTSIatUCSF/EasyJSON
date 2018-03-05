#!/usr/bin/perl

# TODO:
# add timeout support?

package ProfilesEasyJSON;
use CHI;
use Data::Dump qw( dump );
use Data::Visitor::Callback;
use Digest::MD5 qw( md5_base64 );
use Encode qw( encode );
use HTTP::Message 6.06;
use JSON;
use List::MoreUtils qw( uniq );
use LWP::UserAgent 6.0;
use Moo;
use Regexp::Assemble;
use String::Util qw( trim );
use Types::Standard 1.002001
    qw( ArrayRef ClassName InstanceOf Maybe RegexpRef );
use URI;
use URI::Escape qw( uri_escape );
binmode STDOUT, ':utf8';
use 5.10.0;
use namespace::clean;
use utf8;

###############################################################################

# This is the domain that runs the site, where centralized URIs are
# based off of, e.g. base.researchprofiles.org
has 'root_domain' => ( is       => 'ro',
                       required => 1,
                       isa      => InstanceOf ['URI']
);

# This is the domain that users see, and that we hit for API calls.
has 'themed_base_domain' => ( is  => 'lazy',
                              isa => InstanceOf ['URI'] );

sub _build_themed_base_domain {
    my $self = shift;
    return $self->root_domain;
}

# We use this if there are one or more old domains that were
# previously used. We look at these hosts to see if a URL is ours.
has 'legacy_root_domains' => ( is  => 'ro',
                               isa => ArrayRef [ InstanceOf ['URI'] ],
                               default => sub { [] },
);

# We use this as the root to construct example URLs during error
# messages, etc. In most cases, this should be the same as the
# themed_base_domain, but that doesn't always make sense. If this is
# customized, we should almost always make sure that this is included
# in the list of legacy_root_domains.
has 'example_url_domain' => ( is => 'lazy', isa => InstanceOf ['URI'] );

sub _build_example_url_domain {
    my $self = shift;
    return $self->themed_base_domain;
}

has 'id' => ( is => 'lazy' );

sub _build_id {
    my $self   = shift;
    my $string = join( ' - ',
                       $self->root_domain->canonical,
                       $self->themed_base_domain->canonical,
                       $self->example_url_domain->canonical,
                       ( ref $self ),
    );
    return md5_base64($string);
}

has 'themed_base_domain_profile_root' =>
    ( is => 'lazy', isa => InstanceOf ['URI'] );

sub _build_themed_base_domain_profile_root {
    my $self = shift;
    my $url  = $self->themed_base_domain->clone;
    $url->path('/profile/');
    return $url;
}

has _ua => ( is  => 'lazy',
             isa => InstanceOf ['LWP::UserAgent'] );

sub _build__ua {
    my $ua = LWP::UserAgent->new;
    $ua->timeout(5);

    # Profiles has bot detection that interferes with some downloads
    # so we're trying to add some random spaces to the useragent.
    my $agent_string = 'Profiles EasyJSON Interface 2.0';
    1 while $agent_string =~ s/(\w)(\w)/$1 . (' ' x rand(3)) . $2/ei;
    $agent_string = "Mozilla/5.0 ($agent_string)";
    $ua->agent($agent_string);

    return $ua;
}

###############################################################################

# globals
has 'current_or_legacy_profiles_root_url_regexp' => ( is  => 'lazy',
                                                      isa => RegexpRef );

sub _build_current_or_legacy_profiles_root_url_regexp {
    my $self     = shift;
    my $hosts_re = Regexp::Assemble->new;
    for my $url ( $self->root_domain, $self->themed_base_domain,
                  @{ $self->legacy_root_domains } ) {
        $hosts_re->add( $url->host );
    }
    return qr{^https?://$hosts_re};
}

###############################################################################

sub identifier_to_json {
    my ( $self, $identifier_type, $identifier, $options ) = @_;
    $options ||= {};

    my $canonical_url =
        $self->identifier_to_canonical_url( $identifier_type, $identifier,
                                            $options );
    if ($canonical_url) {
        my $json = $self->canonical_url_to_json( $canonical_url, $options );
        if ($json) {
            return $json;
        } else {
            warn 'Could not retrieve JSON for: ' . dump($identifier), "\n";
        }
    } else {
        warn 'Could not look up identifier: ' . dump($identifier), "\n";
    }
    return;
}

# given an identifier (like an FNO), returns the canonical Profiles URL
# (may return old cached results)
sub identifier_to_canonical_url {
    my ( $self, $identifier_type, $identifier, $options ) = @_;
    $options ||= {};

    unless ( defined $identifier and $identifier =~ m/\w/ ) {
        warn 'Unknown identifier: ' . dump($identifier), "\n";
        return;
    }

    # Identifier to Canonical URL cache
    state $i2c_cache ||= CHI->new(
                   driver    => 'File',
                   namespace => 'Profiles JSON API identifier_to_canonical_url',
                   expires_variance => 0.25,
    );

    my $cache_key = join "\t", ( $identifier_type || '' ),
        ( $identifier || '' ), $self->id;

    # cache_key should usually work, but in case the identifier is
    # something like "John.Smith" we actually want to check to see if
    # we can match that against "john.smith"
    my $cache_key_alt = join "\t", ( $identifier_type || '' ),
        lc( $identifier || '' ), $self->id;

    unless ( $options->{cache} and $options->{cache} eq 'never' ) {
        my $canonical_url = $i2c_cache->get($cache_key);
        if ( !$canonical_url and $cache_key_alt ne $cache_key ) {
            $canonical_url = $i2c_cache->get($cache_key_alt);
        }
        if ($canonical_url) {
            return URI->new($canonical_url);
        }
    }

    # couldn't find the canonical URL via the cache,
    # so we need to retrieve from the server

    my $node_uri;

    if (    $identifier_type eq 'FNO'
         or $identifier_type eq 'Person'
         or $identifier_type eq 'EmployeeID'
         or $identifier_type eq 'EPPN'
         or $identifier_type eq 'PrettyURL'
         or $identifier_type eq 'ProfilesNodeID'
         or $identifier_type eq 'UserName'
         or $identifier_type eq 'URL' ) {

        if ( $identifier_type eq 'ProfilesNodeID' ) {
            if ( $identifier =~ m/^(\d\d+)$/ ) {
                return URI->new( $self->root_domain . 'profile/' . $1 );
            } else {
                warn "Expected to see an all-numeric ProfilesNodeID\n";
                return;
            }
        } elsif ( $identifier_type eq 'PrettyURL' ) {
            $identifier = lc $identifier;
        } elsif ( $identifier_type eq 'URL' ) {

            my $profile_root_url = $self->themed_base_domain_profile_root;
            my $current_or_legacy_profiles_root_url_regexp
                = $self->current_or_legacy_profiles_root_url_regexp;

            if ( $identifier
                =~ m{$current_or_legacy_profiles_root_url_regexp/ProfileDetails\.aspx\?Person=(\d+)$}
            ) {
                $identifier      = $1;
                $identifier_type = 'Person';
            } elsif ( $identifier
                =~ m{^$current_or_legacy_profiles_root_url_regexp/([a-zA-Z][a-z-\.]+\d*)$}
            ) {
                $identifier      = lc $1;
                $identifier_type = 'PrettyURL';
            } elsif ( $identifier
                =~ m{^$current_or_legacy_profiles_root_url_regexp/profile/(\d+)$}
            ) {
                return URI->new($identifier)
                    ;    # if passed a canonical URL, return it
            } elsif ( $identifier =~ m{$profile_root_url(\d+)$} ) {
                return URI->new($identifier)
                    ;    # if passed a canonical URL, return it
            } else {
                my $example_root = $self->example_url_domain;
                warn 'Unrecognized URL ', dump($identifier),
                    ' (was expecting something like "${example_root}clay.johnston" or "${example_root}ProfileDetails.aspx?Person=5036574")',
                    "\n";
                return;
            }
        }

        # translate Person IDs, for processing convenience
        if (     $identifier_type eq 'Person'
             and $identifier =~ m/^\d+$/
             and $identifier >= 1_000_000 ) {
            my $new_identifier = substr( ( $identifier - 569307 ), 1, 6 );
            if ( $new_identifier >= 100000 ) {
                $identifier_type = 'UserName';
                $identifier      = "$new_identifier\@ucsf.edu";
            }
        }

        # handle EPPNs, for processing convenience
        if (     $identifier_type eq 'EPPN'
             and $identifier =~ m/\w.*\@.*\w/ ) {
            $identifier_type = 'UserName';
        }

        my $url = $self->themed_base_domain->clone;
        $url->path('CustomAPI/v2/Default.aspx');
        $url->query_form( { $identifier_type => $identifier } );
        my $response = $self->_ua->get($url);

        # if there was an error loading the content, figure out an error message

        my $error_warning;
        if ( $response->is_success ) {
            if ( $response->base->path =~ m{^/Error/} ) {    # still happening?
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
                            return URI->new($node_uri);
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
            return URI->new($node_uri);
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
# (may return recent-ish cached results)
sub canonical_url_to_json {

    my $self          = shift;
    my $canonical_url = shift;
    my $options       = shift || {};
    my @api_notes;

    unless (     $options->{cache}
             and $options->{cache} =~ m/^(fallback|always|never)$/ ) {
        $options->{cache} = 'fallback';
    }

    my $current_or_legacy_profiles_root_url_regexp
        = $self->current_or_legacy_profiles_root_url_regexp;

    unless ( defined $canonical_url
             and $canonical_url
             =~ m{$current_or_legacy_profiles_root_url_regexp/profile/(\d+)} ) {
        warn 'Invalid canonical URL: ', dump($canonical_url), "\n";
        return;
    }
    my $node_id = $1;

    # Canonical URL to JSON cache
    state $c2j_cache ||= CHI->new(
               driver    => 'File',
               namespace => 'Profiles JSON API canonical_url_to_json URL cache',
               expires_variance => 0.25,
    );

    my $expanded_jsonld_url = $self->themed_base_domain->clone;
    $expanded_jsonld_url->path('/ORNG/JSONLD/Default.aspx');
    $expanded_jsonld_url->query_form( { expand      => 'true',
                                        showdetails => 'true',
                                        subject     => $node_id
                                      }
    );

    state $json_obj = JSON->new->utf8->pretty(1);
    my $raw_json;
    my $decoded_json;

    # attempt to get it from the cache, if possible
    unless ( $options->{cache} eq 'never' ) {
        my $cache_object
            = $c2j_cache->get_object( $expanded_jsonld_url->as_string );

        if ( $cache_object and _verify_cache_object_policy($cache_object) ) {

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
        my $response = $self->_ua->get($expanded_jsonld_url);

        if ( $response->is_success ) {
            $raw_json = $response->decoded_content;
            $decoded_json = eval { $json_obj->decode($raw_json) };

            if ( $raw_json and $decoded_json ) {
                push @api_notes,
                    'This data was retrieved live from our database at '
                    . scalar(localtime);

                eval {
                    $c2j_cache->set( $expanded_jsonld_url->as_string,
                                     $raw_json, '24 hours' );
                };
            } else {
                warn 'Loaded URL ', dump($expanded_jsonld_url),
                    " to look up JSON-LD, but JSON was either missing or invalid\n";
            }
        } else {    # if we got an error message from upstream
            warn "Could not load URL $expanded_jsonld_url to look up JSON-LD (",
                $response->status_line, ")\n";
        }
    }

    # if we STILL don't have valid JSON, we look for it in expired
    # cache results, if we're allowed to...

    unless ( $raw_json and $decoded_json ) {
        if ( $options->{cache} ne 'never' ) {
            if ( $c2j_cache->exists_and_is_expired(
                                                 $expanded_jsonld_url->as_string
                 )
            ) {

                my $cache_object
                    = $c2j_cache->get_object( $expanded_jsonld_url->as_string );

                if ( $cache_object
                     and _verify_cache_object_policy($cache_object) ) {

                    $raw_json = $cache_object->value || undef;
                    if ($raw_json) {
                        $decoded_json = eval { $json_obj->decode($raw_json) };
                    }

                    if ( $raw_json and $decoded_json ) {
                        push @api_notes,
                            'We could not connect to our database right now, so we are providing cached data. This data was cached on '
                            . scalar( localtime( $cache_object->created_at() ) )
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
    my ( %publications_by_author, %research_activities_and_funding_by_role );

    foreach my $item ( @{ $data->{entry}->{jsonld}->{'@graph'} } ) {

        next unless $item->{'@type'};

        # ensure list of types ALWAYS represented as an array
        unless ( ref $item->{'@type'} eq 'ARRAY' ) {
            $item->{'@type'} = [ $item->{'@type'} ];
        }

        # handle main person
        if ( $item->{'@id'} eq $node_id or $item->{'@id'} eq $canonical_url ) {
            $person = $item;
        }

        # handle authorship and grants/research
        if ( ref $item and $item->{'@type'} ) {
            foreach my $type ( @{ $item->{'@type'} } ) {
                if ( $type eq 'vivo:Authorship' ) {    # pubs
                    if (     $item->{'linkedAuthor'}
                         and $item->{'linkedInformationResource'} ) {

                        my $pub_id = $item->{'linkedInformationResource'};
                        my $pub_is_claimed = undef;
                        if ( defined $item->{hasClaimedPublication}
                             and $item->{hasClaimedPublication} == 1 ) {
                            $pub_is_claimed = JSON::true;
                        }

                        push @{ $publications_by_author{ $item->{'linkedAuthor'}
                                } },
                            { id => $pub_id, is_claimed => $pub_is_claimed };
                    }
                } elsif ( $type eq 'vivo:ResearcherRole' ) {    # grants
                    if (     $item->{'researcherRoleOf'}
                         and $item->{'roleContributesTo'} ) {

                        push @{ $research_activities_and_funding_by_role{ $item
                                    ->{'researcherRoleOf'} } },
                            { role => $item->{label},
                              id   => $item->{'roleContributesTo'}
                            };
                    }
                }
            }
        }

        $items_by_url_id{ $item->{'@id'} } = $item;
    }    # end each item

    unless ($person) {
        warn
            "Tried to look up user specified, but got no results in the underlying data source. You can manually verify whether or not this is a valid Profiles user by visiting $canonical_url -- if you see a 404, the user's not in the system\n";
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
                        'personInPosition', 'educationalTraining',
                        'hasResearcherRole'
    ) {
        if ( !defined $person->{$field} ) {
            $person->{$field} = [];
        } elsif ( !ref $person->{$field} or ref $person->{$field} ne 'ARRAY' ) {
            $person->{$field} = [ $person->{$field} ];
        }
    }

    my %orng_data;
    state $url_cache ||= CHI->new(
                driver    => 'File',
                namespace => 'Profiles JSON API cache of raw Profiles API URLs',
                expires_variance => 0.25,
    );

    # load ORNG data
    foreach my $field ( 'hasFeaturedPublications', 'hasGlobalHealth',
                        'hasLinks',                'hasMentor',
                        'hasNIHGrantList',         'hasTwitter',
                        'hasSlideShare',           'hasMediaLinks',
                        'hasVideos',
    ) {

        if (     $person->{$field}
             and $person->{$field}
             =~ m{$current_or_legacy_profiles_root_url_regexp/?profile/(\d+)$} )
        {
            my $subject = $1;

            my $field_jsonld_url = $self->themed_base_domain->clone;
            $field_jsonld_url->path('/ORNG/JSONLD/Default.aspx');
            $field_jsonld_url->query_form( { expand      => 'true',
                                             showdetails => 'true',
                                             subject     => $subject
                                           }
            );

            # grab from cache, if available
            my $raw_json_for_field = $url_cache->get($field_jsonld_url);

            # ...or get from server, and cache if found
            unless ($raw_json_for_field) {
                my $field_jsonld_response = $self->_ua->get($field_jsonld_url);
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
                if ( $url_cache->exists_and_is_expired(
                                                    $field_jsonld_url->as_string
                     )
                ) {
                    my $potential_expired_cache_object
                        = $url_cache->get_object($field_jsonld_url->as_string );
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
                     and eval { $field_data->{entry}->{jsonld}->{'@graph'} } ) {
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

                my $matched_the_publication = 0;
                if ( defined $id and $id =~ m/^\d+$/ ) {
                    my $possible_id
                        = $self->themed_base_domain_profile_root . $id;
                    if ( $featured_publication_order_by_id{$possible_id} ) {
                        $featured_publication_order_by_id{$possible_id}
                            = $featured_num;
                        $matched_the_publication = 1;
                    }
                }

                if ( !$matched_the_publication and $pmid and $pmid =~ m/^\d+$/ )
                {

                    # If no ID is given but we have a PMID, go through
                    # every publication to see which one matches that
                    # PMID, and use the corresponding ID. This is
                    # inefficient, but not worth speeding up.

                EachPubToScanPMIDs:
                    foreach my $candidate_pub_data (
                            @{ $publications_by_author{ $person->{'@id'} } } ) {
                        my $candidate_pub_id = $candidate_pub_data->{id};
                        my $candidate_pmid
                            = $items_by_url_id{$candidate_pub_id}->{'pmid'};

                        if ( $candidate_pmid and $candidate_pmid == $pmid ) {
                            $featured_publication_order_by_id{$candidate_pub_id}
                                = $featured_num;
                            $matched_the_publication = 1;
                            last EachPubToScanPMIDs;
                        }
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
    if ( $person->{'mailingAddress'} ) {

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

    # make sure lat/lon is numeric -- and that it's never [0,0]
    my @lat_lon = ( undef, undef );
    if (     defined $person->{'latitude'}
         and $person->{'latitude'} =~ m/\d/
         and defined $person->{'longitude'}
         and $person->{'longitude'} =~ m/\d/
         and ( !(     ( $person->{'latitude'} == 0 )
                  and ( $person->{'longitude'} == 0 )
               )
         )
    ) {
        @lat_lon = ( $person->{'latitude'} + 0, $person->{'longitude'} + 0 );
    }

    # no email? see if it's publicly accessible via the vCard
    if ( !defined $person->{'email'} ) {
        my $vcard_url
            = URI->new( $self->themed_base_domain_profile_root
             . "modules/CustomViewPersonGeneralInfo/vcard.aspx?subject=$node_id"
            );

        # grab from cache, if available
        my $raw_vcard = $url_cache->get($vcard_url);

        # ...or get from server, and cache if found
        unless ($raw_vcard) {
            my $vcard_response = $self->_ua->get($vcard_url);
            if ( $vcard_response->is_success ) {
                $raw_vcard = $vcard_response->decoded_content;
                eval {
                    $url_cache->set( $vcard_url->as_string, $raw_vcard,
                                     '1 week' );
                };
            }
        }

        # ...or try to get from expired cache
        unless ($raw_vcard) {
            if ( $url_cache->exists_and_is_expired( $vcard_url->as_string ) ) {
                my $potential_expired_cache_object
                    = $url_cache->get_object( $vcard_url->as_string );
                if ($potential_expired_cache_object) {
                    if ( $potential_expired_cache_object->value() ) {
                        $raw_vcard = $potential_expired_cache_object->value();
                    }
                }
            }
        }

        # got some raw JSON? start using it
        if ($raw_vcard) {
            if ( $raw_vcard =~ m/[\r\n]EMAIL\S*?:(.*?)[\r\n]/s ) {
                my $likely_email = $1;
                if ( $likely_email
                     =~ m/^([\w+\-].?)+\@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+$/i ) {
                    $person->{'email'} = $likely_email;
                }
            }
        }
    }

    # Every once in a while, Profiles craps out and loses all
    # school/department/title data. In that case, we'll try to use
    # cached data.
    state $c2positions_cache ||=
        CHI->new( driver     => 'File',
                  namespace  => 'Profiles JSON API canonical_url_to_positions',
                  expires_in => '5 days',
                  expires_variance => 0.25,
        );

    my $final_data = {
        Profiles => [
            {  Name        => $person->{'fullName'},
               FirstName   => $person->{'firstName'},
               LastName    => $person->{'lastName'},
               ProfilesURL => (
                               $person->{'workplaceHomepage'}
                            || $self->themed_base_domain_profile_root . $node_id
               ),
               Email   => $person->{'email'},
               Address => { Address1  => $address[0],
                            Address2  => $address[1],
                            Address3  => $address[2],
                            Address4  => $address[3],
                            Telephone => $person->{'phoneNumber'},
                            Fax       => $person->{'faxNumber'},
                            Latitude  => $lat_lon[0],
                            Longitude => $lat_lon[1],
               },

               # only handling primary department at this time
               Department => eval {
                   my $dept_name;
                   my $cache_key = "$expanded_jsonld_url -> Department";

                   if ( $sorted_positions[0]->{'positionInDepartment'} ) {
                       my $dept_id
                           = $sorted_positions[0]->{'positionInDepartment'};
                       $dept_name = $items_by_url_id{$dept_id}->{'label'};
                       if ($dept_name) {
                           eval {
                               $c2positions_cache->set( $cache_key,
                                                        $dept_name );
                           };
                       }
                   }
                   $dept_name ||= eval { $c2positions_cache->get($cache_key) };
                   return $dept_name;
               },

               # only handling primary school at this time
               School => eval {
                   my $school_name;
                   my $cache_key = "$expanded_jsonld_url -> School";

                   if ( $sorted_positions[0]->{'positionInOrganization'} ) {
                       my $school_id
                           = $sorted_positions[0]->{'positionInOrganization'};
                       $school_name = $items_by_url_id{$school_id}->{'label'};
                       if ($school_name) {
                           eval {
                               $c2positions_cache->set( $cache_key,
                                                        $school_name );
                           };
                       }
                   }
                   $school_name
                       ||= eval { $c2positions_cache->get($cache_key) };
                   return $school_name;
               },

               # can handle multiple titles
               # but we're only listing first title at this time
               Title  => $person->{'preferredTitle'},
               Titles => [
                   eval {
                       my @titles = map { $_->{'label'} } @sorted_positions;
                       @titles = grep { defined and m/\w/ } @titles;

                       # multiple titles sometimes concatenated "A; B"
                       @titles = map { split /; / } @titles;

                       @titles = grep {m/\w/} @titles;

                       # If we don't have positions, but we do have
                       # the main title, fall back to main title. This
                       # was a bug we hit on 1/13/2017.
                       if ( !@titles and $person->{'preferredTitle'} ) {
                           @titles = $person->{'preferredTitle'};
                       }

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
                           return $self->themed_base_domain_profile_root
                               . $img_url_segment;
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
                               push @education_training, {
                                   degree   => trim( $item->{'degreeEarned'} ),
                                   end_date => trim( $item->{'endDate'} ),
                                   organization =>
                                       trim( $item->{'trainingAtOrganization'}
                                       ),
                                   department_or_school =>  # try new, old names
                                       trim(       $item->{'majorField'}
                                                || $item->{'departmentOrSchool'}
                                       ),
                               };
                           }

                           my %date_to_year;
                           foreach my $item (@education_training) {
                               my $start_date = $item->{start_date};
                               my $end_date   = $item->{end_date};

                           DateFieldName:
                               foreach my $date_field_name ( 'start_date',
                                                             'end_date' ) {

                                   unless ( defined $item->{$date_field_name}
                                        and $item->{$date_field_name} =~ m/\d/ )
                                   {
                                       $item->{$date_field_name} = '';
                                       next DateFieldName;
                                   }

                                   my $date = $item->{$date_field_name};

                                   if ( $date =~ m{\b((?:19|20)\d\d)$} ) {
                                       $date_to_year{$date} = $1;
                                   } elsif ( $date =~ m/((?:19|20)\d\d)-\d+$/ )
                                   {
                                       $date_to_year{$date} = $1;
                                   } elsif (
                                         $end_date =~ m/\b((?:19|20)\d\d)\b/ ) {
                                       $date_to_year{$end_date} = $1;
                                   }
                               }
                           }

                           @education_training = sort {
                               (  ( $date_to_year{ $b->{end_date} } || '' )
                                      cmp( $date_to_year{ $a->{end_date} } || ''
                                      )
                                   )
                                   || ( ( $b->{end_date} || '' )
                                        cmp( $a->{end_date} || '' ) )
                                   || (
                                     ( $date_to_year{ $b->{start_date} } || '' )
                                     cmp($date_to_year{ $a->{start_date} } || ''
                                     )
                                   )
                                   || ( ( $b->{start_date} || '' )
                                        cmp( $a->{start_date} || '' ) )
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

                           # split on comma, semicolon, or return
                           #   (optionally followed by " and ")
                           my $split_re
                               = qr/(?:\s*,\s*|\s*;\s*|\s*[\r\n]+\s*)(?:\s*\band\ )?/;
                           my @parts = split qr/$split_re/,
                               $person->{'freetextKeyword'};

                           # remove whitespace at start and end
                           # keep only keywords with alphanumeric content
                           @parts = map { trim($_) } @parts;
                           @parts = grep { defined and m/\w/ } @parts;

                           return @parts;
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
                                AwardLabel       => $item->{'label'},
                                AwardConferredBy => $item->{'awardConferredBy'},
                                AwardStartDate   => $item->{'startDate'},
                                AwardEndDate     => $item->{'endDate'},
                           };

                           $award->{Summary}
                               = join( ', ',
                                       map { trim($_) }
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
                       ( $b->{'AwardStartDate'} || '' )
                           cmp( $a->{'AwardStartDate'} || '' )
                   } @awards;
                   return \@awards;
               },

               Publications => eval {
                   my @publications;
                   unless ( $options->{no_publications} ) {

                       foreach my $pub_data (
                            @{ $publications_by_author{ $person->{'@id'} } } ) {

                           my $pub_id = $pub_data->{id};
                           my $pub    = $items_by_url_id{$pub_id};

                           # In January 2016, Profiles RDF stopped
                           #   including the list of authors in the
                           #   "informationResourceReference"
                           # It *should* look like:
                           #   "Last A, Last B. Title. Etc."
                           # But we were getting only:
                           #   "Title. Etc."
                           # So as a temporary workaround, we're
                           #   adding the author list back in.

                           my $title = $pub->{'informationResourceReference'};
                           {
                               my $author_list = $pub->{'hasAuthorList'};
                               if (     $title
                                    and length $title
                                    and $author_list
                                    and length $author_list
                                    and $title !~ m/\Q$author_list\E/i ) {
                                   $title = "$author_list. $title";
                               }
                           }

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
                               Date => (
                                   eval {
                                              $pub->{'publicationDate'}
                                           && $pub->{'publicationDate'}
                                           !~ m/^1900-01-01/;
                                   } ? $pub->{'publicationDate'} : undef
                               ),
                               Year => (
                                   eval {
                                       $pub->{'year'} && $pub->{'year'} > 1900;
                                   } ? $pub->{'year'} : undef
                               ),

                               PublicationCategory =>
                                   ( $pub->{'hmsPubCategory'} || undef ),

                               PublicationTitle  => $title,
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

                               Claimed => ( defined $pub_data->{is_claimed}
                                            ? $pub_data->{is_claimed}
                                            : undef
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

                       # individually numbered entries data structure?
                       my @numbered_style_links;
                       if (    !@links
                            and $orng_data{'hasLinks'}->{links_count}
                            and $orng_data{'hasLinks'}->{links_count}
                            =~ m/^\d+$/ ) {

                           my $max_links_count
                               = $orng_data{'hasLinks'}->{links_count};

                           for ( my $i = 0; $i < $max_links_count; $i++ ) {
                               if ( $orng_data{hasLinks}->{"link_$i"}
                                   and ref $orng_data{hasLinks}->{"link_$i"} ) {
                                   my $link = $orng_data{hasLinks}->{"link_$i"};
                                   push @links,
                                       { Label => $link->{name},
                                         URL   => $link->{url}
                                       };
                               }
                           }
                       }

                       # array style data structure?
                       if (    !@links
                            and $orng_data{'hasLinks'}
                            and $orng_data{'hasLinks'}->{links}
                            and ref $orng_data{'hasLinks'}->{links} eq 'ARRAY' )
                       {

                           foreach
                               my $link ( @{ $orng_data{'hasLinks'}->{links} } )
                           {
                               if ( $link and $link->{link_url} ) {
                                   push @links,
                                       { Label => $link->{link_name} || undef,
                                         URL => $link->{link_url}
                                       };
                               }
                           }
                       }

                       # only keep links that are a valid URI with a valid host
                       @links = grep {
                           eval { URI->new( $_->{URL} )->host =~ m/\w/; }
                       } @links;

                       return @links;
                   }
               ],

               MediaLinks_beta => [
                   eval {

                       # $orng_data{'hasMediaLinks'}->{links} is
                       # sometimes accidentally double-encoded as
                       # JSON. So user "wilson.liao" is corect but
                       # user "anirvan.chatterjee" is wrong.

                       my @links;

                       my @raw_links;
                       if ( eval { $orng_data{'hasMediaLinks'}->{links} }
                            and ref $orng_data{'hasMediaLinks'}->{links} eq
                            'ARRAY' ) {
                           @raw_links
                               = @{ $orng_data{'hasMediaLinks'}->{links} };
                       } elsif (
                           eval {
                               $orng_data{'hasMediaLinks'}->{links};
                           }
                       ) {
                           my $raw_json = $orng_data{'hasMediaLinks'}->{links};
                           if ( utf8::is_utf8($raw_json) ) {
                               $raw_json = Encode::encode_utf8($raw_json);
                               my $decoded = eval { decode_json($raw_json) };
                               if ( $decoded and ref $decoded eq 'ARRAY' ) {
                                   @raw_links = @{$decoded};
                               }
                           }
                       }
                       @raw_links = grep { ref($_) eq 'HASH' } @raw_links;

                       foreach my $link (@raw_links) {

                           my $date;
                           if ( $link->{link_date}
                                =~ m{^(\d+)/(\d+)/((?:19|20)\d\d)$} ) {
                               $date = "$3-$1-$2";
                           }

                           push @links,
                               { Label => $link->{link_name},
                                 URL   => $link->{link_url},
                                 Date  => $date
                               };
                       }
                       return @links;
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
                       if ( eval { @{ $orng_data{'hasVideos'}->{videos} } } ) {
                           foreach my $entry (
                                      @{ $orng_data{'hasVideos'}->{videos} } ) {
                               next unless $entry->{url} =~ m/^http/;
                               unless ( $entry->{name} =~ m/\w/ ) {
                                   $entry->{name} = 'Video';
                               }
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
                                        and ref $value->{Locations} eq 'ARRAY' )
                                   {
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

               ResearchActivitiesAndFunding => [
                   eval {
                       my @grants;
                       if ( $research_activities_and_funding_by_role{ $person->{
                                    '@id'} } ) {
                           my @grant_roles
                               = @{
                               $research_activities_and_funding_by_role{
                                   $person->{'@id'}
                               }
                               };
                           foreach my $role_group (@grant_roles) {
                               my $grant_id   = $role_group->{id};
                               my $grant_role = $role_group->{role};
                               my $raw_grant  = $items_by_url_id{$grant_id};

                               if ($raw_grant) {
                                   my $grant
                                       = {
                                        Role      => $grant_role,
                                        StartDate => $raw_grant->{startDate},
                                        EndDate   => $raw_grant->{endDate},
                                        Title     => $raw_grant->{label},
                                        Sponsor => $raw_grant->{grantAwardedBy},
                                        SponsorAwardID =>
                                            $raw_grant->{sponsorAwardId},
                                       };

                                   # no sponsor? check to see if award
                                   # ID looks like it could maybe be
                                   # from the NIH, and insert that
                                   if ( !$grant->{Sponsor} ) {
                                       my $award_id = $grant->{SponsorAwardID};
                                       if ($award_id) {
                                           if ((      $award_id =~ m/\d{5,12}/
                                                  and $award_id =~ m/[A-Z]/
                                               )
                                               or ( $award_id
                                                   =~ m/\d[A-Z]\d+[A-Z][A-Z]-\d+/
                                               )
                                           ) {
                                               $grant->{Sponsor} = 'NIH';
                                               $grant->{api_notes}
                                                   = "we're not 100% sure of sponsor, but NIH is likely";
                                           }
                                       }
                                   }

                                   # verify that dates are YYYY-MM-DD, or undef
                                   foreach my $field ( 'StartDate', 'EndDate' )
                                   {
                                       if ( defined $grant->{$field}
                                            and $grant->{$field}
                                            !~ m/^\d{4}-\d{2}-\d{2}$/ ) {
                                           $grant->{$field} = undef;
                                       }
                                   }

                                   push @grants, $grant;
                               }
                           }
                       }

                       # remove any duplicate grants
                       {
                           my %serialized_grants;
                           foreach my $grant (@grants) {
                               my $serialized = dump($grant);
                               $serialized_grants{$serialized} = $grant;
                           }
                           @grants = values %serialized_grants;
                       }

                       # sort grants by date

                       {
                           no warnings 'uninitialized';
                           @grants = sort {
                               ( ( $b->{EndDate} || $b->{StartDate} )
                                  cmp( $a->{EndDate} || $a->{StartDate} ) )
                                   || ( $b->{StartDate} cmp $a->{StartDate} )
                           } @grants;
                       }

                       return @grants;
                   }
               ],

            }
        ]
    };

    # if we have new ResearchActivitiesAndFunding data, but not the
    # old NIHGrants_beta, then we do our best to back-port
    # ResearchActivitiesAndFunding to NIHGrants_beta
    if (     $final_data
         and $final_data->{Profiles}->[0]->{ResearchActivitiesAndFunding}
         and !eval { @{ $final_data->{Profiles}->[0]->{NIHGrants_beta} } } ) {

        foreach my $grant (
             @{ $final_data->{Profiles}->[0]->{ResearchActivitiesAndFunding} } )
        {
            if ( $grant and $grant->{Sponsor} and $grant->{Sponsor} eq 'NIH' ) {
                my $grant_year = $grant->{EndDate};
                if ( length $grant_year ) {
                    $grant_year =~ s/-.*$//;
                }
                push @{ $final_data->{Profiles}->[0]->{NIHGrants_beta} },
                    {
                    Title            => $grant->{Title},
                    NIHFiscalYear    => $grant_year,
                    NIHProjectNumber => $grant->{SponsorAwardID},
                    api_notes =>
                        'Deprecated, use ResearchActivitiesAndFunding instead. The fiscal year may be off.',
                    };
            }
        }
    }

    foreach my $person_data ( @{ $final_data->{Profiles} } ) {
        foreach my $key (qw( Publications MediaLinks MediaLinks_beta )) {
            if (     $person_data->{$key}
                 and @{ $person_data->{$key} }
                 and $person_data->{$key}->[0]
                 and $person_data->{$key}->[0]->{Date} ) {
                @{ $person_data->{$key} }
                    = sort { ( $b->{Date} || '' ) cmp( $a->{Date} || '' ) }
                    @{ $person_data->{$key} };
            }
        }
    }

    if (@api_notes) {
        $final_data->{api_notes} = join ' ', @api_notes;
    }

    # kill all leading and trailing whitespace
    my $v = Data::Visitor::Callback->new(
        plain_value => sub {
            if ( defined($_) and length($_) and (m/^\s|\s$/) ) {
                s/^\s+//;
                s/\s+$//;
            }
            return $_;
        },
    );

    $v->visit($final_data);

    my $out = $json_obj->encode($final_data);
    return $out;
}

###############################################################################

# ensure that a cached object, expired or not, is never more than 14 days old
# returns true if usable, false otherwise
sub _verify_cache_object_policy {

    my $how_many_days_old_cached_data_can_we_return = 14;

    my $cache_object = shift;
    my $cached_time = eval { $cache_object->created_at() };
    unless ($cached_time) {
        return 0;
    }

    my $seconds_per_day = 60 * 60 * 24;
    if ( $cached_time >= (
             time - (
                 $how_many_days_old_cached_data_can_we_return * $seconds_per_day
             )
         )
    ) {
        return 1;
    }

    return 0;
}

1;

# Local Variables:
# mode: perltidy
# End:
