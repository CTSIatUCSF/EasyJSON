#!/usr/bin/perl

use lib '.';
use CGI::PSGI;
use Data::Dump qw( dump );
use Encode qw( decode_utf8 );
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

    # Did the user access /url_endpoint/something_random_and_unwanted ?
    unless ( $q->path_info() =~ m{^/?$} ) {
        my $suggested_api_url = $q->url() . '/';
        $error
            = { error =>
            "This is an invalid API endpoint. Did you want to access $suggested_api_url ?"
            };
        $http_status = "404 Not found";
    }

    foreach my $key ( sort keys %valid_types ) {
        if ( exists $params->{$key} ) {
            $identifier_type = $valid_types{$key};
            if ( $params->{$key} =~ m/^(\S+)$/ ) {
                $identifier = $1;
            } else {
                my $identifier_printable = dump($identifier);
                $error
                    ||= { error =>
                    "Invalid argument '$identifier_printable' for identifier type $key"
                    };
                $http_status = "400 Invalid argument sent";
            }
            last;
        }
    }
    unless ($identifier_type) {
        $error
            ||= { error =>
            "You didn't specify an identifier type to look up! We were expecting to see one of the following: "
            . join( ' / ', map {"?$_=..."} sort keys %valid_types ) };
        $http_status = "400 Invalid argument sent";
    }

    unless ( ( $params->{source} and $params->{source} =~ m/\w\w\w/ )
             or $q->referer() ) {
        $error
            ||= { error =>
            q{Missing source! Please send a source= parameter to let us know who's sending the request. For example, ?source=example.ucsf.edu if the data's being used on that website, or ?source=Foobar+University+XYZ+Tool for a script -- it doesn't have to be fancy, just some way to help us understand usage, and so we can get a hold of you in case of an emergency.}
            };
        $http_status = "400 Invalid argument sent";
    }

    if ( $identifier_type and $identifier and !$error ) {

        my $options = {};
        if ( $params->{mobile} and $params->{mobile} =~ m/^(1|on)$/i ) {
            $options->{mobile} = 1;
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

    # Without this, Perl 5.8.8 returns invalid data.
    # But it's not needed on Perl 5.16.
    # I don't understad this.
    if ($] <= 5.010000) {
	$output = decode_utf8($output);
    }

    return [ $q->psgi_header(%header_options), [$output] ];

};

# Local Variables:
# mode: perltidy
# End:
