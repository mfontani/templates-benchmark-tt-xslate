# Allow running "make report 200_full_homepage" to restrict the report to just
# one specific test.
# See also:
# https://stackoverflow.com/questions/2214575/passing-arguments-to-make-run/14061796#14061796
ifeq (report,$(firstword $(MAKECMDGOALS)))
  # use the rest as arguments
  ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  # ...and turn them into do-nothing targets
  $(eval $(ARGS):;@:)
endif
ifeq (report-w,$(firstword $(MAKECMDGOALS)))
  # use the rest as arguments
  ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  # ...and turn them into do-nothing targets
  $(eval $(ARGS):;@:)
endif

# Data files are in data/%.json
data_files := $(wildcard data/*)

# The actual "tests" match data/%.json, and we just want the % in the middle.
tests := $(patsubst data/%.json,%, $(data_files))

# The output goes in results/DURATION.OUTPUT_TYPE.TEST_NAME.json
# These are the "OUTPUT_TYPE":
output_types := TT TX

# 05: Test each for a max of 0.5 seconds
results_files_05 := $(foreach output_type,$(output_types),$(foreach test,$(tests),results/0.5.$(output_type).$(test).json))
results_05_pat=$(foreach output_type,$(output_types),results/0.5.$(output_type).%.json)

# 1: Test each for a max of 1 seconds
results_files_1 := $(foreach output_type,$(output_types),$(foreach test,$(tests),results/1.$(output_type).$(test).json))
results_1_pat=$(foreach output_type,$(output_types),results/1.$(output_type).%.json)

# 5: Test each for a max of 5 seconds
results_files_5 := $(foreach output_type,$(output_types),$(foreach test,$(tests),results/5.$(output_type).$(test).json))
results_5_pat=$(foreach output_type,$(output_types),results/5.$(output_type).%.json)

all: report
	carton exec perl -MTemplate -MText::Xslate -E'say "TT $$Template::VERSION TX $$Text::Xslate::VERSION"'

report: benchmark-0.5 benchmark-1
report-w: benchmark-0.5w benchmark-1w
report-wa: benchmark-0.5wa benchmark-1wa

clean:
	rm -f results/* *.out

.PHONY: dumb
dumb:
	carton exec perl benchmark.pl -D

# Force run specific tests for a specific time..
tests_05 := $(foreach test,$(tests),05_$(test))
$(tests_05):
	carton exec perl benchmark.pl -f 0.5 -w $(patsubst 05_%,%,$@)

tests_1 := $(foreach test,$(tests),1_$(test))
$(tests_1):
	carton exec perl benchmark.pl -f 1 -w $(patsubst 1_%,%,$@)

tests_5 := $(foreach test,$(tests),5_$(test))
$(tests_5):
	carton exec perl benchmark.pl -f 5 -w $(patsubst 5_%,%,$@)

# ... or by default
$(tests):
	carton exec perl benchmark.pl -f -w $@

.SECONDEXPANSION:
$(results_05_pat): data/%.json tt_templates/%.tt tx_templates/%.tx $$(wildcard tt_templates/%_*.tt) $$(wildcard tx_templates/%_*.tx)
	carton exec perl benchmark.pl 0.5 -w $(patsubst TX.%,%,$(patsubst TT.%,%,$(patsubst TXC.%,%,$(patsubst TXSHM.%,%,$(patsubst TTSHM.%,%,$(patsubst results/0.5.%.json,%, $@))))))

.SECONDEXPANSION:
$(results_1_pat): data/%.json tt_templates/%.tt tx_templates/%.tx $$(wildcard tt_templates/%_*.tt) $$(wildcard tx_templates/%_*.tx)
	carton exec perl benchmark.pl 1 -w $(patsubst TX.%,%,$(patsubst TT.%,%,$(patsubst TXC.%,%,$(patsubst TXSHM.%,%,$(patsubst TTSHM.%,%,$(patsubst results/1.%.json,%, $@))))))

.SECONDEXPANSION:
$(results_5_pat): data/%.json tt_templates/%.tt tx_templates/%.tx $$(wildcard tt_templates/%_*.tt) $$(wildcard tx_templates/%_*.tx)
	carton exec perl benchmark.pl 5 -w $(patsubst TX.%,%,$(patsubst TT.%,%,$(patsubst TXC.%,%,$(patsubst TXSHM.%,%,$(patsubst TTSHM.%,%,$(patsubst results/5.%.json,%, $@))))))

.PHONY: benchmark-0.5
benchmark-0.5: $(results_files_05)
	carton exec perl benchmark.pl 0.5 $(ARGS)

.PHONY: benchmark-0.5w
benchmark-0.5w: $(results_files_05)
	carton exec perl benchmark.pl 0.5 -w $(ARGS)

.PHONY: benchmark-0.5wa
benchmark-0.5wa: $(results_files_05)
	carton exec perl benchmark.pl 0.5 -w -A $(ARGS)

.PHONY: benchmark-1
benchmark-1: $(results_files_1)
	carton exec perl benchmark.pl 1 $(ARGS)

.PHONY: benchmark-1w
benchmark-1w: $(results_files_1)
	carton exec perl benchmark.pl 1 -w $(ARGS)

.PHONY: benchmark-1wa
benchmark-1wa: $(results_files_1)
	carton exec perl benchmark.pl 1 -w -A $(ARGS)

.PHONY: benchmark-5
benchmark-5: $(results_files_5)
	carton exec perl benchmark.pl 5 $(ARGS)

.PHONY: benchmark-5w
benchmark-5w: $(results_files_5)
	carton exec perl benchmark.pl 5 -w $(ARGS)

.PHONY: benchmark-5wa
benchmark-5wa: $(results_files_5)
	carton exec perl benchmark.pl 5 -w -A $(ARGS)
