*! version 1.8 J Bartlett & T Morris 5th Feb 2015
* For history, see end of this file.

capture program drop smcfcs
program define smcfcs,eclass
version 11.0
syntax anything(name=smstring), [REGress(varlist)] [LOGIt(varlist)] [poisson(varlist)] [nbreg(varlist)] [mlogit(varlist)] [ologit(varlist)] [ITERations(integer 10)] [m(integer 5)] [rjlimit(integer 1000)] [passive(string)] [eq(string)] [rseed(string)] [chainonly] [savetrace(string)] [NOIsily] [by(varlist)] [clear]

*check mi has not been set already
quietly mi query
if "`r(style)'" != "" {
  if "`r(M)'" == "0" | "`clear'" == "clear" {
    local miconv `r(style)'
    mi extract 0, clear
  }
  else {
    display as error "Data are already mi set and contain imputations."
    exit 0
  }
}


if "`rseed'"!="" {
	set seed `rseed'
}

*split smstring into component parts
tokenize `smstring'
local smcmd `1'
macro shift
*check that outcome regression command is one of those supported
if (inlist("`smcmd'","stcox","logit","logistic","reg","regress")==0) {
		display as error "Specified substantive model regression command (`smcmd') not supported by smcfcs"
		exit 0
}

if "`smcmd'"!="stcox" {
		local smout `1'
		macro shift
}
local smcov `*'

*ensure that all partially observed cts variables are floating point type
if "`regress'"!="" {
	foreach var of varlist `regress' {
		recast float `var'
	}
}

*smcov consists of either fully observed covariates, regular covariates, or passively imputed covariates
*here we check the covariates listed to make sure they are either fully observed, missing and
*is specified using one of the options (e.g. regress), or is defined within the passive option

*to do this we first need a list of the passively defined variables
local passiveparse `passive'
tokenize "`passiveparse'", parse("|")
local passivedef
while "`1'"!="" {
	if "`1'"=="|" {
		macro shift
	}
		else {
		local rest `*'
		local currentpassivedef "`1'"
		tokenize `currentpassivedef', parse("=")
		local passivedef `passivedef' `1'
		tokenize "`rest'" , parse("|")
		macro shift
	}
}

local partiallyObserved `regress' `logit' `poisson' `nbreg' `mlogit' `ologit'

local exit=0
local varcheck: subinstr local smcov "i." "", all
foreach var in `smcov' {
	local varminusidot : subinstr local var "i." "", all
	quietly misstable summ `varminusidot'
	if "`r(vartype)'" == "none" {
		local fullyObserved `fullyObserved' `var'
	}
	else {
		local inpartial: list varminusidot in partiallyObserved
		if "`inpartial'"=="0" {
			*check that the variable is defined in the passive option
			local inpassive: list varminusidot in passivedef
			if "`inpassive'"=="0" {
				display as error "Covariate (`var') must either be fully observed, included in one of the imputation model options, or be defined in a passive statement."
				local exit=1
			}
		}
	}
}
if `exit'==1 {
	exit
}

local allCovariates `partiallyObserved' `fullyObserved'

local catmiss `logit' `mlogit' `ologit'

*process custom equation specification, if any
if "`eq'" != "" {
	tokenize `eq', parse("|")
	local i = 1
	while "``i''" != "" {
		if "``i''" != "|" {
			*split by colon
			tokenize ``i'', parse(":")
			local depVar `1'
			local indVars `3'
			local `depVar'impModelPred `indVars'
		}
		local i = `i' + 1
		tokenize `eq', parse("|")
	}
}


