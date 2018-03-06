default: clean-caches
	perl benchmark.pl

dumb: clean-caches
	perl benchmark.pl -D

all: benchmark-0.5 benchmark-1 benchmark-5 benchmark-10

benchmark-0.5: clean-caches
	perl benchmark.pl 0.5
benchmark-1: clean-caches
	perl benchmark.pl 1
benchmark-5: clean-caches
	perl benchmark.pl 5
benchmark-10: clean-caches
	perl benchmark.pl 10

benchmark-0.5-f: clean-caches
	perl benchmark.pl -f 0.5
benchmark-1-f: clean-caches
	perl benchmark.pl -f 1
benchmark-5-f: clean-caches
	perl benchmark.pl -f 5
benchmark-10-f: clean-caches
	perl benchmark.pl -f 10

clean-caches:
	rm -rf ./.tt_cache/* ./.tx_cache/* tt.out tx.out
