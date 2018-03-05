#!/usr/bin/env perl
use 5.020_000;
use warnings;
use mro qw<c3>;
use feature qw<:5.20>;
use utf8;
no strict qw<refs>;
no warnings qw<uninitialized>;
use Const::Fast qw<const>;
use Carp qw<croak>;
use Template qw<>;
use Text::Xslate qw<>;
use URI::Escape qw<>;

const my $DEFAULT_ITERATIONS => 30;
const my $DEFAULT_RUNTIME    => 10; # seconds

my $tt = Template->new(
    UNICODE      => 1,
    INCLUDE_PATH => [ './tt_templates' ],
    FILTERS      => {
        uri => \&URI::Escape::uri_escape_utf8,
    },
    COMPILE_DIR  => './.tt_cache/',
    COMPILE_EXT  => '.ttc2',
);

my $xs = Text::Xslate->new(
    verbose     => 1,          # warn about non-trivial stuff
    type        => 'html',
    input_layer => ':utf8',    # No need for :set bomb
    path        => [ './tx_templates' ],
    module      => [
        # Use similar variable methods to TT2
        'Text::Xslate::Bridge::TT2Like',
    ],
    function => {
        uri => \&URI::Escape::uri_escape_utf8,
    },
    cache_dir => './.tx_cache/',
);

exit 0;