*construct commands to fit covariate models
di as text _newline "Covariate models:"
foreach var of varlist `partiallyObserved' {

	if "``var'impModelPred'"=="" {
		local impModelPredictors : list allCovariates - var
		local origImpModelPredictors `impModelPredictors'
		*make categorical predictors i.
		foreach predictor of local origImpModelPredictors {
			local predictorcat: list predictor in catmiss
			if `predictorcat'==1 {
				local impModelPredictors: subinstr local impModelPredictors "`predictor'" "i.`predictor'"
			}
		}	
	} 
	else {
		local impModelPredictors ``var'impModelPred'
	}
	
	local `var'impModelPred `impModelPredictors'

	local covtype: list var in regress
	if `covtype'==1 {
				local `var'covariateModelFit reg `var' `impModelPredictors'
	}
	else {
		local covtype: list var in logit
		if `covtype'==1 {
			local covtype = 2
			local `var'covariateModelFit logistic `var' `impModelPredictors', coef
		}
		else {
			local covtype: list var in poisson
			if `covtype'==1 {
				local covtype = 3
				local `var'covariateModelFit poisson `var' `impModelPredictors'
			}
			else {
				local covtype: list var in nbreg
				if `covtype'==1 {
					local covtype = 4
					local `var'covariateModelFit nbreg `var' `impModelPredictors'
				}
				else {
					local covtype: list var in mlogit
					if `covtype'==1 {
						local covtype = 5
						quietly levelsof `var', local(levels)
						tokenize `levels'
						local `var'covariateModelFit mlogit `var' `impModelPredictors', baseoutcome(`1')
					}
					else {
						local covtype = 6
						local `var'covariateModelFit ologit `var' `impModelPredictors'
					}
				}
			}
		}
	}
	di as text "``var'covariateModelFit'"
}

local dipassive `passive'
tokenize "`dipassive'", parse("|")
local i = 1
if "``i''" != "" {
	di as text _newline "Your passive statement(s) say:"
}
while "``i''" != "" {
	if "``i''" != "|" {
		display as text `"``i''"'
	}
	local i = `i' + 1
}

if "`chainonly'"!="" {
	local m = 1
}

if "`savetrace'"!="" {
	local postfilestring "iter"
	foreach var of varlist `partiallyObserved' {
		local postfilestring "`postfilestring' `var'_mean `var'_sd"
	}
	tempname tracefile
	postfile `tracefile' `postfilestring' using `savetrace', replace
}

local quietnoisy quietly
if "`noisily'"!="" {
	local quietnoisy
}

tempvar bygr
if "`by'"!="" {
	egen `bygr' = group(`by'), label
	`quietnoisy' summ `bygr'
	local numgroups=r(max)
}
else {
	gen `bygr' = 1
	local numgroups 1
}

tempvar smcfcsid
gen `smcfcsid' = _n

`quietnoisy' forvalues groupnum = 1/`numgroups' {
	if "`by'"!="" {
		noisily display
		noisily display as text "Imputing for group defined by (`by') = " _continue
		local labelval: label `bygr' `groupnum'
		noisily display "`labelval'"
	}
	`quietnoisy' forvalues imputation = 1/`m' {
		preserve

		keep if `bygr'==`groupnum'

		*generate observation indicators
		foreach var of varlist `partiallyObserved' {
			tempvar `var'_r
			gen ``var'_r' = (`var'!=.)
		}

		*perform preliminary imputation of covariates by sampling from observed values, as in ice
		foreach var of varlist `partiallyObserved' {
			mata: imputePermute("`var'", "``var'_r'")
		}
		updatevars, passive(`passive')

		*construct substantive/outcome model command
		if "`smcmd'"=="stcox" {
			local outcomeModelCommand stcox `smcov'
		}
		else {
			local outcomeModelCommand `smcmd' `smout' `smcov'
		}

		`outcomeModelCommand'	
		*if substantive model is linear or logistic, and there are missing values in outcome, impute based on preliminary imputations of covariates
		if e(cmd)=="regress" | e(cmd)=="logistic" | e(cmd)=="logit" {
			misstable summ `smout'
			if "`r(vartype)'" != "none" {
				if `imputation' == 1 {
					noisily di ""
					noisily di "Missing values in outcome are being imputed using the assumed substantive/outcome model."
				}
				local outcomeMiss = 1
				tempvar `smout'_r
				gen ``smout'_r' = (`smout'!=.)
				
				`outcomeModelCommand'
				
				*preliminary improper imputation, based on fit to those with outcome observed
				if e(cmd)=="regress" {
					tempvar xb
					predict `xb', xb
					replace `smout' = `xb' + e(rmse)*rnormal() if ``smout'_r'==0
				}
				else {
					tempvar pr
					predict `pr', pr
					replace `smout' = (runiform()<`pr') if ``smout'_r'==0
				}
			}
			else {
				local outcomeMiss = 0
			}
		}
		
		*get initial estimates of model of interest
		`outcomeModelCommand'
		if e(cmd)=="regress" {
			local outcomeModType "regress"
		}
		else if e(cmd)=="logistic" | e(cmd)=="logit" {
			local outcomeModType "logistic"
		}
		else if e(cmd)=="cox" {
			local outcomeModType "cox"
			predict H0, basechazard
		}
		else {
			display as error "{bold:smcfcs}: `e(cmd)' is not currently supported by smcfcs"
			error 1
		}
		
		gen _mj=0

		replace _mj = `imputation'
		forvalues cyclenum = 1(1)`iterations' {
			local tracestring
			foreach var of varlist `partiallyObserved' {
				*fit covariate model
				``var'covariateModelFit' 
								
				mata: covImp("``var'_r'","`var'","`smout'","`outcomeModelCommand'")
				
				if "`savetrace'"!="" {
					summ `var' if ``var'_r'==0
					local traceimpmean = r(mean)
					local traceimpsd = r(sd)
					local tracestring "`tracestring' (`traceimpmean') (`traceimpsd')"
				}
			}
			
			*if necessary, impute outcome
			if e(cmd)=="regress" | e(cmd)=="logistic" | e(cmd)=="logit" {
				if `outcomeMiss' == 1 {
					mata: outcomeImp("``smout'_r'","`smout'","`outcomeModelCommand'")
				}		
			}
			
			if "`savetrace'"!="" {
				*post iteration means and SDs
				post `tracefile' (`cyclenum') `tracestring'
			}
		}
		*save imputed dataset
		tempfile smcfcsimp_`groupnum'_`imputation'
		save `smcfcsimp_`groupnum'_`imputation''
		noisily _dots 1 0
	//  noisily display as text "Imputation " as result `imputation' as text " complete"
		restore
	}
}

