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
use URI::XSEscape qw<>;
use Path::Tiny qw<path>;
use Cpanel::JSON::XS qw<>;
use File::Basename qw<basename>;
use Time::HiRes qw<gettimeofday tv_interval>;
use FindBin qw<>;
use Text::Table qw<>;
use Text::Diff qw<diff>;
use File::Path qw<>;
use Dumbbench qw<>;

$|++;
binmode STDOUT, ':encoding(UTF-8)';

const my $CACHE_ITERATIONS   => 100;
const my $DEFAULT_ITERATIONS => 500;
const my $DEFAULT_RUNTIME    => 1; # seconds
const my $TT_DIR             => './tt_templates';
const my $TX_DIR             => './tx_templates';
const my $TT_CACHE_DIR       => './.tt_cache';
const my $TT_SHM_CACHE_DIR   => '/dev/shm/tt_cache';
const my $TX_CACHE_DIR       => './.tx_cache';
const my $TXC_CACHE_DIR      => './.txc_cache';
const my $TX_SHM_CACHE_DIR   => '/dev/shm/tx_cache';
const my $RESULTS_DIR        => './results';
const my $RX_NUMBER          => qr!\A\d+(?:[.]\d+)?\z!xms;
const my $STAT_MTIME_FIELD   => 9;   # perldoc -f stat

mkdir $RESULTS_DIR
    if !-d $RESULTS_DIR;

if (scalar grep { $_ eq '--help' || $_ eq '-h' || $_ eq '-?' } @ARGV) {
    say <<"EOF";
Usage: benchmark.pl [OPTIONS] [list] [RUNTIME]

Benchmarks time taken to output TT (Template Toolkit) vs XS (Xslate) templates,
each given the same data in the stash, and each checked for equivalence of
output.

Performs a benchmark run for about RUNTIME (default $DEFAULT_RUNTIME) seconds,
but first performing $CACHE_ITERATIONS iterations to find how many actual
iterations to perform, but see -D.

By default re-uses previous runs' results, but see -f.

You can also use the "list" parameter, if you'd like to see a list of the
basenames of the tests will be performed.  Each basename will have a
corresponding file in the data/, tt_templates/ and tx_templates/ directories.

Options:

    -f      Force.
            Clean up the result caches before running each benchmark.
    -D      Dumbbench.
            Instead of performing iterations up to RUNTIME seconds, use
            Dumbbench with a default of $DEFAULT_ITERATIONS iterations instead.
            Does not output a report, and does not cache the results.
    -A      ANSI colors and underlines.
            For each of "/s", "% improvement" and "x times improvement" columns,
            show the highest value by row in green, lowest in red and second
            lowest in yellow.
            For each column, also show the highest value as double underline,
            and lowest as single underline.
    -w      Wide.
            Also show how many iterations were done, and in how many seconds.
            Useless with -D.
    -C      Also benchmark "TXC".
            Performs an additional set of benchmarks using Text::Xslate
            with "cache => 2" (cleans up the cache directory before the run).
            Also works with -D.
    -S      Also benchmark "SHM" variations.
            That is, benchmark TT and TX where the cache directory is kept
            on a subdirectory of /dev/shm.

EOF
    exit 0;
}

# Global Options
my ($LIST)      = grep { $_ eq 'list' }     @ARGV; @ARGV = grep { $_ ne 'list' } @ARGV;
my ($FORCE)     = grep { $_ eq '-f' }       @ARGV; @ARGV = grep { $_ ne '-f' } @ARGV;
my ($CACHE)     = grep { $_ eq '-C' }       @ARGV; @ARGV = grep { $_ ne '-C' } @ARGV;
my ($DUMBBENCH) = grep { $_ eq '-D' }       @ARGV; @ARGV = grep { $_ ne '-D' } @ARGV;
my ($WIDE)      = grep { $_ eq '-w' }       @ARGV; @ARGV = grep { $_ ne '-w' } @ARGV;
my ($USE_SHM)   = grep { $_ eq '-S' }       @ARGV; @ARGV = grep { $_ ne '-S' } @ARGV;
my ($USE_ANSI)  = grep { $_ eq '-A' }       @ARGV; @ARGV = grep { $_ ne '-A' } @ARGV;
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
my $TTSHM;
$TTSHM = Template->new(
    UNICODE      => 1,
    INCLUDE_PATH => [ $TT_DIR ],
    FILTERS      => {
        # URI::XSEscape speeds up TT's own version
        uri => \&URI::XSEscape::uri_escape_utf8,
    },
    COMPILE_DIR  => $TT_SHM_CACHE_DIR,
    COMPILE_EXT  => '.ttc2',
) if $USE_SHM && -d '/dev/shm';

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
            my ($template, $vars) = @_;
            $vars = {
                %{ $TX->current_vars },
                %{ $vars // {} },
            };
            return Text::Xslate::mark_raw($TX->render($template, $vars));
        },
    },
    cache_dir => $TX_CACHE_DIR,
);

my $TXSHM;
$TXSHM = Text::Xslate->new(
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
            my ($template, $vars) = @_;
            $vars = {
                %{ $TXSHM->current_vars },
                %{ $vars // {} },
            };
            return Text::Xslate::mark_raw($TXSHM->render($template, $vars));
        },
    },
    cache_dir => $TX_SHM_CACHE_DIR,
) if $USE_SHM && -d '/dev/shm';


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
            my ($template, $vars) = @_;
            $vars = {
                %{ $TXC->current_vars },
                %{ $vars // {} },
            };
            return Text::Xslate::mark_raw($TXC->render($template, $vars));
        },
    },
    cache_dir => $TXC_CACHE_DIR,
);

{
    # Always reset cache directories before each run
    require File::Path;
    File::Path::rmtree($_) for (
        $TT_CACHE_DIR, $TT_SHM_CACHE_DIR,
        $TX_CACHE_DIR, $TX_SHM_CACHE_DIR,
        $TXC_CACHE_DIR,
    );

    my @cols = ('Function');
    push @cols, ('TT done', 'TT seconds') if $WIDE;
    push @cols, 'TT/s';
    push @cols, ('TTSHM done', 'TTSHM seconds') if $TTSHM && $WIDE;
    push @cols, 'TTSHM/s' if $TTSHM;
    push @cols, ('TX done', 'TX seconds') if $WIDE;
    push @cols, 'TX/s';
    push @cols, ('TXSHM done', 'TXSHM seconds') if $TXSHM && $WIDE;
    push @cols, 'TXSHM/s' if $TXSHM;
    push @cols, 'TXC/s'   if $CACHE;
    push @cols, ("±TX/TT\n&num", "±TX/TTx\n&num");
    push @cols, ("±TTSHM/TT\n&num", "±TTSHM/TTx\n&num") if $TTSHM;
    push @cols, ("±TXSHM/TT\n&num", "±TXSHM/TTx\n&num") if $TXSHM;
    push @cols, ("±TXSHM/TX\n&num", "±TXSHM/TXx\n&num") if $TXSHM;
    push @cols, ("±TXC/TT\n&num",   "±TXC/TTx\n&num")   if $CACHE;
    push @cols, ("±TXC/TX\n&num",   "±TXC/TXx\n&num")   if $CACHE;
    my $table       = Text::Table->new(@cols);
    my @jsons       = reverse glob './data/*.json';
    my %wants_tests = map { $_ => 1 } @ARGV;
    my @bases       = ();
    my @rows        = ();
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
        push @rows, benchmark($base, $json) if !$DUMBBENCH;
        dumb_benchmark($base, $json)        if  $DUMBBENCH;
    }
    exit 0 if $DUMBBENCH;
    if ($LIST) {
        say "@bases";
        exit 0;
    }
    @rows = ansify_rows(\@cols, \@rows) if $USE_ANSI;
    # say "TT:  Template Toolkit with disk cache";
    # say "TX:  Text::Xslate     with disk cache and cache => 1 (default)";
    # say "TXC: Text::Xslate     with disk cache and cache => 2"
    #     if $CACHE;
    $table->add(@$_) for @rows;
    print
        $table->title,
        $table->body;
}

