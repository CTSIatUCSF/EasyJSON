#!perl

use lib 'lib', '../lib';
use HTTP::Request::Common;
use JSON qw( decode_json );
use Plack::Test;
use Plack::Util;
use Test::More;
binmode STDOUT, ':utf8';
use strict;
use warnings;

my $app;
if ( -r 'app.psgi' ) {
    $app = Plack::Util::load_psgi 'app.psgi';
} elsif ( -r '../app.psgi' ) {
    $app = Plack::Util::load_psgi '../app.psgi';
}

test_psgi $app, sub {
    my $cb = shift;

    # no source or req type
    {
        my $req = GET('http://localhost/');
        my $res = $cb->($req);
        is $res->code, 400, 'call without params should return 400';
    }

    # no req type
    {
        my $req = GET('http://localhost/?source=Anirvan_script');
        my $res = $cb->($req);
        is $res->code, 400, 'call without request type should return 400';
    }

    # good req type and source
    {
        my $req
            = GET(
            'http://localhost/?source=Anirvan_script&FNO=anirvan.chatterjee@ucsf.edu'
            );
        my $res = $cb->($req);
        is $res->code, 200, 'reasonable call should return 200';

    SKIP: {
            skip "invalid data, can't test", 1 unless $res->code == 200;
            like( $res->decoded_content, qr/Anirvan/,
                  'call for Anirvan should mention Anirvan' );
        }
    }

    # 404 for nonexistent user
    {
        my $req = GET(
              'http://localhost/?source=Anirvan_script&FNO=fake.user@ucsf.edu');
        my $res = $cb->($req);
        is $res->code, 404, 'FNO call for nonexistent user should return 404';
    }

    # 404 for nonexistent user
    {
        my $req
            = GET(
            'http://localhost/?source=Anirvan_script&ProfilesURLName=fake.user@ucsf.edu'
            );
        my $res = $cb->($req);
        is $res->code, 404,
            'URL name call for nonexistent user should return 404';
    }

    # good req type and source
    {
        my $req
            = GET(
            'http://localhost/?source=Anirvan_script&ProfilesURLName=ronald.arenson'
            );
        my $res = $cb->($req);
        is $res->code, 200, 'reasonable call should return 200';

    SKIP: {
            skip "invalid data, can't test", 1 unless $res->code == 200;
            like( $res->decoded_content, qr/Ronald/,
                  'call for Ronald should mention Ronald' );
        }
    }

};

done_testing;

# Local Variables:
# mode: perltidy
# End:
