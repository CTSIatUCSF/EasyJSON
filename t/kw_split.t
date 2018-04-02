#!perl

use lib 'lib', '../lib';
use Data::Dump qw( dump );
use Test::More;
use Test::NoWarnings;
use ProfilesEasyJSON;
binmode STDOUT, ':utf8';
use utf8;
use strict;
use warnings;

my @input = ( ['Larry, Moe, and Curly'],
              [ 'Larry',   'Moe',   'and Curly' ],
              [ ' Larry ', ' Moe ', ' and Curly ' ],
              ["Larry\r\nMoe\r\nCurly\r\n"],
              ["Larry; Moe; Curly"],
              ["Larry; Moe; and Curly"],
              [ ' ',      "Larry, Moe,   and  Curly", '' ],
              [ '(Larry', 'Moe)',                     '(Curly)' ],
              [ 'Larry (', '-',     'Moe)', ' and Curly  ' ],
              [ '*Larry',  '* Moe', 'Curly ' ],
              ["•Larry\n• Moe •\tCurly"],
              ["*Larry\n* Moe *\tCurly"],
              ['Areas of interest include: Larry, Moe, and Curly'],
              ['Larry, Moe, and Curly.'],
              [ 'Clinical Interests:', "Larry\nMoe\nCurly\n" ],
              ['Research interests: Larry, Moe, Curly'],
              ['Scholarly interests: Larry, Moe, Curly'],
              ['My interests include: Larry, Moe, Curly'],
              ['My main research interest relates to Larry, Moe, Curly'],
              ['and Larry, and Moe, Curly'],
              [ 'e.g.', 'Larry', 'Moe', 'Curly' ],
              ['the Larry, Moe, and Curly  '],
              [ 'Larry (e.g. ', 'Moe', 'Curly)' ],
);

plan tests => 1 + scalar @input;

foreach my $test (@input) {
    is_deeply( [ ProfilesEasyJSON::_split_keyword_string( @{$test} ) ],
               [ 'Larry', 'Moe', 'Curly' ],
               dump($test), );
}

# Local Variables:
# mode: perltidy
# End:
