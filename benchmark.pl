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
use URI::XSEscape qw<>;
use Path::Tiny qw<path>;
use Cpanel::JSON::XS qw<>;
use File::Basename qw<basename>;
use Time::HiRes qw<gettimeofday tv_interval>;
use FindBin qw<>;
use Text::Table qw<>;
use Text::Diff qw<diff>;
use Dumbbench qw<>;

$|++;
binmode STDOUT, ':encoding(UTF-8)';

const my $DEFAULT_ITERATIONS => 500;
const my $DEFAULT_RUNTIME    => 1; # seconds
const my $TT_DIR             => './tt_templates';
const my $TX_DIR             => './tx_templates';
const my $TT_CACHE_DIR       => './.tt_cache';
const my $TX_CACHE_DIR       => './.tx_cache';
const my $RESULTS_DIR        => './results';
const my $RX_NUMBER          => qr!\A\d+(?:[.]\d+)?\z!xms;

mkdir $RESULTS_DIR
    if !-d $RESULTS_DIR;

# Global Options
my ($FORCE)     = grep { $_ eq '-f' }       @ARGV; @ARGV = grep { $_ ne '-f' } @ARGV;
my ($CACHE)     = grep { $_ eq '-C' }       @ARGV; @ARGV = grep { $_ ne '-C' } @ARGV;
my ($DUMBBENCH) = grep { $_ eq '-D' }       @ARGV; @ARGV = grep { $_ ne '-D' } @ARGV;
my ($LIST)      = grep { $_ eq 'list' }     @ARGV; @ARGV = grep { $_ ne 'list' } @ARGV;
my ($WIDE)      = grep { $_ eq '-w' }       @ARGV; @ARGV = grep { $_ ne '-w' } @ARGV;
my ($RUNTIME)   = grep { $_ =~ $RX_NUMBER } @ARGV; @ARGV = grep { $_ !~ $RX_NUMBER } @ARGV;
$RUNTIME //= $DEFAULT_RUNTIME;

my $JSON = Cpanel::JSON::XS->new->utf8;

my $TT = Template->new(
    UNICODE      => 1,
    INCLUDE_PATH => [ $TT_DIR ],
    FILTERS      => {
        # URI::XSEscape speeds up TT's own version
        uri => \&URI::XSEscape::uri_escape_utf8,
    },
    COMPILE_DIR  => "$FindBin::RealBin/$TT_CACHE_DIR",
    COMPILE_EXT  => '.ttc2',
);

my $TX; # to allow the functions to reference the templating system
$TX = Text::Xslate->new(
    verbose     => 1,          # warn about non-trivial stuff
    type        => 'html',
    input_layer => ':utf8',    # No need for :set bomb
    path        => [ $TX_DIR ],
    cache       => 1,          # the default cache level (check freshness every time)
    module      => [
        # Use similar variable methods to TT2
        'Text::Xslate::Bridge::TT2Like',
    ],
    function => {
        # Xslate's uri filter is a lot faster than this
        # uri => \&URI::XSEscape::uri_escape_utf8,
        runtime_include => sub {
            return Text::Xslate::mark_raw( $TX->render("$_[0]", $TX->current_vars) );
        },
    },
    cache_dir => $TX_CACHE_DIR,
);

my $TXC; # to allow the functions to reference the templating system
$TXC = Text::Xslate->new(
    verbose     => 1,          # warn about non-trivial stuff
    type        => 'html',
    input_layer => ':utf8',    # No need for :set bomb
    path        => [ $TX_DIR ],
    cache       => 2,          # use cache; do not check for freshness
    module      => [
        # Use similar variable methods to TT2
        'Text::Xslate::Bridge::TT2Like',
    ],
    function => {
        # Xslate's uri filter is a lot faster than this
        # uri => \&URI::XSEscape::uri_escape_utf8,
        runtime_include => sub {
            return Text::Xslate::mark_raw( $TX->render("$_[0]", $TX->current_vars) );
        },
    },
    cache_dir => $TX_CACHE_DIR,
);

# Always reset cache directory before each run, to ensure TXC cache => 2
# setting will not wreak havoc with updated / uncached templates; it shouldn't,
# as TX is done first, so the cache for any updated template should be already
# updated by the time TXC happens, but better safe than sorry.
if ($CACHE) {
    warn "Purging $TX_CACHE_DIR...\n";
    require File::Path;
    warn "Removed ", File::Path::rmtree($TX_CACHE_DIR), " files from TX cache.\n";
}

{
    my @cols = $WIDE ?  ('Function', 'TT done', 'TT seconds', 'TT/s', 'TX done', 'TX seconds', 'TX/s', "±TX/TT\n&num")
             :          ('Function',                          'TT/s',                          'TX/s', "±TX/TT\n&num");
    push @cols, 'TXC/s', pop @cols, "±TXC/TT\n&num", "±TXC/TX\n&num"
        if $CACHE;
    my $table       = Text::Table->new(@cols);
    my @jsons       = reverse glob './data/*.json';
    my %wants_tests = map { $_ => 1 } @ARGV;
    my @bases       = ();
    for my $file (@jsons) {
        my $base = basename($file) =~ s![.]json\z!!xmsgr;
        if ($LIST) {
            push @bases, $base;
            next;
        }
        if (scalar keys %wants_tests) {
            next if !exists $wants_tests{$base};
        }
        my $json = path($file)->slurp_utf8;
        benchmark($base, $json, $table) if !$DUMBBENCH;
        dumb_benchmark($base, $json)    if $DUMBBENCH;
    }
    if ($LIST) {
        say "@bases";
        exit 0;
    }
    if (!$DUMBBENCH) {
        say "TT:  Template Toolkit with disk cache";
        say "TX:  Text::Xslate     with disk cache and cache => 1 (default)";
        say "TXC: Text::Xslate     with disk cache and cache => 2";
        print
            $table->title,
            $table->body;
    }
}

exit 0;

sub files_for {
    my ($base) = @_;

    my $tt_file = "$base.tt";
    croak "No such file: $TT_DIR/$tt_file" if !-f "$TT_DIR/$tt_file";
    my $tx_file = "$base.tx";
    croak "No such file: $TX_DIR/$tx_file" if !-f "$TX_DIR/$tx_file";

    return ($tt_file, $tx_file);
}

sub sanity_check {
    my ($base, $tt_file, $tx_file, $json) = @_;

    my $txc_data;
    my $tt_data = _benchmark_one('TT', $base, \&tt_exec, $TT, $tt_file, $json);
    my $tx_data = _benchmark_one('TX', $base, \&tx_exec, $TX, $tx_file, $json);
    $txc_data   = _benchmark_one('TXC', $base, \&tx_exec, $TXC, $tx_file, $json)
        if $CACHE;

    if ($tt_data ne $tx_data) {
        warn "$base output differs!\nTT: \Q$tt_data\E\nTX: \Q$tx_data\E\n";
        path("./tt.out")->spew_utf8($tt_data);
        path("./tx.out")->spew_utf8($tx_data);
        warn diff(\$tt_data, \$tx_data);
        path("$RESULTS_DIR/$RUNTIME.$_.$base.json")->remove for qw<TT TX TXC>;
        exit 1;
    }
    if ($CACHE && $tx_data ne $txc_data) {
        warn "$base output differs!\nTX: \Q$tx_data\E\nTXC: \Q$txc_data\E\n";
        path("./tx.out")->spew_utf8($tx_data);
        path("./ttc.out")->spew_utf8($txc_data);
        warn diff(\$tx_data, \$txc_data);
        path("$RESULTS_DIR/$RUNTIME.$_.$base.json")->remove for qw<TT TX TXC>;
        exit 1;
    }
}

sub benchmark {
    my ($base, $json, $table) = @_;

    my ($tt_file, $tx_file) = files_for($base);
    sanity_check($base, $tt_file, $tx_file, $json);

    my $txc_data;
    my $tt_data = _benchmark_all('TT',  $base, \&tt_exec, $TT,  $tt_file, $json);
    my $tx_data = _benchmark_all('TX',  $base, \&tx_exec, $TX,  $tx_file, $json);
    $txc_data   = _benchmark_all('TXC', $base, \&tx_exec, $TXC, $tx_file, $json)
        if $CACHE;

    my @cols = ("${RUNTIME}s $base");
    push @cols, ($tt_data->{iterate}, (sprintf '%.2f', $tt_data->{done})) if $WIDE;
    push @cols, sprintf '%.2f', $tt_data->{per_sec};
    push @cols, ($tx_data->{iterate}, (sprintf '%.2f', $tx_data->{done})) if $WIDE;
    push @cols, sprintf '%.2f', $tx_data->{per_sec};
    push @cols, sprintf '%.2f', $txc_data->{per_sec} if $CACHE;
    push @cols, sprintf '%+.2f%%', $tx_data->{per_sec}  * 100 / $tt_data->{per_sec};
    push @cols, sprintf '%+.2f%%', $txc_data->{per_sec} * 100 / $tt_data->{per_sec}
        if $CACHE;
    push @cols, sprintf '%+.2f%%', $txc_data->{per_sec} * 100 / $tx_data->{per_sec}
        if $CACHE;
    $table->add(@cols);
}

sub dumb_benchmark {
    my ($base, $json) = @_;

    warn "Dumb-Benchmarking $base...\n";

    my ($tt_file, $tx_file) = files_for($base);
    sanity_check($base, $tt_file, $tx_file, $json);

    my $bench = Dumbbench->new(
        target_rel_precision => 0.002,
        initial_runs         => $DEFAULT_ITERATIONS,
    );
    $bench->add_instances(
        Dumbbench::Instance::PerlSub->new(name => 'TT', code => sub {
            tt_exec($TT, $tt_file, $json);
        }),
        Dumbbench::Instance::PerlSub->new(name => 'TX', code => sub {
            tx_exec($TX, $tx_file, $json);
        }),
    );
    $bench->run;
    $bench->report(0, { float => 1 });
}

sub _benchmark_one {
    my ($what, $base, $subref, $instance, $file, $json) = @_;

    return $subref->($instance, $file, $json);
}

sub _benchmark_all {
    my ($what, $base, $subref, $instance, $file, $json) = @_;

    my $results_file = "$RESULTS_DIR/$RUNTIME.$what.$base.json";
    if (-f $results_file && !$FORCE) {
        return $JSON->decode(path($results_file)->slurp_utf8)
    }

    my $t0 = [gettimeofday];
    $subref->($instance, $file, $json) for 1..$DEFAULT_ITERATIONS;
    my $done    = tv_interval($t0);
    my $iterate = int( $DEFAULT_ITERATIONS * $RUNTIME * 1.2 / $done );
    warn "$base: doing $iterate iterations for $what...\n" if $ENV{DEBUG};
    $t0 = [gettimeofday];
    my $out = '';
    $out = $subref->($instance, $file, $json) for 1..$iterate;
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
    warn "$what $base $results_file done $ret->{per_sec}/s...\n";
    return $ret;
}

sub tt_exec {
    my ($tt, $tt_file, $json) = @_;

    my $output = '';
    my $data   = $JSON->decode($json);
    $tt->process($tt_file, $data, \$output)
        or die $tt->error;
    return $output;
}

sub tx_exec {
    my ($tx, $tx_file, $json) = @_;

    my $output = '';
    my $data   = $JSON->decode($json);
    $output = $tx->render($tx_file, $data);
    return $output;
}