if "`savetrace'"!="" {
	postclose `tracefile'
}

if "`chainonly'"!="" {
	di ""
	di "Chainonly option specified. No imputations produced."
}
else {
	*combine imputed datasets across by groups
	forvalues groupnum = 1/`numgroups' {
		forvalues imputation = 1(1)`m' {
			quietly append using `smcfcsimp_`groupnum'_`imputation''
		}
	}
	if "`outcomeModType'"=="cox" {
		drop H0
	}
	quietly replace _mj=0 if _mj==.
	quietly gen _mi=`smcfcsid'
	quietly sort _mj _mi

	display as result _newline `m' as text " imputations generated"

	*import into Stata's official mi commands and convert to user's favoured form
	noisily mi import ice, clear
	quietly mi register imputed `partiallyObserved'
	if "`passivedef'"!="" {
		quietly mi register passive `passivedef'
	}
	if "`outcomeMiss'"=="1" {
		quietly mi register imputed `smout'
	}
  if "`miconv'" != "" & "`miconv'" != "flong" {
    mi convert `miconv' , clear
  }

	if "`by'"=="" {
		display as text "Fitting substantive model to multiple imputations"
		mi estimate: `outcomeModelCommand'
	}
	else {
		display as text "Since you imputed separately by groups, smcfcs has not fitted a model to the combined (across groups) imputations."
	}
}

end


capture program drop updatevars
program define updatevars
syntax [, passive(string)]
tokenize "`passive'", parse("|")
local i = 1
while "``i''" != "" {
	if "``i''" != "|" {
		replace ``i''
	}
	local i = `i' + 1
}
end

capture program drop postdraw_strip
program define postdraw_strip

	matrix smcfcsb = e(b)
	matrix smcfcsv = e(V)

	_ms_omit_info smcfcsb
	local cols = colsof(smcfcsb)
	matrix smcfcsnomit =  J(1,`cols',1) - r(omit)
end

mata:
mata clear

void postdraw() {

	stata("postdraw_strip")

	stripV = select(st_matrix("smcfcsv"),(st_matrix("smcfcsnomit")))
	stripV = select(stripV, (st_matrix("smcfcsnomit"))')

	stripB = select(st_matrix("smcfcsb"),(st_matrix("smcfcsnomit")))

	if (st_global("e(cmd)")=="regress") {
		sigmasq = st_numscalar("e(rmse)")^2
		df = st_numscalar("e(df_r)")
		newsigmasq = sigmasq*df/rchi2(1,1,df)
		st_numscalar("smcfcs_resvar", newsigmasq)
		stripV = (newsigmasq/sigmasq)*stripV
	}

	
	/*take draw*/
	newstripB = transposeonly( transposeonly(stripB) + cholesky(stripV) * rnormal(1,1,J(cols(stripB),1,0),J(cols(stripB),1,1)) )

	/*recombine*/
	b = st_matrix("e(b)")
	
	b[,select(1..length(st_matrix("smcfcsnomit")), st_matrix("smcfcsnomit"))] = newstripB
	
	st_matrix("smcfcsnewb",b)
	stata("ereturn repost b=smcfcsnewb")
}

void imputePermute(string scalar varName, string scalar obsIndicator)
{
	data = st_data(., varName)
	r = st_data(., obsIndicator)
	n = st_nobs()
	imputationNeeded = select(transposeonly(1..n),J(n,1,1)-r)
	observedValues = select(data,r)
	numObserved = rows(observedValues)
	for (j=1; j<=length(imputationNeeded); j++) {
		i = imputationNeeded[j]
		/* randomly sample from observed values */
		draw = observedValues[ceil(runiform(1,1)*numObserved)]
		data[i] = draw
	}
	st_store(., varName, data)
}

void outcomeImp(string scalar missingnessIndicatorVarName, string varBeingImputed, string scalar outcomeModelCmd)
{
	st_view(r, ., missingnessIndicatorVarName)
	st_view(outcomeVar, ., varBeingImputed)
	
	/* fit substantive mode */
	stata(outcomeModelCmd)
	
	outcomeModelCmd = st_global("e(cmd)")
	postdraw()
	
	if (outcomeModelCmd=="regress") {
		newsigmasq = st_numscalar("smcfcs_resvar")
	}

	/* calculate fitted values */
	stata("predict smcfcsxb, xb")
	st_view(xb, ., "smcfcsxb")
	
	if (outcomeModelCmd=="regress") {
		fittedMean = xb
	}
	else if ((outcomeModelCmd=="logit") | (outcomeModelCmd=="logistic")) {
		fittedMean = invlogit(xb)
	}
	
	n = st_numscalar("e(N)")
	imputationNeeded = select(transposeonly(1..n),J(n,1,1)-r)
	
	if (outcomeModelCmd=="regress") {
		outcomeVar[imputationNeeded] = rnormal(1,1,fittedMean[imputationNeeded],newsigmasq^0.5)
	}
	else if ((outcomeModelCmd=="logit") | (outcomeModelCmd=="logistic")) {
		outcomeVar[imputationNeeded] = rbinomial(1,1,1, fittedMean[imputationNeeded])
	}
	
	st_dropvar("smcfcsxb")
}


void covImp(string scalar missingnessIndicatorVarName, string varBeingImputed, string scalar smout, string scalar outcomeModelCmd)
{
	r = st_data(., missingnessIndicatorVarName)
	rjLimit = strtoreal(st_local("rjlimit"))
	outcomeModType = st_local("outcomeModType")
	passive = st_local("passive")
	
	/* extract information from covariate model (which has just been fitted) */
	n = st_numscalar("e(N)")
	
	covariateModelCmd = st_global("e(cmd)")
	postdraw()
	newbeta = transposeonly(st_matrix("e(b)"))
		
	/* calculate fitted values */
	stata("predict smcfcsxb, xb")
	xb = st_data(., "smcfcsxb")
	/*st_view(xb, ., "smcfcsxb")*/
			
	if (covariateModelCmd=="regress") {
		fittedMean = xb
		newsigmasq = st_numscalar("smcfcs_resvar")
	}
	else if (covariateModelCmd=="logistic") {
		fittedMean = invlogit(xb)	
	}
	else if (covariateModelCmd=="poisson") {
		fittedMean = exp(xb)
	}
	else if (covariateModelCmd=="nbreg") {
		//alpha is the dispersion parameter
		alpha = exp(newbeta[rows(newbeta),1])
		fittedMean = exp(xb)
	}
	else if ((covariateModelCmd=="mlogit") | (covariateModelCmd=="ologit")) {
		if (covariateModelCmd=="mlogit") {
			numberOutcomes = st_numscalar("e(k_out)")
			catvarlevels = st_matrix("e(out)")
		}
		else {
			numberOutcomes = st_numscalar("e(k_cat)")
			catvarlevels = st_matrix("e(cat)")
		}
		mologitpredstr = "predict mologitprOutcomeNum, outcome(#OutcomeNum) pr"
		prOutVarstr = "mologitpr1"
		stata(subinstr(mologitpredstr, "OutcomeNum", "1"))
		for (i=2; i<=numberOutcomes; i++) {
			prOutVarstr = prOutVarstr , subinstr("mologitprx", "x", strofreal(i))
			stata(subinstr(mologitpredstr, "OutcomeNum", strofreal(i)))
		}
		fittedMean = st_data(., prOutVarstr)
		for (i=1; i<=numberOutcomes; i++) {
			st_dropvar(subinstr("mologitprOutcomeNum", "OutcomeNum", strofreal(i)))
		}
		//calculate running row sums (in built mata can't do this apparently)
		cumProbs = fittedMean
		for (i=2; i<=numberOutcomes; i++) {
			cumProbs[.,i] = cumProbs[.,i-1] + cumProbs[.,i]
		}
		//due to rounding errors last column sometimes slightly differs from 1, so set to 1
		cumProbs[.,numberOutcomes] = J(rows(cumProbs),1,1)
	}
	
	st_dropvar("smcfcsxb")
	
	/* fit substantive model */
	stata(outcomeModelCmd)
	postdraw()

	if (outcomeModType=="regress") {
		outcomeModResVar = st_numscalar("smcfcs_resvar")
		y = st_data(., smout)
	}
	else if (outcomeModType=="cox") {
		st_dropvar("H0")
		stata("predict H0, basechazard")
		d = st_data(., "_d")
		t = st_data(., "_t")
		H0 = st_data(., "H0")
		/*st_view(d, ., "_d")
		st_view(t, ., "_t")
		st_view(H0, ., "H0")*/
	}
	else {
		/*st_view(y, ., smout)*/
		y = st_data(., smout)
	}
	
	imputationNeeded = select(transposeonly(1..n),J(n,1,1)-r)
	
	stata("predict smcoutmodxb, xb")
	
	st_view(xMis, ., varBeingImputed)
	st_view(outmodxb, ., "smcoutmodxb")
	
	if ((covariateModelCmd=="mlogit") | (covariateModelCmd=="ologit") | (covariateModelCmd=="logistic")) {
		/*we can sample directly in this case*/
		if (covariateModelCmd=="logistic") {
			numberOutcomes = 2
			fittedMean = (1:-fittedMean,fittedMean)
		}
		
		outcomeDensCovDens = J(length(imputationNeeded),numberOutcomes,0)
		for (xMisVal=1; xMisVal<=numberOutcomes; xMisVal++) {
			
			if (covariateModelCmd=="logistic") {
				xMis[imputationNeeded] = J(length(imputationNeeded),1,xMisVal-1)
			}
			else {
				/*ologit or mlogit*/
				multdraw = J(length(imputationNeeded),1,xMisVal)
				recodedDraw = multdraw
				for (i=1; i<=length(catvarlevels); i++) {
					indices = select(range(1,length(imputationNeeded),1),multdraw:==i)
					if (length(indices)>0) {
						recodedDraw[indices] = J(length(indices),1,catvarlevels[i])
					}
				}
				xMis[imputationNeeded] = recodedDraw
			}
			if (passive!="") {
				stata(`"quietly updatevars, passive(""'+passive+`"")"')
			}

			st_dropvar("smcoutmodxb")
			stata("predict smcoutmodxb, xb")

			if (outcomeModType=="regress") {
				deviation = y[imputationNeeded] - outmodxb[imputationNeeded]
				outcomeDens = normalden(deviation:/(outcomeModResVar^0.5))/(outcomeModResVar^0.5)
			}
			else if (outcomeModType=="logistic") {
				prob = invlogit(outmodxb[imputationNeeded])
				ysub = y[imputationNeeded]
				outcomeDens = prob :* ysub + (J(length(imputationNeeded),1,1) :- prob) :* (J(length(imputationNeeded),1,1) :- ysub)
			}
			else if (outcomeModType=="cox") {
				outcomeDens = exp(-H0[imputationNeeded] :* exp(outmodxb[imputationNeeded])) :* (exp(outmodxb[imputationNeeded]):^d[imputationNeeded])
			}
			
			outcomeDensCovDens[,xMisVal] = outcomeDens :* fittedMean[imputationNeeded,xMisVal]
		}
		
		directImpProbs = outcomeDensCovDens :/ rowsum(outcomeDensCovDens)
		
		if (covariateModelCmd=="logistic") {
		
			directImpProbs = directImpProbs[.,2]
			/*ensure that probabilities are within Stata's specified limits*/
			directImpProbs = rowmax((directImpProbs,J(rows(directImpProbs),1,1e-8)))
			directImpProbs = rowmin((directImpProbs,J(rows(directImpProbs),1,1-1e-8)))
			xMis[imputationNeeded] = rbinomial(1,1,1, directImpProbs)
		}
		else {
			/*ologit or mlogit*/
			//take a draw from a multinomial distribution, coded 1:numberOutcomes
			cumProbs = directImpProbs
			for (i=2; i<=numberOutcomes; i++) {
				cumProbs[.,i] = cumProbs[.,i-1] + cumProbs[.,i]
			}
			multdraw = J(length(imputationNeeded),1,numberOutcomes+1) - rowsum(runiform(length(imputationNeeded),1) :< cumProbs)
			//now recode
			recodedDraw = multdraw
			for (i=1; i<=length(catvarlevels); i++) {
				indices = select(range(1,length(imputationNeeded),1),multdraw:==i)
				if (length(indices)>0) {
					recodedDraw[indices] = J(length(indices),1,catvarlevels[i])
				}
			}
			xMis[imputationNeeded] = recodedDraw
		}
		/*call passive to update based on new draw*/
		if (passive!="") {
			stata(`"quietly updatevars, passive(""'+passive+`"")"')
		}
	}
	else {
		j=1
		
		while ((length(imputationNeeded)>0) & (j<rjLimit)) {
			if (covariateModelCmd=="regress") {
				xMis[imputationNeeded] = rnormal(1,1,fittedMean[imputationNeeded],newsigmasq^0.5)
			}
			else if (covariateModelCmd=="logistic") {
				xMis[imputationNeeded] = rbinomial(1,1,1, fittedMean[imputationNeeded])
			}
			else if (covariateModelCmd=="poisson") {
				xMis[imputationNeeded] = rpoisson(1,1, fittedMean[imputationNeeded])
			}
			else if (covariateModelCmd=="nbreg") {
				//for negative binomial, first generate draw of gamma random effect
				poissonMeans = rgamma(1,1,J(length(imputationNeeded),1,1/alpha),alpha:*fittedMean[imputationNeeded])
				//if a draw from the Gamma distribution is lower than Stata's rpoisson(m) lower limit for m (1e-6), missing values are generated
				//therefore perform a check to ensure means are not below Stata's rpoisson lower threshold, and set any which are, to the threshold
				poissonMeans = rowmax((J(length(imputationNeeded),1,1e-6),poissonMeans))
				xMis[imputationNeeded] = rpoisson(1,1, poissonMeans)
			}
			else if ((covariateModelCmd=="mlogit") | (covariateModelCmd=="ologit")) {
				//take a draw from a multinomial distribution, coded 1:numberOutcomes
				multdraw = J(length(imputationNeeded),1,numberOutcomes+1) - rowsum(runiform(length(imputationNeeded),1) :< cumProbs[imputationNeeded,.])
				//now recode
				recodedDraw = multdraw
				for (i=1; i<=length(catvarlevels); i++) {
					indices = select(range(1,length(imputationNeeded),1),multdraw:==i)
					if (length(indices)>0) {
						recodedDraw[indices] = J(length(indices),1,catvarlevels[i])
					}
				}
				xMis[imputationNeeded] = recodedDraw
			}
		
			if (passive!="") {
				stata(`"quietly updatevars, passive(""'+passive+`"")"')
			}
			
			uDraw = runiform(length(imputationNeeded),1)
			
			st_dropvar("smcoutmodxb")
			stata("predict smcoutmodxb, xb")
			
			if (outcomeModType=="regress") {
				deviation = y[imputationNeeded] - outmodxb[imputationNeeded]
				reject = log(uDraw) :> -(deviation:*deviation) :/ (2*J(length(imputationNeeded),1,outcomeModResVar))
			}
			else if (outcomeModType=="logistic") {
				prob = invlogit(outmodxb[imputationNeeded])
				ysub = y[imputationNeeded]
				prob = prob :* ysub + (J(length(imputationNeeded),1,1) :- prob) :* (J(length(imputationNeeded),1,1) :- ysub)
				reject = uDraw :> prob
			}
			else if (outcomeModType=="cox") {
				s_t = exp(-H0[imputationNeeded] :* exp(outmodxb[imputationNeeded]))
				prob = exp(J(length(imputationNeeded),1,1) + outmodxb[imputationNeeded] - (H0[imputationNeeded] :* exp(outmodxb[imputationNeeded])) ) :* H0[imputationNeeded]
				prob = d[imputationNeeded]:*prob + (J(length(imputationNeeded),1,1)-d[imputationNeeded]):*s_t
				reject = uDraw :> prob
			}
			
			imputationNeeded = select(imputationNeeded, reject)
			j = j + 1
			//length(imputationNeeded)
		}

		if (j>=rjLimit) {
			messagestring = `"noisily display as error "Warning" as text ": valid imputed values may not have been generated for imputationNeeded subject(s). You should probably increase the rejection sampling limit.""'
			stata(subinstr(messagestring, "imputationNeeded", strofreal(length(imputationNeeded))))
		}
	}
	
	st_dropvar("smcoutmodxb")
	
}


end

exit

History of smcfcs

05/02/2015  Allowed use of data that are already -mi set-. Added a clear option so that if imputations already exist, smcfcs can clear them instead of exiting with an error.
07/01/2015  Changed use of Mata function selectindex so that Stata version 11 and 12 users can still use the command.
			Added check to ensure that dataset is not mi set when smcfcs is called.
05/12/2014  Fixed bug where i. dummies in substantive model for variables being imputed were not being updated in covImp since they're not defined by the user in a passive statement
			To resolve this, smcfcs now calls all regression commands without xi:, such that calls to predict properly update any internal dummy variables.
			Fixed bug in the direct sampling code added 31/10/2014 (needed to update passive variables after direct sampling)
			Fixed bug in direct sampling with linear outcome models caused by unexpected behaviour of normalden() function (which was due to previously having version 11.0 at top)
31/10/2014  Rejection sampling replaced by (faster) direct sampling for logistic, ologit and mlogit covariates
08/09/2014	Added by option to enable imputation separately by groups
			Modified syntax of command
			When imputation is completed, passive variables are registered as passive and imputed as imputed (previously all substantive model covariates were registered as imputed)
01/07/2014  Fixed bug in imputation of missing continuous outcomes
08/06/2014  Added ability to impute missing outcomes (regress and logistic models only)
15/07/2013  Mlogit and ologit imputation functionality added for unordered and ordered categorical variables
			Handling of i. factor variables added
21/06/2013	Chainonly and savetrace options added to allow for convergence checking
20/06/2013  Poisson and negative binomial imputation for count variables added
			rseed optiona added
01/06/2013  The requirement to write a program called updateDerivedVariables was replaced with the passive() option
            Various option names changed and shortened
            Mata rejection sampling code tuned to make it much shorter and neater
29/04/2013  Multiple chains are now used, rather than a single chain, to match ice and mi impute chained
29/10/2012  First version of smcfcs Released
20/12/2012  Changed name of command from congenialFCS to smcfcs