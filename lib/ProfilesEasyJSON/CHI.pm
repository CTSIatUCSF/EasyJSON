#!/usr/bin/perl

# This is a subclass of the CHI cache, that overrides the defaults by:
#
#  - trying to set the disk cache location to
#    /srv/ProfilesEasyJSON-cache or /tmp/ProfilesEasyJSON-cache
#  - setting the default expires_variance to 0.25
#
# more details at https://metacpan.org/pod/CHI#SUBCLASSING-AND-CONFIGURING-CHI

package ProfilesEasyJSON::CHI;
use lib '..';
use CHI;
use File::Path qw( mkpath );
use File::Spec::Functions qw( catdir  tmpdir );
use base 'CHI';
use 5.10.0;

my @dir_options = ( catdir( '/srv',   'ProfilesEasyJSON-cache' ),
                    catdir( tmpdir(), 'ProfilesEasyJSON-cache' ) );

my $root_dir;
foreach my $dir_option (@dir_options) {
    unless ( -d $dir_option ) {
        eval { mkpath($dir_option) };
    }
    if ( -d $dir_option ) {
        if ( -w $dir_option ) {
            $root_dir = $dir_option;
            last;
        } else {
            warn
                "Could not write to cache directory '$dir_option' -- skipping\n";
        }
    } else {
        warn "Could not create cache directory '$dir_option' -- skipping\n";
    }
    next;
}

unless ($root_dir) {
    die "Sorry, could not create a writable cache directory -- we tried ",
        join( ', ', @dir_options ), "\n";
}

__PACKAGE__->config(
    {  storage => { local_file => { driver => 'File', root_dir => $root_dir } },
       defaults => { storage => 'local_file', expires_variance => 0.25 },
       memoize_cache_objects => 1,
    }
);

1;