exit 0;

sub ansify_rows {
    my ($c, $r) = @_;

    my @cols = @$c;
    my @rows = @$r;

    my $sort_just_the_number = sub {
        my ($aa, $bb) = @_;
        for ($aa, $bb) {
            s!\e\[[0-9]*m!!xmsg; # rm ansi codes
            s!x\z!!xms;          # trailing x
            s!\A[+-]? !!xms;
            s!  [%]?\z!!xms;
        }
        $aa <=> $bb;
    };

    # Find highest /s for each row, and mark it as such
    for my $i (0..$#rows) {
        my @sorted = reverse
                     sort { $sort_just_the_number->($rows[$i][$a], $rows[$i][$b]) }
                     grep { $_ && $cols[$_] =~ m!/s\z!xms }
                     1..$#cols;
        $rows[$i][$sorted[ 0]] = "\e[32m$rows[$i][$sorted[ 0]]\e[0m" if exists $sorted[0];
        $rows[$i][$sorted[-1]] = "\e[31m$rows[$i][$sorted[-1]]\e[0m" if exists $sorted[-1];
        $rows[$i][$sorted[ 1]] = "\e[33m$rows[$i][$sorted[ 1]]\e[0m" if exists $sorted[1];
    }

    # Find highest x$ for each row, and mark it as such
    for my $i (0..$#rows) {
        my @sorted = reverse
                     sort { $sort_just_the_number->($rows[$i][$a], $rows[$i][$b]) }
                     grep { $_ && $cols[$_] =~ m!x\s!xms }
                     1..$#cols;
        $rows[$i][$sorted[ 0]] = "\e[32m$rows[$i][$sorted[ 0]]\e[0m" if exists $sorted[0];
        $rows[$i][$sorted[-1]] = "\e[31m$rows[$i][$sorted[-1]]\e[0m" if exists $sorted[-1];
        $rows[$i][$sorted[ 1]] = "\e[33m$rows[$i][$sorted[ 1]]\e[0m" if exists $sorted[1];
    }

    # Find highest ± for each row and mark it
    for my $i (0..$#rows) {
        my @sorted = reverse
                     sort { $sort_just_the_number->($rows[$i][$a], $rows[$i][$b]) }
                     grep { $_ && $cols[$_] =~ m!±!xms }
                     1..$#cols;
        $rows[$i][$sorted[ 0]] = "\e[32m$rows[$i][$sorted[ 0]]\e[0m" if exists $sorted[0];
        $rows[$i][$sorted[-1]] = "\e[31m$rows[$i][$sorted[-1]]\e[0m" if exists $sorted[-1];
        $rows[$i][$sorted[ 1]] = "\e[33m$rows[$i][$sorted[ 1]]\e[0m" if exists $sorted[1];
    }

    # Mark highest & lowest number by COLUMN as underline
    for my $j (1..$#cols) {
        my @highest = reverse
                      sort { $sort_just_the_number->($rows[$a][$j], $rows[$b][$j]) }
                      0..$#rows;
        $rows[$highest[ 0]][$j] = "\e[21m$rows[$highest[ 0]][$j]\e[0m" if exists $highest[0];
        next if scalar @highest <= 1;
        $rows[$highest[-1]][$j] = "\e[4m$rows[$highest[-1]][$j]\e[0m"  if exists $highest[-1];
    }

    return @rows;
}

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

    _benchmark_one('TTSHM', $base, \&tt_exec, $TTSHM, $tt_file, $json) if $TTSHM;
    _benchmark_one('TXSHM', $base, \&tx_exec, $TXSHM, $tx_file, $json) if $TXSHM;

    if ($tt_data ne $tx_data) {
        warn "$base output differs!\nTT: \Q$tt_data\E\nTX: \Q$tx_data\E\n";
        path("./tt.out")->spew($tt_data);
        path("./tx.out")->spew($tx_data);
        warn diff(\$tt_data, \$tx_data);
        path("$RESULTS_DIR/$RUNTIME.$_.$base.json")->remove for qw<TT TX TXC>;
        exit 1;
    }
    if ($CACHE && $tx_data ne $txc_data) {
        warn "$base output differs!\nTX: \Q$tx_data\E\nTXC: \Q$txc_data\E\n";
        path("./tx.out")->spew($tx_data);
        path("./ttc.out")->spew($txc_data);
        warn diff(\$tx_data, \$txc_data);
        path("$RESULTS_DIR/$RUNTIME.$_.$base.json")->remove for qw<TT TX TXC>;
        exit 1;
    }
}

sub _highest_width_for_tests {
    state $highest = do {
        my @jsons    = reverse glob './data/*.json';
        my $_highest = 0;
        for my $file (@jsons) {
            my $base = basename($file) =~ s!\A./data/(.*)[.]json\z!!xmsgr;
            $_highest = length $base
                if length $base > $_highest;
        }
        $_highest;
    };
    return $highest;
}

sub benchmark {
    my ($base, $json) = @_;

    my ($tt_file, $tx_file) = files_for($base);
    sanity_check($base, $tt_file, $tx_file, $json);

    my ($ttshm_data, $txshm_data, $txc_data);
    my $tt_data = _benchmark_all('TT',    $base, \&tt_exec, $TT,    $tt_file, $json);
    my $tx_data = _benchmark_all('TX',    $base, \&tx_exec, $TX,    $tx_file, $json);
    $ttshm_data = _benchmark_all('TTSHM', $base, \&tt_exec, $TTSHM, $tt_file, $json)
        if $TTSHM;
    $txshm_data = _benchmark_all('TXSHM', $base, \&tx_exec, $TXSHM, $tx_file, $json)
        if $TXSHM;
    $txc_data   = _benchmark_all('TXC',   $base, \&tx_exec, $TXC,   $tx_file, $json)
        if $CACHE;

    my $w = _highest_width_for_tests();
    my @cols = (sprintf "%-4s %-${w}s", "${RUNTIME}s", $base);
    push @cols, ($tt_data->{iterate}, (sprintf '%.2f', $tt_data->{done})) if $WIDE;
    push @cols, sprintf '%.2f', $tt_data->{per_sec};
    push @cols, ($ttshm_data->{iterate}, (sprintf '%.2f', $ttshm_data->{done})) if $TTSHM && $WIDE;
    push @cols, sprintf '%.2f', $ttshm_data->{per_sec} if $TTSHM;
    push @cols, ($tx_data->{iterate}, (sprintf '%.2f', $tx_data->{done})) if $WIDE;
    push @cols, sprintf '%.2f', $tx_data->{per_sec};
    push @cols, ($txshm_data->{iterate}, (sprintf '%.2f', $txshm_data->{done})) if $TXSHM && $WIDE;
    push @cols, sprintf '%.2f', $txshm_data->{per_sec} if $TXSHM;
    push @cols, sprintf '%.2f', $txc_data->{per_sec} if $CACHE;
    push @cols, sprintf '%+.2f%%', - 100 + $tx_data->{per_sec}    * 100 / $tt_data->{per_sec};
    push @cols, sprintf '%+.2fx',  - 1   + $tx_data->{per_sec}          / $tt_data->{per_sec};
    push @cols, sprintf '%+.2f%%', - 100 + $ttshm_data->{per_sec} * 100 / $tt_data->{per_sec} if $TTSHM;
    push @cols, sprintf '%+.2fx',  - 1   + $ttshm_data->{per_sec}       / $tt_data->{per_sec} if $TTSHM;
    push @cols, sprintf '%+.2f%%', - 100 + $txshm_data->{per_sec} * 100 / $tt_data->{per_sec} if $TXSHM;
    push @cols, sprintf '%+.2fx',  - 1   + $txshm_data->{per_sec}       / $tt_data->{per_sec} if $TXSHM;
    push @cols, sprintf '%+.2f%%', - 100 + $txshm_data->{per_sec} * 100 / $tx_data->{per_sec} if $TXSHM;
    push @cols, sprintf '%+.2fx',  - 1   + $txshm_data->{per_sec}       / $tx_data->{per_sec} if $TXSHM;
    push @cols, sprintf '%+.2f%%', - 100 + $txc_data->{per_sec}   * 100 / $tt_data->{per_sec} if $CACHE;
    push @cols, sprintf '%+.2fx',  - 1   + $txc_data->{per_sec}         / $tt_data->{per_sec} if $CACHE;
    push @cols, sprintf '%+.2f%%', - 100 + $txc_data->{per_sec}   * 100 / $tx_data->{per_sec} if $CACHE;
    push @cols, sprintf '%+.2fx',  - 1   + $txc_data->{per_sec}         / $tx_data->{per_sec} if $CACHE;
    return [ @cols ];
}

sub dumb_benchmark {
    my ($base, $json) = @_;

    warn "Dumb-Benchmarking $base...\n";

    my ($tt_file, $tx_file) = files_for($base);
    sanity_check($base, $tt_file, $tx_file, $json);

    my $bench = Dumbbench->new(
        target_rel_precision => 0.005,
        initial_runs         => $DEFAULT_ITERATIONS,
    );
    $bench->add_instances(
        Dumbbench::Instance::PerlSub->new(name => 'TT   ', code => sub {
            tt_exec($TT, $tt_file, $json);
        }),
        Dumbbench::Instance::PerlSub->new(name => 'TX   ', code => sub {
            tx_exec($TX, $tx_file, $json);
        }),
    );
    $bench->add_instances(
        Dumbbench::Instance::PerlSub->new(name => 'TXC  ', code => sub {
            tx_exec($TXC, $tx_file, $json);
        }),
    ) if $CACHE;
    $bench->add_instances(
        Dumbbench::Instance::PerlSub->new(name => 'TTSHM', code => sub {
            tt_exec($TTSHM, $tt_file, $json);
        }),
    ) if $TTSHM;
    $bench->add_instances(
        Dumbbench::Instance::PerlSub->new(name => 'TXSHM', code => sub {
            tx_exec($TXSHM, $tx_file, $json);
        }),
    ) if $TXSHM;
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
        # Ensure the mtime of the $results_file is consistent with (i.e. is
        # later than) the maximum mtime of the "input" (tt or tx) files
        my $result_mtime = (stat $results_file)[$STAT_MTIME_FIELD];
        my $max_mtime    = 0;
        for my $file ((glob "$TT_DIR/$base*.tt"), (glob "$TX_DIR/$base*.tx")) {
            my $file_mtime = (stat $file)[$STAT_MTIME_FIELD];
            $max_mtime = $file_mtime
                if $file_mtime > $max_mtime;
        }
        return $JSON->decode(path($results_file)->slurp)
            if $result_mtime > $max_mtime;
    }

    my $t0 = [gettimeofday];
    $subref->($instance, $file, $json) for 1..$CACHE_ITERATIONS;
    my $done    = tv_interval($t0);
    my $iterate = int( $CACHE_ITERATIONS * $RUNTIME * 1.2 / $done );
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
    path($results_file)->spew($JSON->encode($ret));
    # warn "$what $base $results_file done $ret->{per_sec}/s...\n";
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
