#!perl

use lib '.';
use HTTP::Request::Common;
use JSON qw( decode_json );
use Plack::Test;
use Plack::Util;
use Test::More;
binmode STDOUT, ':utf8';
use strict;
use warnings;

my $app = Plack::Util::load_psgi 'app.psgi';

test_psgi $app, sub {
    my $cb = shift;

    # no source or req type
    {
        my $req = GET('http://localhost/');
        my $res = $cb->($req);
        is $res->code, 400;
    }

    # no req type
    {
        my $req = GET('http://localhost/?source=Anirvan_script');
        my $res = $cb->($req);
        is $res->code, 400;
    }

    # no req type
    {
        my $req
            = GET(
            'http://localhost/?source=Anirvan_script&FNO=anirvan.chatterjee@ucsf.edu'
            );
        my $res = $cb->($req);
        is $res->code, 200;
        like( $res->decoded_content, qr/Anirvan/ );
    }

    # 404 for nonexistent user
    {
        my $req = GET(
            'http://localhost/?source=Anirvan_script&FNO=fake.user@ucsf.edu');
        my $res = $cb->($req);
        is $res->code, 404;
    }

};

done_testing;

# Local Variables:
# mode: perltidy
# End:
