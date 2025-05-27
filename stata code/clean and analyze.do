* Judd Ormsby 25 May 2025
* Cleans data and then performs analysis per home task.

clear all
set more off

* set global for Main working directory
global MAIN /Users/juddormsby/Library/CloudStorage/Dropbox/CV/Applications/Deel/home task/


import delimited "${MAIN}/raw data/raw_data.csv", clear

********************************************************************************
****** CLEANING AND CHECKING 

des
codebook // check missings unique values etc.
** not terrible, missings don't look too bad mostly.

egen rowmiss = rowmiss(*) // number of missings variables per ob.
tab rowmiss // as expected small number missing everthing

bro if rowmiss == 7
bro if rowmiss == 10 // more probelmatic , these just haven't imported correctly. But also look like they are missing id vars so for now dro


drop if rowmiss >= 7 // DROPS 480 of ~ 484k obs or less that 0.1% of obs.
* note with more time could spend a bit more effort looking into why corrupted, or whether to use them with country data etc.
* but since so minor # of obs relative to data set it is unlikely a good use of time at this stage.
* e.g. about 245 of these obs seem to have some country data but missing countract ids., also at a glance dispersed over multiple countries - safer/easier for now to exclude 

* label data better
gen double start_dt = dofc(clock(substr(contract_start_date,1,23), "YMDhms"))
gen double end_dt = dofc(clock(contract_end_date, "YMDhms"))

format %td start_dt end_dt

encode contract_id , gen(contract_id2)
order contract_id2 , first
label values contract_id2

gen month_spine2 = mofd(date(month_spine,"YMD"))
order month_spine2 
format %tm month_spine2

drop contract_id month_spine // drop string versions

***** check data structure
* every month should be consecutive.
bys contract_id (month_spine) : gen month_consec2 = month_spine - month_spine[_n-1]
assert month_consec == 1 | month_consec == . // checks out.

* org constant within contract? 
bys contract_id (month_spine) : gen org_cons = (organization_id == organization_id[_n-1]) if _n >1
assert inlist(org_cons,1,.) // yes constant

* job title constant within contract?
bys contract_id (month_spine) : gen job_title_cons = (job_title_name == job_title_name[_n-1]) if _n > 1
assert inlist(job_title_cons,1,.) // yest constant


* save cleaned data in stata format (speeds up processing).
compress
save "/Users/juddormsby/Library/CloudStorage/Dropbox/CV/Applications/Deel/home task/out/deel_clean.dta" , replace // allows for commenting out this section and saving time


********************************************************************************
*******
* Q1 analysis: most employees by country
* well ... we don't have a worker id 
* so need to assume contracts map closely enough to workers (i.e. not muddled by multiple contracts per worker at same time).
* but let's go with that.
use "${MAIN}/out/deel_clean.dta" , clear // needed if above section commented out.


preserve
	* subset to most recent month
	keep if month_spine2 == mofd(date("1june2024","DMY"))
	
	
	* collapse data by country (and whether contract active or not).
	collapse (count) count=contract_id2 , by(contract_country is_active)
	
	* convert active to numeric from string
	encode is_active , gen(is_actv)
	drop is_active


	* reshape into wide format
	reshape wide count , i(contract_country) j(is_actv)
	rename count1 inactive 
	rename count2 active
	
	
	* calculate sum of inactive and active)
	egen total = rowtotal(inactive active)

	gsort - total // sort descending
	list in 1/6 // list top 6. Observe ranking doesn't depend on active/inactive.
	
	* export data to excel for posterity.
	export excel using "${MAIN}/out/analysis.xlsx", sheet("q1_country_rank") sheetreplace firstrow(variables)

restore

********************************************************************************
* Q2 job title
codebook job_title_name // over 19k unique values, never missing.

