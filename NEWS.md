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
  indicate a damaged file, and an explicitly named full-sample weight
  (`_LLCPWT`, `_FINALWT`) follows that same rule instead of silently
  subsetting.
* The matcher also recognizes the abbreviations CDC's 1998 to 2001
  format libraries use for don't-know and refused ("UNK/REF", "UNK",
  "REF", "UNKNOWN"), together with the bare "N/A" and "N/A,REF"
  placeholders from the same years. Validated against every row of the
  shipped catalog, this matches 786 rows across 370 variables, all in
  1998 to 2001, and loses none. Without it, `na = TRUE` left those
  codes in the data for years the catalog nominally covers: 145,594
  cells in the 1998 file (`_DRNKMO` code 9999 alone on 117,351 rows)
  and 380,693 in 2001, so any mean or proportion from an affected
  variable was wrong. Spelled-out "not applicable" is deliberately not
  a token, because in later years it names ordinal scale positions such
  as `GETHIV` code 5.
* `na = TRUE` says so when requested years have no value-label catalog
  at all (1985-1997, a classed `brfssdata_na_coverage_warning`) or
  mostly lack it (1998 covers under a quarter of that file's
  variables, a `brfssdata_na_coverage_note`), instead of silently
  changing nothing.
* `labels = TRUE` refuses to convert a variable whose label wording
  changed meaning across the requested years, keeping CDC's numeric
  codes and naming it in a `brfssdata_label_drift_warning`. Applying
  the newest year's labels to every row would restate what earlier
  respondents answered: CDC reused `COLNTES1` and `SIGMTES1` codes 3 to
  5 for different colorectal screening intervals from 2022 on, so
  `read_brfss(2021:2024, vars = "COLNTES1", labels = TRUE)` would
  otherwise return a wrong interval distribution. This matches how
  every other ambiguity gate (incomplete formats, mismatched code sets,
  duplicate codes or labels, uncovered values) already behaves. The
  wording comparison folds `<` and `>` to words before stripping
  punctuation, so CDC's house abbreviation ("anytime < 12 months ago"
  against "anytime less than 12 months ago") counts as cosmetic and
  still converts.
* The pooled state-participation warning
  (`brfssdata_pooled_states_warning`) counts participation over the
  rows a user-supplied `weight` covers, the population the design
  actually estimates, not over the whole annual file. Counting over the
  file names states the design never contained, and goes silent when
  the files agree on coverage but the weight's domain does not, which
  is exactly the case for 2022 pooled with 2023 under `_CLLCPWT`.
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
  rename family. A card whose variable has no coded values says which
  of the two reasons applies, either that the requested years sit
  outside the catalog's span or that CDC's format for the variable is
  continuous or range-only (`_BMI5`), and a card built from a range
  format (`PHYSHLTH`, cataloged only as 77, 88, and 99) says that
  ordinary in-range values are valid and are not listed, so a truncated
  code list cannot read as the whole value set. Cards carry codes and
  labels only, with no units, scale factor, or valid range; those live
  in CDC's codebook, named per year by `brfss_year_info()$codebook_url`.
  A cache-integrity failure while reading the rename crosswalk aborts,
  as it does everywhere else in the package, rather than quietly
  returning a card with no concept family. `brfss_year_info()` lists
  respondents, variables, states, hosted size, and CDC's documentation
  page per year. `brfss_citation()` returns per-year `bibentry`
  citations, each with a stable BibTeX key (`brfss2023` and the like,
  and `brfssdata` for the package), so `toBibtex()` output drops into a
  `.bib` file unedited.
* `brfss_labels()` and `brfss_crosswalk()` say so when only some
  requested variables match (`brfssdata_partial_match_note`), naming
  the ones with no entries, instead of silently returning rows for the
  rest. A miss can be legitimate (continuous variables have no label
  entries; most variables belong to no rename family), which is
  exactly why it deserves a note rather than silence: without one, a
  legitimate absence and a typo look identical.
  `brfss_missing_codes()` inherits the note.
