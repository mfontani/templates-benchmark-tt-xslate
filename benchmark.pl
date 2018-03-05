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
use Text::Table qw<>;

const my $DEFAULT_ITERATIONS => 50;
const my $DEFAULT_RUNTIME    => 1; # seconds
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
    my $table = Text::Table->new('Function', 'TT/s', 'TX/s', '+/-');
    my @jsons = reverse glob './data/*.json';
    for my $file (@jsons) {
        my $data    = $JSON->decode(path($file)->slurp_utf8);
        my $base    = basename($file) =~ s![.]json\z!!xmsgr;
        benchmark($base, $data, $table);
    }
    binmode STDOUT, ':encoding(UTF-8)';
    print $table;
}

exit 0;

sub benchmark {
    my ($base, $data, $table) = @_;

    my $tt_file = "$base.tt";
    croak "No such file: $TT_DIR/$tt_file" if !-f "$TT_DIR/$tt_file";
    my $tx_file = "$base.tx";
    croak "No such file: $TX_DIR/$tx_file" if !-f "$TX_DIR/$tx_file";

    my $tt_data = _benchmark_one('TT', $base, \&tt_exec, $TT, $tt_file, $data);
    my $tx_data = _benchmark_one('TX', $base, \&tx_exec, $TX, $tx_file, $data);
    if ($tt_data->{out} ne $tx_data->{out}) {
        warn "$base output differs!\nTT: \Q$tt_data->{out}\E\nTX: \Q$tx_data->{out}\E\n";
    }
    $table->add($base,
        (sprintf '%.2f', $tt_data->{per_sec}),
        (sprintf '%.2f', $tx_data->{per_sec}),
        (sprintf '%.2f%%', $tx_data->{per_sec} * 100 / $tt_data->{per_sec}),
    );
}

sub _benchmark_one {
    my ($what, $base, $subref, $instance, $file, $data) = @_;

    $subref->($instance, $file, $data);    # cache things

    my $t0 = [gettimeofday];
    $subref->($instance, $file, $data) for 1..$DEFAULT_ITERATIONS;
    my $done    = tv_interval($t0);
    my $iterate = int( $DEFAULT_ITERATIONS * $DEFAULT_RUNTIME / $done );
    warn "$base: doing $iterate iterations for $what...\n";
    $t0 = [gettimeofday];
    my $out = '';
    $out = $subref->($instance, $file, $data) for 1..$iterate;
    $done = tv_interval($t0);
    warn sprintf "%s %s done %d iterations in %.5f, i.e. %.4f/s\n",
        $what, $base, $iterate, $done, $iterate/$done;
    return {
        what    => $what,
        base    => $base,
        iterate => $iterate,
        done    => $done,
        per_sec => $iterate / $done,
        out     => $out,
    };
}

sub tt_exec {
    my ($tt, $tt_file, $data) = @_;

    my $output = '';
    $tt->process($tt_file, $data, \$output)
        or die $tt->error;
    return $output;
}

sub tx_exec {
    my ($tx, $tx_file, $data) = @_;

    my $output = '';
    $output = $tx->render($tx_file, $data);
    return $output;
}
