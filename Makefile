default: clean-caches
	carton exec perl benchmark.pl -C

dumb: clean-caches
	carton exec perl benchmark.pl -D

all: benchmark-0.5 benchmark-1 benchmark-5 benchmark-10

benchmark-0.5: clean-caches
	carton exec perl benchmark.pl 0.5 -C
benchmark-1: clean-caches
	carton exec perl benchmark.pl 1 -C
benchmark-5: clean-caches
	carton exec perl benchmark.pl 5 -C
benchmark-10: clean-caches
	carton exec perl benchmark.pl 10 -C

benchmark-0.5-f: clean-caches
	carton exec perl benchmark.pl -f 0.5 -C
benchmark-1-f: clean-caches
	carton exec perl benchmark.pl -f 1 -C
benchmark-5-f: clean-caches
	carton exec perl benchmark.pl -f 5 -C
benchmark-10-f: clean-caches
	carton exec perl benchmark.pl -f 10 -C

clean-caches:
	rm -rf ./.tt_cache/* ./.tx_cache/* tt.out tx.out
