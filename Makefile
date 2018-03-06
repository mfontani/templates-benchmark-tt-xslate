default:
	perl benchmark.pl

dumb:
	perl benchmark.pl -D

all:
	perl benchmark.pl 0.5
	perl benchmark.pl 1
	perl benchmark.pl 5
	perl benchmark.pl 10
