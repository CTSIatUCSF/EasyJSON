#!perl

use lib '.', '..';
use Data::Dump;
use String::Util qw( trim );
use Test::More;
use Test::NoWarnings;
binmode STDOUT, ':utf8';
use utf8;
use strict;
use warnings;

my @input = ( ['Larry, Moe, and Curly'],
              [ 'Larry',   'Moe',   'and Curly' ],
              [ 'Larry',   'Moe',   'and Curly' ],
              [ ' Larry ', ' Moe ', ' and Curly ' ],
              ["Larry\r\nMoe\r\nCurly\r\n"],
              ["Larry; Moe; Curly"],
              ["Larry; Moe; and Curly"],
              [ " ", "Larry, Moe,   and  Curly", "" ],
);

plan tests => 1 + scalar @input;

my $split_re = qr/(?:\s*,\s*|\s*;\s*|\s*[\r\n]+\s*|\A)(?:\s*\band\s+)?/;

foreach my $test (@input) {
    my $input = join "\n", @{$test};
    my @parts = split qr/$split_re/, $input;
    @parts = map { trim($_) } @parts;
    @parts = grep { defined($_) and ( $_ =~ m/\w/ ) } @parts;
    is_deeply( \@parts, [ 'Larry', 'Moe', 'Curly' ] );
}

# Local Variables:
# mode: perltidy
# End:
