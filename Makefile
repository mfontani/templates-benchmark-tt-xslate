default:
	perl benchmark.pl

dumb:
	perl benchmark.pl -D

all: benchmark-0.5 benchmark-1 benchmark-5 benchmark-10

benchmark-0.5:
	perl benchmark.pl 0.5
benchmark-1:
	perl benchmark.pl 1
benchmark-5:
	perl benchmark.pl 5
benchmark-10:
	perl benchmark.pl 10