* `brfss_citation(integer(0))` errors with `brfssdata_bad_years_arg`
  instead of returning a malformed, data-free citation list with no
  signal that nothing was cited.
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
* `read_brfss()` with no `vars` selection says it is loading every
  column before anything is read (`brfssdata_full_load_note`): a bare
  `read_brfss(2024)` materializes 302 columns and about 1.1 GB where a
  one-column projection is about 5 MB. The note names `vars = c(...)`
  as the remedy; it previously fired only from `brfss_design()`, which
  now inherits it from `read_brfss()`.
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
  documentation calls for it. Module analyses that require CDC's
  questionnaire-version datasets and their `_LCPWTV1` to `_LCPWTV3`
  final weights are not supported by the hosted annual files.
* By default, `brfss_design()` sets the codes CDC uses for don't-know,
  refused, and missing-type answers to `NA` (`na = TRUE`), so means and
  proportions cover substantive answers; `read_brfss()` defaults to
  `na = FALSE` and returns the file as published. The exported
  `brfss_missing_codes()` lists exactly which codes are affected.
* `brfss_design(weight = )` accepts CDC's final analysis weights only:
  `_FINALWT` (1985-2010) and `_LLCPWT` (2011 on) for the full sample,
  the domain weights `_CLLCPWT`, `_CHILDWT`, and `_HOUSEWT`, and the
  2007 questionnaire-version weights `_FINALQ1`, `_FINALQ2`,
  `_CHILDQ1`, and `_CHILDQ2`. Anything else, an intermediate pipeline
  stage or an arbitrary column, is a classed error
  (`brfssdata_unrecognized_weight`) unless `unsafe_weight = TRUE` says
  it is deliberate, and the override still warns. Previously only five
  modern intermediates drew a warning and everything else passed
  silently: the review built designs with `weight = "GENHLTH"` (female
  share shifted 1.8 points) and the 1985-2000 design weight `_WT1`
  (fair/poor health shifted 0.95 points) without a signal. Weight
  values must now be positive and finite, a final weight requested
  outside its published span fails before anything downloads, and an
  explicitly named full-sample weight obeys the same completeness rule
  as the automatic path: missing values abort as a damaged file
  instead of silently subsetting the design. All weight columns, final
  and intermediate, are excluded from labeling and `na` recoding on
  every path.
* `brfss_design()` detects the reverse weight mistake too: a requested
  variable whose answers sit almost entirely inside a module weight's
  records (95% or more in every requested year) while the design uses
  a full-sample weight draws a `brfssdata_module_weight_warning`
  naming the weight to consider. The live case: 2023 child asthma
  (`CASTHDX2`, 99.7% confined to `_CLLCPWT`'s records) under the
  default `_LLCPWT` estimated 10.86% against the correct 10.36%, with
  no signal. It warns rather than fails because state-optional modules
  that CDC assigns to the core weight produce the same confinement
  shape; `options(brfssdata.module_weight_check = FALSE)` disables it.
* `quiet = TRUE` governs progress and housekeeping output only:
  download progress, cache notes, the full-load hint, and the recode
  tally. Signals about what the data mean fire regardless of `quiet`:
  the rename note, the missing-code coverage signals, and the
  weight-domain subset note. Previously all three were suppressed by
  `quiet = TRUE`, which every article passed, so a
  `brfss_design(weight = "_CLLCPWT", quiet = TRUE)` call could
  silently estimate a different population. Requesting `na = TRUE`
  for years before 1998, where no value-label catalog exists, is now
  a classed warning (`brfssdata_na_coverage_warning`) rather than a
  message: nothing was cleared there, and a 1993 `PHYSHLTH` mean with
  the 77/99 codes left in is materially wrong. Silence any of these
  by class, e.g.
  `suppressMessages(..., classes = "brfssdata_rename_note")`.
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
* Cached survey years are re-verified against the manifest's checksums
  at most once a day per session, the same cadence the metadata
  catalogs already use. A cached file whose hash no longer matches is
  treated like a damaged one: announced (`brfssdata_cache_note`) and
  re-downloaded verified, with the old file kept until a verified
  replacement lands. Previously only file size was compared after the
  initial download, so a same-size corrupted copy was accepted without
  a condition. On that same path, a fully cached `read_brfss()` with
  `download = TRUE` now lets the manifest refresh on its daily
  cadence, so a user who cached a year before a corrected republish is
  told within a day; when the refresh fails (offline), the cached
  manifest is used with a `brfssdata_manifest_note` and the read
  proceeds as before. `download = FALSE` checks nothing, downloads
  nothing, and never deletes anything.
* `brfss_cache_info(verify = TRUE)` adds a `verified` column: `TRUE`
  when a cached file's sha256 matches the manifest entry, `FALSE` on a
  mismatch, `NA` where the manifest has no entry to compare against.
  Off by default because hashing reads every byte, roughly two seconds
  for the full 40-year, 737 MB cache, and `brfss_download()` lists the
  cache on every call.
* A cached manifest that is present but unreadable does not count as
  fresh. The manifest is the one asset fetched without an expected
  hash, and any non-empty payload is accepted, so a captive-portal or
  proxy error page served with HTTP 200 could otherwise sit in the
  cache looking new. For a day after that, `brfss_years()` would return
  `integer(0)` and every checksum lookup would return `NULL`, so
  downloads would proceed unverified. Freshness now reads the content,
  the bundled copy wins over an unusable cache with a
  `brfssdata_manifest_note` naming `brfss_years(refresh = TRUE)` as the
  repair, and a downloaded manifest reaches the cache only once its
  payload parses.
* A request whose `states` filter leaves no rows aborts with a classed
  `brfssdata_no_eligible_rows` error naming the states, years, and
  weight, instead of failing inside the survey package with "group
  length is 0 but data length > 0". Kentucky and Pennsylvania in 2023
  are the live cases. `read_brfss()` still returns the zero-row tibble,
  which is a usable answer where a zero-row design is not.
* Every error, warning, and message carries a documented condition
  class; see `?brfssdata-conditions`.

## Documentation

* The *Age-adjusted prevalence* article passes the outcome to
  `survey::svystandardize()`, as `excluding.missing = ~ fair_poor +
  age_group`. `svystandardize()` filters on `excluding.missing` before
  it calibrates, so naming only the age variable leaves the age weights
  calibrated over respondents that `na.rm = TRUE` discards afterwards,
  returning the age-group means weighted by standard share times
  weighted response rate instead of by standard share alone. The two
  agree only when item nonresponse is flat across age, which it is not.
  The recipe also labels the age factor from `brfss_std_pop_2000` and
  asserts the level order, because `svystandardize()` matches
  `population` to the levels of `by` by position without checking
  names. `brfss_std_pop_2000` now documents that ordering contract.
* The articles no longer call a whole-file estimate national. The 2023
  public-use file covers 52 reporting areas, 48 states plus the
  District of Columbia, Guam, Puerto Rico, and the U.S. Virgin Islands,
  with Kentucky and Pennsylvania absent.

## Known limitations

* Upstream provenance is not recorded yet: `brfss_year_info()` carries
  no CDC source URL, retrieval date, or hash of the upstream SAS
  Transport file, so the package cannot say which CDC revision of a
  year the hosted copy was built from. The published checksums cover
  the hosted copies. Provenance columns are planned for 0.1.1, which
  requires a data republish.
* Calculated variables keep CDC's stored scaling. `_BMI5` and
  `_DRNKWK2` carry two implied decimals (a stored 2704 in `_BMI5` is a
  BMI of 27.04), and neither the files nor the catalogs record scale
  factors, units, or valid ranges. Codebook cards say so and point to
  CDC's per-year codebook (`brfss_year_info()$codebook_url`). Curated
  scale metadata is 0.2.0 work.
* No value-label catalog exists before 1998, so `na = TRUE` has
  nothing to consult there and warns instead of guessing; special
  codes in 1985 to 1997 must be recoded by hand from CDC's codebooks.
  This is a deliberate policy of signaling over hand-curation.
* Module analyses that require CDC's questionnaire-version datasets
  and their `_LCPWTV1` to `_LCPWTV3` final weights are unsupported;
  the hosted annual files do not include those weights. The
  module-weight confinement check covers the reachable cases; curated
  module-to-weight metadata is 0.2.0 work.
* Data releases are not immutable snapshots. A corrected year replaces
  the published bytes under the same tag; the manifest checksum and
  the daily cache recheck notice the change, but an analysis cannot
  yet pin itself to an exact prior snapshot. Versioned snapshots are
  0.2.0 work.