preserve
	* let's look at popularity in just the most recent month.
	keep if month_spine2 == mofd(date("1june2024","DMY"))
	tab is_active , miss // check % 
	collapse (count) count = contract_id2 , by(job_title_name)
	
	order job_title, first
	gsort - count // sort by most to least common.
	
	* export top 100 (rather than all 19k titles ...)
	
	keep if _n < 100
	
	export excel using "${MAIN}/out/analysis.xlsx", sheet("q2_role_title_rank") sheetreplace firstrow(variables)

restore	

********************************************************************************
* Q3 salary increase

* subset to canada.
keep if contract_country == "CA"

* exclude hours and inactive.
drop if compensation_scale == "hourly" // doesn't make sense to include
drop if is_active_on_date == "false" // dropping at month-contract level - so in principle keep people with gaps (if data has gaps).

* let's define annual incrase for people in a job for at least 12 months by comparing to pay 12 months ago.
* this gets to the questions focus on "people in a job". Also doesn't really make sense to annualize this month to last month as most of this will be zero for peopl recieving annual increase.

* tell stata data is panel so can use panel operators

xtset contract_id2 month_spine2

gen comp_12 = L12.compensation_rate_usd
label var comp_12 "compensation 12 months ago (missing if not employed/active on same contract)"

gen salary_increase = compensation_rate_usd - comp_12
label var comp_12 "absolute salary increase (missing if not employed/active on same contract)"

gen pct_increase = salary_increase/comp_12
label var pct_increase "percentage salary increase"


bys month_spine: su salary_increase , detail // curious how many negatives there are.possibly due to pseudo-data generating process.
bys month_spine: su pct_increase , detail

** collapse as tidy version for excel export
preserve
	* by month
	collapse ///
			(count) total_contracts = contract_id total_in_job12 = comp_12 ///
			(mean) 	mean_salary=compensation_rate_usd mean_increase=salary_increase  mean_pct_increase=pct_increase ///
			 (p50) median_salary=compensation_rate_usd  med_increase=salary_increase  med_pct_increase=pct_increase ///
			 , by(month_spine2)
			 
	drop if mean_increase == . // get rid of first 12 months where data undefined.
	export excel using "${MAIN}/out/analysis.xlsx", sheet("q3_salaries_by_month") sheetreplace firstrow(varlabels)

restore 

preserve
	* average over first six months of 2024
	collapse ///
			(count) total_contracts = contract_id total_in_job12 = comp_12 ///
			(mean) 	mean_salary=compensation_rate_usd mean_increase=salary_increase  mean_pct_increase=pct_increase ///
			 (p50) median_salary=compensation_rate_usd  med_increase=salary_increase  med_pct_increase=pct_increase 
			 
	export excel using "${MAIN}/out/analysis.xlsx", sheet("q3_salaries") sheetreplace firstrow(varlabels)

restore 

********************************************************************************
* Section B insight.
* let's do Deel growth and jobs by country as easiest given short time and complimentarity with prior questions.


preserve
	use "${MAIN}/out/deel_clean.dta" , clear // needed if above section commented out.

	* remove inactive 
	drop if is_active_on_date == "false" 

	* keep key months of 2024 and 2023
	keep if month_spine2 == mofd(date("1june2024","DMY")) | month_spine2 == mofd(date("1june2023","DMY"))

	** okay collapse by month 
	collapse (count) count=contract_id2 , by(contract_country month_spine)

	*reshape wide
	reshape wide count , i(contract_country) j(month)
	rename count761 contracts_2023
	rename count773 contracts_2024

	gen change = contracts_2024 - contracts_2023
	* practically everywwhere grew (handful of tiny exceptions).
	gsort - change

	gen pct_change = change/contracts_2023
	* gsort - pct_change // as expected biggest changes are those with a tiny base so stick to aboslutes for now.
	* so comment out sort by pct_change sticking to absolutes.


	* keep top 12 countries (will further reduce to like 5, but want flexibility later while keeping tidy).

	export excel using "${MAIN}/out/analysis.xlsx", sheet("q4_insight_raw") sheetreplace firstrow(varlabels)

restore
