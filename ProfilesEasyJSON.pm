#!/usr/bin/perl

# TODO:
# disable JSON pretty encoding in mobile view?
# add timeout support?

package ProfilesEasyJSON;
use CHI;
use Data::Dump qw( dump );
use Encode qw( encode );
use JSON;
use LWP::UserAgent;
use String::Util qw( trim );
use URI::Escape qw( uri_escape );
use 5.12.0;
binmode STDOUT, ':utf8';
use parent qw( Exporter );
use strict;
use warnings;

our @EXPORT_OK
    = qw( identifier_to_json identifier_to_canonical_url canonical_url_to_json );
our $ua;

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

    state $cache = CHI->new(
                 driver    => 'File',
                 namespace => 'Profiles JSON API identifier_to_canonical_url',
                 expires_variance => 0.25,
    );

    my $cache_key = join "\t", ( $identifier_type // '' ),
        ( $identifier // '' );

    unless ( $options->{cache} and $options->{cache} eq 'never' ) {
        my $canonical_url = $cache->get($cache_key);
        if ($canonical_url) {
            return $canonical_url;
        }
    }

    unless ( defined $identifier and $identifier =~ m/\w/ ) {
        warn 'Unknown identifier: ' . dump($identifier), "\n";
        return;
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

            if ( $cache->exists_and_is_expired($url) ) {
                my $potential_expired_cache_object = $cache->get_object($url);
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
            eval { $cache->set( $cache_key, $node_uri, '2 months' ) };
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

    unless (     $options->{cache}
             and $options->{cache} =~ m/^(fallback|always|never)$/ ) {
        $options->{cache} = 'fallback';
    }

    unless ( defined $canonical_url
         and $canonical_url =~ m{^http://profiles.ucsf.edu/profile/(\d+)$} ) {
        warn 'Invalid canonical URL: ', dump($canonical_url), "\n";
        return;
    }

    state $cache = CHI->new(
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
        my $cache_object = $cache->get_object($expanded_jsonld_url);
        if ($cache_object) {
            $raw_json = $cache_object->value;
        }
    } elsif ( $options->{cache} eq 'fallback' ) {
        $raw_json = $cache->get($expanded_jsonld_url);
    }
    unless ($raw_json) {
        _init_ua() unless $ua;
        my $response = $ua->get($expanded_jsonld_url);
        if ( $response->is_success ) {
            $raw_json = $response->decoded_content;
            $cache->set( $expanded_jsonld_url, $raw_json, '23.5 hours' );
        } else {
            warn "Could not load URL ", dump($expanded_jsonld_url),
                " to look up JSON-LD (",
                $response->status_line, ")\n";
            if ( $cache->exists_and_is_expired($expanded_jsonld_url) ) {
                my $potential_expired_cache_object
                    = $cache->get_object($expanded_jsonld_url);
                if ($potential_expired_cache_object) {
                    $raw_json = $potential_expired_cache_object->value()
                        || undef;
                }
            }
        }
    }
    unless ($raw_json) {
        return;
    }

    state $json_obj = JSON->new->pretty(1);
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
        qw( email fullName mailingAddress phoneNumber faxNumber latitude longitude mainImage preferredTitle personInPrimaryPosition )
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
                           ->{positionInDepartment} }->{label};
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
                   eval {
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
                              _title_to_title_parts(
                                          $items_by_url_id{$_}
                                              ->{informationResourceReference}
                              ),
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

    if ( $options->{no_publications} ) {
        delete $final_data->{Publications};
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

sub _title_to_title_parts {
    my $text = shift;
    if ( $text
        =~ m/^(\w.*?)\. (\S.*[[:punct:]]) ([A-Za-z].+?)\. ((?:19\d\d|2[01]\d\d).*?)(?:; (.*?))?\.$/
        ) {
        my ( $authors, $title, $journal, $date, $issue )
            = ( $1, $2, $3, $4, $5 || undef );

        # if there's a period only  at end of title, then remove
        $title =~ s/^([^\.]+)\.$/$1/;

        return ( ArticleTitle_beta    => $title,
                 AuthorList_beta      => $authors,
                 Publication_beta     => $journal,
                 Date_beta            => $date,
                 IssueVolumePage_beta => $issue,
                 PublicationTitle     => $text,
        );
    } else {
        my @years = ( $text =~ m/\b(19\d\d|20[01]\d)\b/g );
        my $year;
        if ( @years and @years == 1 ) {
            return ( PublicationTitle => $text, Date_beta => $years[0] );
        } else {
            return ( PublicationTitle => $text );
        }
    }
}

1;

# Local Variables:
# mode: perltidy
# End:
