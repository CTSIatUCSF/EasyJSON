requires 'perl', '5.010000';

requires 'CGI::PSGI';
requires 'CHI';
requires 'Config::Auto';
requires 'Crypt::RC4';
requires 'Data::Dump';
requires 'Data::Validate::Domain', '0.14';
requires 'Data::Visitor::Callback';
requires 'IO::All';
requires 'JSON';
requires 'List::AllUtils';
requires 'LWP::UserAgent', '6.0';
requires 'HTTP::Message', '6.06';
requires 'MIME::Base64';
requires 'Moo';
requires 'namespace::clean';
requires 'Plack';
requires 'Regexp::Assemble';
requires 'String::Util';
requires 'Text::CSV::Slurp';
requires 'Types::Standard', '1.002001';
requires 'URI';
requires 'URI::Escape';

on 'test' => sub {
    requires 'Test::More';
    requires 'Test::NoWarnings';
    requires 'Test::Warn', '0.31';
};
