*==============================================================================
* Tests and speed benchmark for cem_peede_felder
*==============================================================================
*
* cem_peede_felder computes the same matching indicator and weights as the
* -cem- package (Blackwell et al. 2009; Iacus, King & Porro 2012), but only
* those two outputs and with a sort-based algorithm. This file shows that
*
*   Part 1  both commands give IDENTICAL results, observation by observation,
*           in a range of simulated datasets (easy and hard cases),
*   Part 2  invalid input stops with an informative error,
*   Part 3  cem_peede_felder is much faster, increasingly so for large N.
*
* How to run: the working directory must be the folder of this file
* (examples_speedtest). Double-clicking the file in the file explorer usually
* starts Stata there; otherwise run  cd "<path>/CEM_Matching/examples_speedtest"
*
* Files used:
*   ../cem_peede_felder_program.do  defines the command cem_peede_felder
*   cem_make_testdata.do            defines the test data generator make_testdata
*
* Output written to the folder of this file:
*   cem_peede_felder_tests.log    log of this run
*   cem_benchmark_results.csv     timings from Part 3
*   cem_benchmark.png             graph of the timings from Part 3
*
* Requirements: Stata 16 or newer (frames), -cem- (ssc install cem)
* Runtime: a few minutes with the default settings in Part 3, almost all of
*          it spent in -cem-.
*==============================================================================

version 16
clear all
set more off
set linesize 120    // wide enough for the result tables

* Set working directory.
global cem_dir "`c(pwd)'"
capture confirm file "cem_make_testdata.do"
local rc1 = _rc
capture confirm file "../cem_peede_felder_program.do"
if `rc1' | _rc {
	di as error "Current directory: $cem_dir"
	di as error "This is not the folder examples_speedtest. Change to it first, e.g."
	di as error `"  cd "<path>/CEM_Matching/examples_speedtest""'
	exit 601
}

capture log close
log using "cem_peede_felder_tests.log", replace text

capture which cem
if _rc {
	di as error "The -cem- package is required: ssc install cem"
	exit 111
}

do "../cem_peede_felder_program.do"
do "cem_make_testdata.do"

di as text "Stata " c(stata_version) ", " c(processors) " processor(s) in use, " c(current_date)


*==============================================================================
* Part 1: Correctness - compare with -cem- in different datasets
*==============================================================================
*
* For each scenario the helper program compare_with_cem
*   1. generates a dataset with make_testdata (variables betnr, year, treat,
*      x1 ... xK; see cem_make_testdata.do for all options),
*   2. runs cem_peede_felder,
*   3. runs -cem- on the matching year only. "(#0)" tells -cem- not to
*      coarsen any variable, so both commands match exactly on x1 ... xK.
*      "noimbal" skips the imbalance statistics, which cem_peede_felder does not generate.
*   4. compares the results and stops with an error if anything differs:
*        diff_match   obs. in the matching year where matched_cem != cem_matched
*        diff_weight  obs. in the matching year where the weights differ (> 1e-6)
*        diff_panel   obs. in ANY year whose values differ from those of the
*                     same unit (betnr) in the matching year. cem_peede_felder
*                     copies its results to all years of a unit; -cem- only
*                     fills the matching year.
*   All three counts must be 0.
*------------------------------------------------------------------------------

* Define helper program to run each individual scenario and compare results with -cem-
cap program drop compare_with_cem
program define compare_with_cem
	syntax , label(string) year(integer) [*]

	// 1. data
	make_testdata, `options' clear
	local match_vars `r(match_vars)'
	local cem_vars   `r(cem_vars)'

	// 2. our command
	cem_peede_felder `match_vars', treat_indicator(treat) id(betnr) timevar(year) year(`year')

	// 3. original command, matching year only, no coarsening (coarsend varibles passed to programm as "(#0)")
	quietly cem `cem_vars' if year == `year', treatment(treat) noimbal

	// 4. compare
	quietly {
		count if year == `year'
		local n_obs = r(N)
		count if year == `year' & matched_cem == 1
		local n_matched = r(N)

		count if year == `year' & matched_cem != cem_matched
		local diff_match = r(N)
		count if year == `year' & !(abs(weight_cem - cem_weights) < 1e-6)
		local diff_weight = r(N)

		tempvar cem_m cem_w
		bysort betnr: egen `cem_m' = max(cond(year == `year', cem_matched, .))
		bysort betnr: egen double `cem_w' = max(cond(year == `year', cem_weights, .))
		count if matched_cem != `cem_m' | !(abs(weight_cem - `cem_w') < 1e-6)
		local diff_panel = r(N)
	}

	frame post results ("`label'") (`n_obs') (`n_matched') (`diff_match') (`diff_weight') (`diff_panel')

	di as text "{bf:`label'}: " as result `n_matched' as text " of " as result `n_obs' ///
		as text " matched; differences (match / weight / panel): " ///
		as result "`diff_match' / `diff_weight' / `diff_panel'"

	if `diff_match' + `diff_weight' + `diff_panel' > 0 {
		di as error "Results differ from -cem- in scenario: `label'"
		exit 9
	}
end

frame create results str40 scenario long(n_obs n_matched diff_match diff_weight diff_panel)

* Each line is one scenario. Unless stated otherwise: 6 matching variables
* with 4 equally likely categories each, 30% treated, 2 years, no missings.

* Baseline
compare_with_cem, label("Baseline")                         year(1) n(10000) seed(1)

* Many possible cells (6^8 = 1.7 million) -> most strata have no match
compare_with_cem, label("Many strata, few matches")         year(1) n(5000) nvars(8) ncats(6) seed(2)

* Very few cells (3^2 = 9) -> almost every observation is matched
compare_with_cem, label("Few strata, almost all matched")   year(1) n(5000) nvars(2) ncats(3) seed(3)

* Low categories much more likely -> very unequal stratum sizes and weights
compare_with_cem, label("Unequal stratum sizes")            year(1) n(10000) skew(3) seed(4)

* Treatment share close to 0 and close to 1
compare_with_cem, label("Few treated (2%)")                 year(1) n(10000) treatshare(0.02) seed(5)
compare_with_cem, label("Many treated (95%)")               year(1) n(10000) treatshare(0.95) seed(6)

* 20% missing per variable; both commands treat missing as its own category
compare_with_cem, label("20% missing values")               year(1) n(10000) missshare(0.2) seed(7)

* Variables with different numbers of categories
compare_with_cem, label("Mixed category counts")            year(1) n(10000) nvars(4) ncats(2 3 10 50) seed(8)

* Real panel: 4 years, matching variables change over time, matching in
* year 2, non-consecutive ids, rows in random order
compare_with_cem, label("Panel, changing covariates")       year(2) n(10000) nyears(4) panelchange(0.3) idscatter seed(9)

* Very small dataset
compare_with_cem, label("Tiny dataset (N = 20)")            year(1) n(20) nvars(2) ncats(2) seed(10)

di _n as text "{bf:Part 1 summary} (all differences must be 0):"
frame results: list, noobs sep(0) abbreviate(12)


*==============================================================================
* Part 2: Input checks - invalid input must stop with error 459
*==============================================================================
*
* rcof "command" == 459   runs the command and checks that it fails with
*                         return code 459 (and stops this file otherwise).
*------------------------------------------------------------------------------

local call cem_peede_felder x1 x2, treat_indicator(treat) id(betnr) timevar(year) year(1)

* (a) Treatment with a third value in the matching year
make_testdata, n(100) seed(11) clear
replace treat = 2 if betnr == 1 & year == 1
rcof "noisily `call'" == 459

* (b) Missing treatment in the matching year
make_testdata, n(100) seed(11) clear
replace treat = . if betnr == 1 & year == 1
rcof "noisily `call'" == 459

* (c) Unit id not unique in the matching year
make_testdata, n(100) seed(11) clear
replace betnr = 1 if betnr == 2
rcof "noisily `call'" == 459

* (d) Missing unit id in the matching year
make_testdata, n(100) seed(11) clear
replace betnr = . if betnr == 1 & year == 1
rcof "noisily `call'" == 459

* (e) Invalid values OUTSIDE the matching year are ignored (no error)
make_testdata, n(100) seed(11) clear
replace treat = . if betnr == 1 & year == 0
`call'

di _n as text "{bf:Part 2 summary}: all input checks behave as expected."


*==============================================================================
* Part 3: Speed benchmark
*==============================================================================
*
* Both commands run on the same data: one year, 6 matching variables with 4
* categories each (4,096 possible cells), 30% treated. Times are wall-clock
* seconds from a single run each.
*
* -cem- slows down roughly with the SQUARE of N (see cem_speed_explained.md),
* so it is only run up to bench_cem_max observations. On a standard desktop
* -cem- needs about 1 minute at N = 50,000 and about 3 minutes at
* N = 100,000. Raise bench_cem_max if you are willing to wait.
*
* At every N where both commands run, the results are also checked to be
* identical.
*------------------------------------------------------------------------------

global bench_n       1000 5000 10000 25000 50000 100000 250000 1000000 5000000
global bench_cem_max 50000

frame create bench long n double(t_ours t_cem) long n_matched

foreach n of global bench_n {
	make_testdata, n(`n') nyears(1) seed(`n') clear
	local match_vars `r(match_vars)'
	local cem_vars   `r(cem_vars)'

	timer clear

	timer on 1
	cem_peede_felder `match_vars', treat_indicator(treat) id(betnr) timevar(year) year(0)
	timer off 1

	if `n' <= $bench_cem_max {
		timer on 2
		quietly cem `cem_vars', treatment(treat) noimbal
		timer off 2

		assert matched_cem == cem_matched
		assert abs(weight_cem - cem_weights) < 1e-6
	}

	quietly timer list
	local t_ours = r(t1)
	local t_cem  = cond(`n' <= $bench_cem_max, r(t2), .)

	quietly count if matched_cem == 1
	frame post bench (`n') (`t_ours') (`t_cem') (r(N))

	di as text "N = " as result %9.0fc `n' ///
		as text "   cem_peede_felder: " as result %8.2f `t_ours' as text " s" ///
		as text "   cem: " as result %8.2f `t_cem' as text " s"
}

frame bench {
	gen speedup = t_cem / t_ours
	format t_ours t_cem %9.3f
	format speedup %9.0f
	format n n_matched %12.0fc

	di _n as text "{bf:Part 3 summary} (seconds; speedup = cem / cem_peede_felder):"
	list n n_matched t_ours t_cem speedup, noobs sep(0) abbreviate(12)

	export delimited using "cem_benchmark_results.csv", replace

	twoway (connected t_ours n, msymbol(O)) (connected t_cem n, msymbol(D)), ///
		xscale(log) yscale(log) ///
		xlabel(1000 "1k" 10000 "10k" 100000 "100k" 1000000 "1M" 5000000 "5M") ///
		ylabel(0.01 "0.01" 0.1 "0.1" 1 "1" 10 "10" 100 "100" 1000 "1000", angle(0)) ///
		xtitle("Number of observations (log scale)") ytitle("Seconds (log scale)") ///
		legend(order(1 "cem_peede_felder" 2 "cem (Iacus, King & Porro)") rows(1) position(6)) ///
		title("Run time of matching indicator and weights")
	graph export "cem_benchmark.png", replace width(1600)
}

di _n as text "{bf:All tests passed.}"
log close
