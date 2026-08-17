# Conditions signaled by brfssdata

Every error, warning, and message this package signals carries a class,
so [`tryCatch()`](https://rdrr.io/r/base/conditions.html) and
[`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html) can
react to exactly the situation they mean to and nothing else, e.g.
`tryCatch(read_brfss(2023), brfssdata_download_error = \(e) NULL)` or
`suppressWarnings(..., classes = "brfssdata_break_warning")`.

`quiet = TRUE` never hides a signal about what the data mean; it
suppresses progress and housekeeping output only. To silence a specific
analytical note, suppress its class, e.g.
`suppressMessages(read_brfss(2021:2022, vars = "_DRNKWK1"), classes = "brfssdata_rename_note")`.

## Errors

- `brfssdata_bad_years_arg`:

  `years` is not a vector of whole survey years.

- `brfssdata_bad_year`:

  A requested year is not among the published releases.

- `brfssdata_no_data`:

  The data manifest could not be read or lists no published years.

- `brfssdata_bad_vars_arg`:

  `vars` is not a character vector of variable names.

- `brfssdata_bad_var`:

  A requested variable does not exist in the requested years.

- `brfssdata_bad_states_arg`:

  `states` is not a vector of FIPS codes, postal abbreviations, or
  jurisdiction names.

- `brfssdata_bad_state`:

  A value in `states` matches no BRFSS jurisdiction; see
  [brfss_states](https://muntasirmasum.github.io/brfssdata/reference/brfss_states.md).

- `brfssdata_bad_pattern`:

  `pattern` in
  [`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md)
  is not a valid regular expression.

- `brfssdata_bad_weight`:

  `weight` in
  [`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
  is malformed, requested outside the weight's published span, absent
  from a requested year, or carries values that are not positive and
  finite.

- `brfssdata_unrecognized_weight`:

  `weight` in
  [`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
  names a column that is not one of CDC's final analysis weights and
  `unsafe_weight = TRUE` was not set. Also carries
  `brfssdata_bad_weight`, so one handler catches every weight refusal.

- `brfssdata_bad_bool_arg`:

  A `TRUE`/`FALSE` argument received something else, `NA` included. Each
  flag also raises a class of its own on one pattern,
  `brfssdata_bad_<argument>_arg`: `na` raises `brfssdata_bad_na_arg`,
  and likewise for `download`, `quiet`, `refresh`, `verify`, `catalogs`,
  `allow_break`, `pool_weights`, and `unsafe_weight`. One handler on the
  shared class catches them all.

- `brfssdata_bad_labels_arg`:

  `labels` is something other than `TRUE`, `FALSE`, or `"both"`.

- `brfssdata_bad_n_arg`:

  `n` in `print.brfss_codebook()` is not a single positive number.

- `brfssdata_bad_option`:

  `options(brfssdata.lonely_psu)` is not a single string,
  `options(brfssdata.module_weight_check)` is not `TRUE` or `FALSE`, or
  `options(brfssdata.cache_dir)` is not a single non-empty path to a
  directory.

- `brfssdata_bad_design_var`:

  A design variable (era weight, `_STSTR`, `_PSU`) is absent or carries
  missing or invalid values, so no valid design can be built; for a
  final analysis weight this points at a damaged file.

- `brfssdata_no_eligible_rows`:

  No rows are left to build a survey design: a `states` filter, or the
  domain of a user-supplied `weight`, emptied the frame.
  [`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
  still returns the zero-row tibble, which is a usable answer; a
  zero-row survey design is not constructible.

- `brfssdata_break_error`:

  The requested years span the 2011 redesign and `allow_break = TRUE`
  was not set.

- `brfssdata_not_cached`:

  `download = FALSE` was set and the needed file is not in the cache.

- `brfssdata_download_error`:

  A download failed. Also the parent class of
  `brfssdata_checksum_error`, so one handler catches both.

- `brfssdata_checksum_error`:

  A downloaded file did not match the manifest's sha256 after a retry;
  nothing was cached.

- `brfssdata_cache_unwritable`:

  The cache directory could not be created, or exists but cannot be
  written to, so no download can land: a local permission problem, named
  as one instead of being reported as a network failure. Also carries
  `brfssdata_download_error`, so the metadata lookups' bundled fallback
  still applies.

- `brfssdata_corrupt_cache`:

  A cached file is unreadable (typically a corrupted download from
  before verification); the message names the file and the
  [`brfss_cache_clear()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
  remedy.

- `brfssdata_wrong_year_cache`:

  A cached file does not hold the survey year its name promises (a
  hand-copied or damaged cache); the message says what each such file
  really holds. Also carries `brfssdata_corrupt_cache`, so one handler
  covers both.

- `brfssdata_duckdb_version`:

  The installed duckdb is older than the version this package requires,
  so the argument that keeps DuckDB from writing to the home directory
  is unavailable; the message names the required and the found version.

- `brfssdata_type_conflict`:

  A requested column is stored as text in some requested years' files
  and as a number in others, so combining them would silently corrupt
  values; usually stale cached files mixed with current releases, with
  the
  [`brfss_cache_clear()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
  remedy named.

## Warnings

- `brfssdata_break_warning`:

  Pooling across the 2011 redesign with `allow_break = TRUE`.

- `brfssdata_intermediate_weight_warning`:

  `weight` in
  [`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
  names an intermediate stage of CDC's weighting pipeline (e.g.
  `_LLCPWT2`, the truncated pre-raking design weight), requested
  deliberately via `unsafe_weight = TRUE`.

- `brfssdata_unsafe_weight_warning`:

  `weight` in
  [`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md),
  requested via `unsafe_weight = TRUE`, names a column that is neither a
  final analysis weight nor a known pipeline stage; the estimates are
  calibrated to nothing.

- `brfssdata_module_weight_warning`:

  A requested analysis variable has data almost only where a module
  weight (`_CLLCPWT` and kin) is non-missing, but the design uses a
  full-sample weight: very likely a module analysis under the wrong
  weight. State-optional modules that CDC assigns to the core weight are
  the legitimate exception. Disable with
  `options(brfssdata.module_weight_check = FALSE)`.

- `brfssdata_pooled_states_warning`:

  Pooled years differ in state participation, so totals mix coverage.
  Participation is counted over the rows a user-supplied `weight`
  covers, the population the design actually estimates, not over the
  whole file.

- `brfssdata_empty_year_warning`:

  A requested year contributed no rows to a pooled design (a `states`
  filter, or the domain of a user-supplied `weight`, emptied it), so
  pooled weights divide by the contributing years only and totals
  estimate an average contributing year.

- `brfssdata_label_drift_warning`:

  Label wording for a variable changed meaning (not just formatting)
  across the requested years, so it kept CDC's numeric codes instead of
  converting to a factor; read the years separately if each year's own
  wording is wanted.

- `brfssdata_na_coverage_warning`:

  `na = TRUE` recoded nothing in a requested year, either because no
  value-label catalog exists for it (years before 1998) or because the
  catalog covers none of the loaded variables there: estimates over that
  year still contain CDC's don't-know and refused codes.

- `brfssdata_state_coverage_warning`:

  A jurisdiction requested via `states` is absent from a requested
  year's file, so estimates for that year cover the remaining states
  only.

## Messages

- `brfssdata_cache_note`:

  Cache lifecycle notes: directory created, files removed by
  [`brfss_cache_clear()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md),
  a size-mismatched or checksum-failing cached file re-downloaded, a
  stale catalog refreshed, or the
  [`brfss_download()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_download.md)
  summary.

- `brfssdata_download_note`:

  A survey year is being downloaded (once, then cached).

- `brfssdata_manifest_note`:

  The manifest or a catalog could not be refreshed; a cached or bundled
  copy was used.

- `brfssdata_lonely_psu_note`:

  The once-per-session note that `survey.lonely.psu` was set to
  `"adjust"`.

- `brfssdata_design_spec_note`:

  The specification of the design just built, stated the way a Stata log
  would (weight, strata, PSU term, pooling divisor; one `svyset` line
  per era weight when pooling crosses 2011), for cross-checking against
  a coauthor's `svyset`. Suppressed by `quiet = TRUE`.

- `brfssdata_unverified_note`:

  An asset was downloaded without checksum verification (the available
  manifest carries no hash for it).

- `brfssdata_na_note`:

  `na = TRUE` set missing-type codes to `NA`; the counts and the
  [`brfss_missing_codes()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_missing_codes.md)
  audit trail.

- `brfssdata_na_coverage_note`:

  `na = TRUE` was requested for a year the value-label catalog covers
  only partially (1998 covers under a quarter of its file's variables),
  so codes in the uncatalogued variables passed through unchanged. Years
  with no catalog at all raise `brfssdata_na_coverage_warning` instead.

- `brfssdata_weight_subset_note`:

  A user-supplied `weight` in
  [`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
  is missing on some rows (a module weight covers only its module's
  records); those rows were dropped, per CDC's module-analysis guidance.

- `brfssdata_empty_result`:

  A metadata lookup
  ([`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md),
  [`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md),
  [`brfss_crosswalk()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_crosswalk.md),
  [`brfss_year_info()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_year_info.md))
  matched nothing. From
  [`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md)
  the message also suggests near misses: close names and labels,
  order-blind multi-word matches, and matches confined to other years.

- `brfssdata_partial_match_note`:

  Some requested variables in
  [`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md)
  or
  [`brfss_crosswalk()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_crosswalk.md)
  matched nothing while others matched, so the returned rows cover the
  matching variables only. Absence can be legitimate: continuous
  variables have no label entries, and most variables belong to no
  rename family.

- `brfssdata_full_load_note`:

  [`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
  is loading every column because `vars` was not given;
  [`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
  passes `vars` through and inherits it.

- `brfssdata_rename_note`:

  A requested variable is empty in years a sibling generation from the
  rename crosswalk covers; see
  [`brfss_crosswalk()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_crosswalk.md).

- `brfssdata_case_match_note`:

  `vars` matched columns case-insensitively; the note pairs each
  requested spelling with the CDC-canonical column name the returned
  data actually use. Suppressed by `quiet = TRUE`.

- `brfssdata_duplicate_label_note`:

  `labels = TRUE` kept CDC's numeric codes for variables whose format
  gives several codes the same label, which a factor would merge into
  one level.

- `brfssdata_bundled_fallback_note`:

  A metadata lookup was served from the snapshot bundled with the
  package (frozen at release) because nothing newer was cached and no
  download was possible.
