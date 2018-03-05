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
use Path::Tiny qw<path>;
use Cpanel::JSON::XS qw<>;
use File::Basename qw<basename>;
use Time::HiRes qw<gettimeofday tv_interval>;
use FindBin qw<>;

const my $DEFAULT_ITERATIONS => 30;
const my $DEFAULT_RUNTIME    => 10; # seconds
const my $TT_DIR             => './tt_templates/';
const my $TX_DIR             => './tx_templates/';

my $TT = Template->new(
    UNICODE      => 1,
    INCLUDE_PATH => [ $TT_DIR ],
    FILTERS      => {
        uri => \&URI::Escape::uri_escape_utf8,
    },
    COMPILE_DIR  => "$FindBin::RealBin/.tt_cache/",
    COMPILE_EXT  => '.ttc2',
);

my $TX = Text::Xslate->new(
    verbose     => 1,          # warn about non-trivial stuff
    type        => 'html',
    input_layer => ':utf8',    # No need for :set bomb
    path        => [ $TX_DIR ],
    module      => [
        # Use similar variable methods to TT2
        'Text::Xslate::Bridge::TT2Like',
    ],
    function => {
        uri => \&URI::Escape::uri_escape_utf8,
    },
    cache_dir => './.tx_cache/',
);
my $JSON = Cpanel::JSON::XS->new->utf8;

{
    my @jsons = glob './data/*.json';
    for my $file (@jsons) {
        my $data    = $JSON->decode(path($file)->slurp_utf8);
        my $base    = basename($file) =~ s![.]json\z!!xmsgr;
        benchmark($base, $data);
    }
}

exit 0;

sub benchmark {
    my ($base, $data) = @_;

    my $tt_file = "$base.tt";
    croak "No such file: $TT_DIR/$tt_file" if !-f "$TT_DIR/$tt_file";
    my $tx_file = "$base.tx";
    croak "No such file: $TX_DIR/$tx_file" if !-f "$TX_DIR/$tx_file";

    tt_exec($TT, $tt_file, $data);    # cache things

    my $tt_t0 = [gettimeofday];
    tt_exec($TT, $tt_file, $data) for 1..$DEFAULT_ITERATIONS;
    my $tt_done = tv_interval($tt_t0);
    # TT took $tt_done to do $DEFAULT_ITERATIONS iterations.
    # it'll take ... to run for about $DEFAULT_RUNTIME.
    # $tt_done : $DEFAULT_ITERATIONS = $DEFAULT_RUNTIME : x
    my $tt_iterate = int( $DEFAULT_ITERATIONS * $DEFAULT_RUNTIME / $tt_done );
    warn "$base: Doing $tt_iterate iterations for TT...\n";
    $tt_t0 = [gettimeofday];
    tt_exec($TT, $tt_file, $data) for 1..$tt_iterate;
    $tt_done = tv_interval($tt_t0);
    warn sprintf "%s %s done %d iterations in %.5f, i.e. %.4f/s\n", 'TT', $base, $tt_iterate, $tt_done, $tt_iterate/$tt_done;

    tx_exec($TX, $tx_file, $data);    # cache things

    my $tx_t0 = [gettimeofday];
    tx_exec($TX, $tx_file, $data) for 1..$DEFAULT_ITERATIONS;
    my $tx_done = tv_interval($tx_t0);
    # TT took $tx_done to do $DEFAULT_ITERATIONS iterations.
    # it'll take ... to run for about $DEFAULT_RUNTIME.
    # $tx_done : $DEFAULT_ITERATIONS = $DEFAULT_RUNTIME : x
    my $tx_iterate = int( $DEFAULT_ITERATIONS * $DEFAULT_RUNTIME / $tx_done );
    warn "$base Doing $tx_iterate iterations for TX...\n";
    $tx_t0 = [gettimeofday];
    tx_exec($TX, $tx_file, $data) for 1..$tx_iterate;
    $tx_done = tv_interval($tx_t0);
    warn sprintf "%s %s done %d iterations in %.5f, i.e. %.4f/s\n", 'TX', $base, $tx_iterate, $tx_done, $tx_iterate/$tx_done;
}

sub tt_exec {
    my ($tt, $tt_file, $data) = @_;

    my $output = '';
    $tt->process($tt_file, $data, \$output)
        or die $tt->error;
}

sub tx_exec {
    my ($tx, $tx_file, $data) = @_;

    my $output = '';
    $output = $tx->render($tx_file, $data);
}
