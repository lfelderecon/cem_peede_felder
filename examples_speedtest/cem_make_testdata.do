
** Defines the program make_testdata, which generates test datasets for cem_peede_felder
** Usage: do "cem_make_testdata.do", then call make_testdata

/*
Generated variables:
	- betnr      unit identifier (unique within each year)
	- year       0, 1, ..., nyears-1
	- treat      treatment indicator 0/1, constant over time within betnr
	- x1 ... xK  categorical matching variables with values 1..ncats (and missings)

Options:
	n(#)            number of units (required)
	nvars(#)        number of matching variables K                  (default 6)
	ncats(numlist)  categories per variable: one number for all
	                variables, or one number per variable           (default 4)
	skew(#)         1 = categories equally likely; > 1 = low
	                categories more likely (unequal cell sizes)      (default 1)
	treatshare(#)   share of treated units                           (default 0.3)
	missshare(#)    share of missing values, independently per
	                variable                                         (default 0)
	nyears(#)       number of periods                                (default 2)
	panelchange(#)  probability that a unit's value of a variable
	                is redrawn in each later period (0 = matching
	                variables constant over time)                    (default 0)
	idscatter       non-consecutive ids and random row order
	seed(#)         random number seed                               (default 123)
	clear           replace the data in memory

Returned:
	r(match_vars)   x1 x2 ... xK
	r(cem_vars)     x1 (#0) x2 (#0) ... xK (#0)   -> no coarsening in cem for run time testing 
*/


	cap program drop make_testdata

	program define make_testdata, rclass

	syntax , n(integer) [nvars(integer 6) ncats(numlist integer >=1) skew(real 1) ///
		treatshare(real 0.3) missshare(real 0) nyears(integer 2) panelchange(real 0) ///
		idscatter seed(integer 123) clear]

		// ---- input checks
		if `n' < 1 {
			di as error "n() must be at least 1"
			exit 198
		}
		if `nvars' < 1 {
			di as error "nvars() must be at least 1"
			exit 198
		}
		if `nyears' < 1 {
			di as error "nyears() must be at least 1"
			exit 198
		}
		if `skew' <= 0 {
			di as error "skew() must be positive"
			exit 198
		}
		foreach opt in treatshare missshare panelchange {
			if !inrange(``opt'', 0, 1) {
				di as error "`opt'() must be between 0 and 1"
				exit 198
			}
		}
		if "`ncats'" == "" local ncats 4
		local n_ncats : word count `ncats'
		if `n_ncats' != 1 & `n_ncats' != `nvars' {
			di as error "ncats() must contain either 1 number or nvars() = `nvars' numbers"
			exit 198
		}
		if c(changed) & "`clear'" == "" {
			error 4
		}

		// ---- generate data
		clear
		set seed `seed'

		quietly {
		set obs `n'

		if "`idscatter'" != "" {
			// unique but non-consecutive ids, rows in random order
			gen long betnr = _n * 7 + floor(7 * runiform())
		}
		else {
			gen long betnr = _n
		}

		gen byte treat = (runiform() < `treatshare')

		// matching variables in the first period
		forvalues j = 1/`nvars' {
			if `n_ncats' == 1 local k `ncats'
			else local k : word `j' of `ncats'
			gen long x`j' = cond(runiform() < `missshare', ., floor(`k' * runiform()^`skew') + 1)
			local match_vars `match_vars' x`j'
			local cem_vars `cem_vars' x`j' (#0)
		}

		// panel structure: later periods start as copies of the first period ...
		expand `nyears'
		bysort betnr: gen int year = _n - 1

		// ... and each value is redrawn with probability panelchange
		if `panelchange' > 0 & `nyears' > 1 {
			forvalues j = 1/`nvars' {
				if `n_ncats' == 1 local k `ncats'
				else local k : word `j' of `ncats'
				replace x`j' = cond(runiform() < `missshare', ., floor(`k' * runiform()^`skew') + 1) ///
					if year > 0 & runiform() < `panelchange'
			}
		}

		if "`idscatter'" != "" {
			gen double sortorder = runiform()
			sort sortorder
			drop sortorder
		}
		else {
			sort betnr year
		}
		}

		return local match_vars `match_vars'
		return local cem_vars `cem_vars'

	end
