#!/usr/bin/perl

use lib '.';
use CGI::PSGI;
use Data::Dump qw( dump );
use JSON qw( encode_json );
use ProfilesEasyJSON qw( identifier_to_json );
use 5.8.8;
use utf8;
use strict;
use warnings;

my %valid_types = ( FNO             => 'FNO',
                    Person          => 'Person',
                    EmployeeID      => 'EmployeeID',
                    ProfilesURLName => 'PrettyURL',
                    ProfilesNodeID  => 'ProfilesNodeID',
                    URL             => 'URL'
);

my $app = sub {
    my $env = shift;
    my $q   = CGI::PSGI->new($env);

    my $params = $q->Vars;

    my ( $identifier_type, $identifier, $error, $json );
    my $http_status = 200;

    foreach my $key ( sort keys %valid_types ) {
        if ( exists $params->{$key} ) {
            $identifier_type = $valid_types{$key};
            if ( $params->{$key} =~ m/^(\S+)$/ ) {
                $identifier = $1;
            } else {
                my $identifier_printable = dump($identifier);
                $error
                    = { error =>
                    "Invalid argument '$identifier_printable' for identifier type $key"
                    };
                $http_status = "400 Invalid argument sent";
            }
            last;
        }
    }
    unless ($identifier_type) {
        $error
            = { error =>
            "You didn't specify an identifier type to look up! We were expecting to see one of the following: "
            . join( ' / ', map {"?$_=..."} sort keys %valid_types ) };
        $http_status = "400 Invalid argument sent";
    }

    if ( $identifier_type and $identifier ) {

        my $options = {};
        if ( $params->{mobile} and $params->{mobile} =~ m/^1|on$/i ) {
            $options->{mobile} = 1;
        }

        if ( $params->{publications} and $params->{publications} eq 'full' ) {
            $options->{no_publications} = 0;
        } else {
            $options->{no_publications} = 1;
        }

        if ( $params->{cache} and $params->{cache} =~ m/^(always|never)$/ ) {
            $options->{cache} = lc $1;
        }

        my $error_string = '';
        $SIG{__WARN__} = sub { $error_string = $_[0]; chomp $error_string; };
        $json = identifier_to_json( $identifier_type, $identifier, $options );
        delete $SIG{__WARN__};

        unless ($json) {
            $error = { error => $error_string || 'Unknown error' };
            if ( $error_string
                 =~ m/Tried to look up user.*but got no results/ ) {
                $http_status = "404 Could not find user";
            }
        }
    }

    # prepare output

    my %header_options = ( -type                        => 'application/json',
                           -charset                     => 'utf-8',
                           -status                      => $http_status,
                           -access_control_allow_origin => '*',
    );

    my $output;
    if ($error) {
        $output = encode_json($error);
    } else {
        $output = $json;
    }

    if ( $params->{callback} ) {
        $output = "$params->{callback}($output)";
        $header_options{'-type'} = 'text/javascript';
    }

    return [ $q->psgi_header(%header_options), [$output] ];

};

# Local Variables:
# mode: perltidy
# End:
