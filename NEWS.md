# brfssdata 0.1.0

Initial CRAN release.

## Correctness

* The missing-code matcher now recognizes CDC's calculated-variable
  buckets whose labels carry a trailing noun ("Don't know, refused or
  missing values" and kin, plus the RACE2 family's "component question"
  wordings). Before this, `na = TRUE` (the `brfss_design()` default)
  silently left genuine code-9 don't-know/refused answers in 18
  variable/code combinations, including `_FRTLT1A` (51,087 uncleared
  rows in 2021 alone), `_HLTHPLN`, `_VEGLT1A`, and the `_LMT*` family,
  overstating those denominators by several points. The extension was
  validated against every distinct catalog label: it adds exactly those
  buckets and loses none, and "Doctor refused when asked"-style
  substantive answers still never match.
* Six variables that CDC stored as a number in some years and text in
  others (`SEQNO`, `_RECORD`, `MRACEORG`, `WINDDOWN`, `_MSACODE`,
  `RCVFVCH4`) are now written with one type across every hosted year,
  values unchanged. Multi-year reads previously promoted the numeric
  years to text, so the same MSA appeared as both `"1120"` and
  `"1120.0"` in one column, silently splitting groups and defeating
  missing-code matching. `read_brfss()` additionally refuses to combine
  files whose stored types conflict (`brfssdata_type_conflict`), so a
  stale cache mixed with current releases can never reproduce the bug
  silently; `brfss_cache_clear()` is the named remedy.
* A user-supplied `weight` in `brfss_design()` now subsets to the rows
  the weight covers, with a `brfssdata_weight_subset_note` message. The
  documented child-module call, `brfss_design(2023, weight =
  "_CLLCPWT")`, previously always failed on real data, because a module
  weight is missing outside its module's records (383,782 of 433,323
  rows in 2023) and the design constructor refused missing weights. The
  automatic era weight still aborts on missing values, which there
  indicate a damaged file.
* `na = TRUE` says so (`brfssdata_na_coverage_note`) when requested
  years have no value-label catalog at all (1985-1997) or mostly lack
  it (1998 covers under a quarter of that file's variables), instead of
  silently changing nothing.
* Blank SAS character fields are stored as missing values, not `""`,
  and code matching is proof against R's scientific notation, so a
  future round code at or above 100,000 cannot be skipped.

## Discovery and metadata

* `brfss_crosswalk()` reports CDC's trailing-digit rename families
  (`_DRNKWK1` to `_DRNKWK3`). A `status` column records how far human
  review of each family has gone (mechanically proposed families ship
  as `"candidate"`), and `comparable`/`note` record the reviewed
  verdict per generation pair. When a requested variable is empty in
  years a sibling generation covers, `read_brfss()` says so
  (`brfssdata_rename_note`); combining generations stays the analyst's
  decision.
* `read_brfss()` and `brfss_design()` gain `states =` (FIPS, postal
  abbreviation, or name), pushed into the DuckDB query so other states'
  rows never reach R. For states this pre-filtering is variance-exact,
  because BRFSS strata nest within state. A requested state absent from
  a year warns (`brfssdata_state_coverage_warning`).
* `brfss_codebook()` renders a per-variable card: label history, value
  labels with missing-type codes flagged, year availability, and the
  rename family. `brfss_year_info()` lists respondents, variables,
  states, hosted size, and CDC's documentation page per year.
  `brfss_citation()` returns per-year `bibentry` citations.
* New package data: `brfss_states` (FIPS, names, abbreviations, Census
  regions for all 56 BRFSS jurisdictions) and `brfss_std_pop_2000` (the
  2000 projected U.S. standard population, all-ages and `_AGE_G`-
  matched adult groupings, for `survey::svystandardize()`).
* The variable, label, and crosswalk catalogs ship as bundled snapshots,
  so metadata functions work on first use with no network; a snapshot
  is never served silently (`brfssdata_bundled_fallback_note`).

## Access

* `read_brfss()` returns respondent-level BRFSS microdata for any of the
  40 published survey years (1985-2024) as a tibble. Each year is
  downloaded once from the package's data releases, verified against a
  published sha256 checksum, and cached under `tools::R_user_dir()`;
  queries run locally through DuckDB, so selecting a handful of
  variables from a 300-plus column survey stays fast and repeat use
  works offline.
* `brfss_design()` builds a srvyr survey-design object with the
  era-correct final weight (`_FINALWT` through 2010, `_LLCPWT` from
  2011), strata, and primary sampling units. Requests that pool years
  across the 2011 redesign fail unless `allow_break = TRUE` is set,
  because CDC states estimates are not comparable across that boundary.
  Files through 2000 carry genuine multi-respondent PSUs and keep the
  clustered variance estimator; from 2001 on each respondent is their
  own PSU, and the design drops the nominal cluster term for identical
  estimates at a fraction of the cost. A `weight` argument selects
  another final weight, such as the child weight `_CLLCPWT`, when CDC's
  documentation calls for it; requesting an intermediate stage of CDC's
  weighting pipeline (such as `_LLCPWT2`, the truncated design weight
  computed before raking) triggers a classed warning, because those
  columns are not analysis weights. Module analyses that require CDC's
  questionnaire-version datasets and their `_LCPWTV1` to `_LCPWTV3`
  final weights are not supported by the hosted annual files.
* By default, `brfss_design()` sets the codes CDC uses for don't-know,
  refused, and missing-type answers to `NA` (`na = TRUE`), so means and
  proportions cover substantive answers; `read_brfss()` defaults to
  `na = FALSE` and returns the file as published. The exported
  `brfss_missing_codes()` lists exactly which codes are affected.
* `brfss_labels()` exposes CDC's value-label catalog (1998-2024), and
  `labels = TRUE` converts variables with safe one-to-one maps to
  factors; ambiguous maps keep their numeric codes. `labels = "both"`
  keeps the code in the level text so it survives conversion.
* `brfss_vars()` searches variable names and labels across years;
  `brfss_years()` lists the published years. Variable names match
  case-insensitively everywhere, and returned columns keep CDC's
  canonical spelling.
* `brfss_download()` prefetches years and the metadata catalogs for
  offline use; `brfss_cache_dir()`, `brfss_cache_info()`, and
  `brfss_cache_clear()` manage the cache. A cached file that fails
  integrity checks is re-downloaded automatically or named in a classed
  error with its remedy.
* Every error, warning, and message carries a documented condition
  class; see `?brfssdata-conditions`.
