/*==============================================================================
cem_peede_felder - fast CEM matching indicator and weights
--------------------------------------------------------------------------------
PURPOSE  Same match indicator and weights as -cem- (Blackwell et al. 2009;
         Iacus, King & Porro 2012), but sort-based and therefore fast enough
         for large administrative data.
         Do-file instead of ado to ease transfer into FDZ environments.

USAGE    do "cem_peede_felder_program.do"
         cem_peede_felder x1 x2 ..., treat_indicator(treat) id(betnr) ///
             timevar(year) year(2015) [matchlab("...") weightlab("...")]

OUTPUT   matched_cem  1 = matched, 0 = not matched          (= cem_matched)
         weight_cem   CEM weight, 0 if not matched          (= cem_weights)
         Computed in the matching year and copied to all years of the same id.
         Ids without an observation in the matching year get missing values.

EXPECTS  - Matching variables already coarsened (categorical). Continuous
           variables are matched exactly, value by value.
         - id uniquely identifies observations within the matching year.
         - Treatment coded 0/1, no missings, fixed per id. One common matching
           year for all ids.
         - Missing values in matching variables count as their own category,
           as in -cem-.

CANNOT   Coarsen variables, compute imbalance measures (L1), k2k matching,
         multiply imputed data, more than two treatment groups, or different
         matching years for different ids.

AUTHORS  Lennert Peede and Lars Felder. Mistakes or unexpected behaviour:
         lfelder@diw.de

REFERENCES
         Blackwell, Matthew, et al. "CEM: Coarsened exact matching in Stata."
           The Stata Journal 9.4 (2009): 524-546.
         Iacus, Stefano M., Gary King, and Giuseppe Porro. "Causal inference
           without balance checking: Coarsened exact matching." Political
           Analysis 20.1 (2012): 1-24.
==============================================================================*/


	cap program drop cem_peede_felder

	program define cem_peede_felder, rclass

	// ---------------------------------------------
	// Args:
	//   varlist         = matching variables (already coarsened / categorical)
	//   treat_indicator = treatment variable, coded 0/1, no missings in matching year
	//   id              = unit identifier, unique within the matching year
	//   timevar         = time variable
	//   year            = value of timevar in which matching takes place
	//   matchlab        = optional variable label for matched_cem
	//   weightlab       = optional variable label for weight_cem
	// ---------------------------------------------

	syntax varlist(min=1) , treat_indicator(varname) id(varname) timevar(varname) year(integer) [matchlab(string) weightlab(string)]

		// id must be non-missing and unique within the matching year,
		// otherwise copying results across periods by id would mix units
		capture assert !missing(`id') if `timevar' == `year'
		if _rc {
			di as error "`id' has missing values in `timevar' == `year'"
			exit 459
		}
		capture bysort `id' `timevar': assert _N == 1 if `timevar' == `year'
		if _rc {
			di as error "`id' does not uniquely identify observations in `timevar' == `year'"
			exit 459
		}

		// treatment must be binary 0/1 without missings in the matching year
		// (cem would treat missing or any further value as an additional treatment group)
		capture assert !missing(`treat_indicator') if `timevar' == `year'
		if _rc {
			di as error "`treat_indicator' has missing values in `timevar' == `year'"
			exit 459
		}
		capture assert inlist(`treat_indicator', 0, 1) if `timevar' == `year'
		if _rc {
			di as error "`treat_indicator' must be coded 0/1 in `timevar' == `year' (found other values or more than 2 levels)"
			exit 459
		}

		quietly{
		sort `varlist' `treat_indicator' `id' `timevar'

		egen strata = group(`varlist' `treat_indicator') if `timevar' == `year' , missing

		bysort strata: gen byte first_strata_obs = (_n ==1) if `timevar' == `year'

		duplicates tag `varlist' if first_strata_obs == 1 & `timevar' == `year' , gen(has_twin_help)

		bysort strata: egen byte hand_matched = max(has_twin_help) if `timevar' == `year'
		drop has_twin_help

		replace strata = . if hand_matched != 1
		egen long strata2 = group(strata) if hand_matched == 1 & `timevar' == `year'

		count if hand_matched == 1 & `treat_indicator' == 0 & `timevar' == `year'
		local tot_match_c `r(N)'
		count if hand_matched == 1 & `treat_indicator' == 1 & `timevar' == `year'
		local tot_match_t `r(N)'
		gen double rel_ct = `tot_match_c' / `tot_match_t'

		gen long match_strata = ceil(strata2/2) if `timevar' == `year'
		bysort match_strata: egen double strat_c = total(`treat_indicator'==0) if `timevar' == `year'
		bysort match_strata: egen double strat_t = total(`treat_indicator'==1) if `timevar' == `year'

		gen double hand_weights = 0 if `timevar' == `year'
		replace hand_weights = 1 if `treat_indicator' == 1 & hand_matched == 1 & `timevar' == `year'
		replace hand_weights = rel_ct * (strat_t / strat_c) if hand_matched == 1 & `treat_indicator' == 0 & `timevar' == `year'

		drop strata first_strata_obs strata2 rel_ct match_strata strat_c strat_t

		bysort `id': egen matched_cem = max(hand_matched)
		bysort `id': egen double weight_cem = max(hand_weights)

		drop hand_matched
		drop hand_weights

		if ("`matchlab'" != "") label variable matched_cem "`matchlab'"
		if ("`weightlab'" != "") label variable weight_cem "`weightlab'"
		}

	end
