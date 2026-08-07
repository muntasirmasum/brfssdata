# Conditions signaled by brfssdata

Every error, warning, and message this package signals carries a class,
so [`tryCatch()`](https://rdrr.io/r/base/conditions.html) and
[`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html) can
react to exactly the situation they mean to and nothing else, e.g.
`tryCatch(read_brfss(2023), brfssdata_download_error = \(e) NULL)` or
`suppressWarnings(..., classes = "brfssdata_break_warning")`.

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
  is malformed, or the column is absent from a requested year.

- `brfssdata_bad_labels_arg`:

  `labels` is something other than `TRUE`, `FALSE`, or `"both"`.

- `brfssdata_bad_na_arg`:

  `na` is not `TRUE` or `FALSE`.

- `brfssdata_bad_option`:

  `options(brfssdata.lonely_psu)` is not a single string.

- `brfssdata_bad_design_var`:

  A design variable (era weight, `_STSTR`, `_PSU`) is absent or carries
  missing values, so no valid design can be built.

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

- `brfssdata_corrupt_cache`:

  A cached file is unreadable (typically a corrupted download from
  before verification); the message names the file and the
  [`brfss_cache_clear()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
  remedy.

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
  `_LLCPWT2`, the truncated pre-raking design weight), not a final
  analysis weight.

- `brfssdata_pooled_states_warning`:

  Pooled years differ in state participation, so totals mix coverage.

- `brfssdata_label_drift_warning`:

  Label wording for a converted variable changed meaning (not just
  formatting) across the requested years; the newest wording was
  applied.

- `brfssdata_state_coverage_warning`:

  A jurisdiction requested via `states` is absent from a requested
  year's file, so estimates for that year cover the remaining states
  only.

## Messages

- `brfssdata_cache_note`:

  Cache lifecycle notes: directory created, files removed by
  [`brfss_cache_clear()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md),
  a size-mismatched file or stale catalog re-downloaded, or the
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

- `brfssdata_unverified_note`:

  An asset was downloaded without checksum verification (the available
  manifest carries no hash for it).

- `brfssdata_na_note`:

  `na = TRUE` set missing-type codes to `NA`; the counts and the
  [`brfss_missing_codes()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_missing_codes.md)
  audit trail.

- `brfssdata_na_coverage_note`:

  `na = TRUE` was requested for years the value-label catalog does not
  cover (before 1998) or covers only partially (1998), so codes there
  passed through unchanged.

- `brfssdata_weight_subset_note`:

  A user-supplied `weight` in
  [`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
  is missing on some rows (a module weight covers only its module's
  records); those rows were dropped, per CDC's module-analysis guidance.

- `brfssdata_empty_result`:

  A metadata lookup
  ([`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md),
  [`brfss_crosswalk()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_crosswalk.md),
  [`brfss_year_info()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_year_info.md))
  matched nothing.

- `brfssdata_full_load_note`:

  [`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
  is loading every column because `vars` was not given.

- `brfssdata_rename_note`:

  A requested variable is empty in years a sibling generation from the
  rename crosswalk covers; see
  [`brfss_crosswalk()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_crosswalk.md).

- `brfssdata_bundled_fallback_note`:

  A metadata lookup was served from the snapshot bundled with the
  package (frozen at release) because nothing newer was cached and no
  download was possible.
