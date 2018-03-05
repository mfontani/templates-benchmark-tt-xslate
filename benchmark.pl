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
use Text::Diff qw<diff>;

$|++;

const my $DEFAULT_ITERATIONS => 50;
const my $DEFAULT_RUNTIME    => 1; # seconds
const my $TT_DIR             => './tt_templates/';
const my $TX_DIR             => './tx_templates/';
const my $RESULTS_DIR        => './results/';

mkdir $RESULTS_DIR
    if !-d $RESULTS_DIR;

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
    my $runtime = shift @ARGV || $DEFAULT_RUNTIME;
    my $table   = Text::Table->new('Function', 'TT/s', 'TX/s', '+/-');
    my @jsons   = reverse glob './data/*.json';
    for my $file (@jsons) {
        my $data    = $JSON->decode(path($file)->slurp_utf8);
        my $base    = basename($file) =~ s![.]json\z!!xmsgr;
        benchmark($base, $data, $table, $runtime);
    }
    binmode STDOUT, ':encoding(UTF-8)';
    print $table;
}

exit 0;

sub benchmark {
    my ($base, $data, $table, $runtime) = @_;

    print "Benchmarking $base...";

    my $tt_file = "$base.tt";
    croak "No such file: $TT_DIR/$tt_file" if !-f "$TT_DIR/$tt_file";
    my $tx_file = "$base.tx";
    croak "No such file: $TX_DIR/$tx_file" if !-f "$TX_DIR/$tx_file";

    my $tt_data = _benchmark_one('TT', $base, \&tt_exec, $TT, $tt_file, $data, $runtime);
    my $tx_data = _benchmark_one('TX', $base, \&tx_exec, $TX, $tx_file, $data, $runtime);
    if ($tt_data->{out} ne $tx_data->{out}) {
        warn "$base output differs!\nTT: \Q$tt_data->{out}\E\nTX: \Q$tx_data->{out}\E\n";
        path("./tt.out")->spew_utf8($tt_data->{out});
        path("./tx.out")->spew_utf8($tx_data->{out});
        warn diff(\$tt_data->{out}, \$tx_data->{out});
    }
    $table->add("${runtime}s $base",
        (sprintf '%.2f', $tt_data->{per_sec}),
        (sprintf '%.2f', $tx_data->{per_sec}),
        (sprintf '%.2f%%', $tx_data->{per_sec} * 100 / $tt_data->{per_sec}),
    );
    print "done\n";
}

sub _benchmark_one {
    my ($what, $base, $subref, $instance, $file, $data, $runtime) = @_;

    my $results_file = "$RESULTS_DIR/$runtime.$what.$base.json";
    if (-f $results_file) {
        print " $results_file cached...";
        return $JSON->decode(path($results_file)->slurp_utf8)
    }

    $subref->($instance, $file, $data);    # cache things

    my $t0 = [gettimeofday];
    $subref->($instance, $file, $data) for 1..$DEFAULT_ITERATIONS;
    my $done    = tv_interval($t0);
    my $iterate = int( $DEFAULT_ITERATIONS * $runtime / $done );
    warn "$base: doing $iterate iterations for $what...\n" if $ENV{DEBUG};
    $t0 = [gettimeofday];
    my $out = '';
    $out = $subref->($instance, $file, $data) for 1..$iterate;
    $done = tv_interval($t0);
    warn sprintf "%s %s done %d iterations in %.5f, i.e. %.4f/s\n",
        $what, $base, $iterate, $done, $iterate/$done
        if $ENV{DEBUG};
    my $ret = {
        what    => $what,
        base    => $base,
        iterate => $iterate,
        done    => $done,
        per_sec => $iterate / $done,
        out     => $out,
    };
    path($results_file)->spew_utf8($JSON->encode($ret));
    print " $results_file done...";
    return $ret;
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
