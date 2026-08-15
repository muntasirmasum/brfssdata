#' Conditions signaled by brfssdata
#'
#' @description
#' Every error, warning, and message this package signals carries a
#' class, so `tryCatch()` and `withCallingHandlers()` can react to
#' exactly the situation they mean to and nothing else, e.g.
#' `tryCatch(read_brfss(2023), brfssdata_download_error = \(e) NULL)` or
#' `suppressWarnings(..., classes = "brfssdata_break_warning")`.
#'
#' `quiet = TRUE` never hides a signal about what the data mean; it
#' suppresses progress and housekeeping output only. To silence a
#' specific analytical note, suppress its class, e.g.
#' `suppressMessages(read_brfss(2021:2022, vars = "_DRNKWK1"),
#' classes = "brfssdata_rename_note")`.
#'
#' @section Errors:
#' \describe{
#'   \item{`brfssdata_bad_years_arg`}{`years` is not a vector of whole
#'     survey years.}
#'   \item{`brfssdata_bad_year`}{A requested year is not among the
#'     published releases.}
#'   \item{`brfssdata_no_data`}{The data manifest could not be read or
#'     lists no published years.}
#'   \item{`brfssdata_bad_vars_arg`}{`vars` is not a character vector
#'     of variable names.}
#'   \item{`brfssdata_bad_var`}{A requested variable does not exist in
#'     the requested years.}
#'   \item{`brfssdata_bad_states_arg`}{`states` is not a vector of
#'     FIPS codes, postal abbreviations, or jurisdiction names.}
#'   \item{`brfssdata_bad_state`}{A value in `states` matches no BRFSS
#'     jurisdiction; see [brfss_states].}
#'   \item{`brfssdata_bad_pattern`}{`pattern` in [brfss_vars()] is not a
#'     valid regular expression.}
#'   \item{`brfssdata_bad_weight`}{`weight` in [brfss_design()] is
#'     malformed, requested outside the weight's published span, absent
#'     from a requested year, or carries values that are not positive
#'     and finite.}
#'   \item{`brfssdata_unrecognized_weight`}{`weight` in [brfss_design()]
#'     names a column that is not one of CDC's final analysis weights
#'     and `unsafe_weight = TRUE` was not set. Also carries
#'     `brfssdata_bad_weight`, so one handler catches every weight
#'     refusal.}
#'   \item{`brfssdata_bad_unsafe_weight_arg`}{`unsafe_weight` is not
#'     `TRUE` or `FALSE`.}
#'   \item{`brfssdata_bad_labels_arg`}{`labels` is something other than
#'     `TRUE`, `FALSE`, or `"both"`.}
#'   \item{`brfssdata_bad_na_arg`}{`na` is not `TRUE` or `FALSE`.}
#'   \item{`brfssdata_bad_n_arg`}{`n` in `print.brfss_codebook()` is not
#'     a single positive number.}
#'   \item{`brfssdata_bad_option`}{`options(brfssdata.lonely_psu)` is
#'     not a single string, `options(brfssdata.module_weight_check)`
#'     is not `TRUE` or `FALSE`, or `options(brfssdata.cache_dir)` is
#'     not a single non-empty path to a directory.}
#'   \item{`brfssdata_bad_design_var`}{A design variable (era weight,
#'     `_STSTR`, `_PSU`) is absent or carries missing or invalid
#'     values, so no valid design can be built; for a final analysis
#'     weight this points at a damaged file.}
#'   \item{`brfssdata_no_eligible_rows`}{No rows are left to build a
#'     survey design: a `states` filter, or the domain of a
#'     user-supplied `weight`, emptied the frame. [read_brfss()] still
#'     returns the zero-row tibble, which is a usable answer; a
#'     zero-row survey design is not constructible.}
#'   \item{`brfssdata_break_error`}{The requested years span the 2011
#'     redesign and `allow_break = TRUE` was not set.}
#'   \item{`brfssdata_not_cached`}{`download = FALSE` was set and the
#'     needed file is not in the cache.}
#'   \item{`brfssdata_download_error`}{A download failed. Also the
#'     parent class of `brfssdata_checksum_error`, so one handler
#'     catches both.}
#'   \item{`brfssdata_checksum_error`}{A downloaded file did not match
#'     the manifest's sha256 after a retry; nothing was cached.}
#'   \item{`brfssdata_cache_unwritable`}{The cache directory could not
#'     be created, or exists but cannot be written to, so no download
#'     can land: a local permission problem, named as one instead of
#'     being reported as a network failure. Also carries
#'     `brfssdata_download_error`, so the metadata lookups' bundled
#'     fallback still applies.}
#'   \item{`brfssdata_corrupt_cache`}{A cached file is unreadable
#'     (typically a corrupted download from before verification); the
#'     message names the file and the [brfss_cache_clear()] remedy.}
#'   \item{`brfssdata_duckdb_version`}{The installed duckdb is older
#'     than the version this package requires, so the argument that
#'     keeps DuckDB from writing to the home directory is unavailable;
#'     the message names the required and the found version.}
#'   \item{`brfssdata_type_conflict`}{A requested column is stored as
#'     text in some requested years' files and as a number in others,
#'     so combining them would silently corrupt values; usually stale
#'     cached files mixed with current releases, with the
#'     [brfss_cache_clear()] remedy named.}
#' }
#'
#' @section Warnings:
#' \describe{
#'   \item{`brfssdata_break_warning`}{Pooling across the 2011 redesign
#'     with `allow_break = TRUE`.}
#'   \item{`brfssdata_intermediate_weight_warning`}{`weight` in
#'     [brfss_design()] names an intermediate stage of CDC's weighting
#'     pipeline (e.g. `_LLCPWT2`, the truncated pre-raking design
#'     weight), requested deliberately via `unsafe_weight = TRUE`.}
#'   \item{`brfssdata_unsafe_weight_warning`}{`weight` in
#'     [brfss_design()], requested via `unsafe_weight = TRUE`, names a
#'     column that is neither a final analysis weight nor a known
#'     pipeline stage; the estimates are calibrated to nothing.}
#'   \item{`brfssdata_module_weight_warning`}{A requested analysis
#'     variable has data almost only where a module weight
#'     (`_CLLCPWT` and kin) is non-missing, but the design uses a
#'     full-sample weight: very likely a module analysis under the
#'     wrong weight. State-optional modules that CDC assigns to the
#'     core weight are the legitimate exception. Disable with
#'     `options(brfssdata.module_weight_check = FALSE)`.}
#'   \item{`brfssdata_pooled_states_warning`}{Pooled years differ in
#'     state participation, so totals mix coverage. Participation is
#'     counted over the rows a user-supplied `weight` covers, the
#'     population the design actually estimates, not over the whole
#'     file.}
#'   \item{`brfssdata_label_drift_warning`}{Label wording for a
#'     variable changed meaning (not just formatting) across the
#'     requested years, so it kept CDC's numeric codes instead of
#'     converting to a factor; read the years separately if each
#'     year's own wording is wanted.}
#'   \item{`brfssdata_na_coverage_warning`}{`na = TRUE` was requested
#'     for years before 1998, where no value-label catalog exists at
#'     all, so no missing-type code was cleared there: estimates over
#'     those years still contain CDC's don't-know and refused codes.}
#'   \item{`brfssdata_state_coverage_warning`}{A jurisdiction requested
#'     via `states` is absent from a requested year's file, so
#'     estimates for that year cover the remaining states only.}
#' }
#'
#' @section Messages:
#' \describe{
#'   \item{`brfssdata_cache_note`}{Cache lifecycle notes: directory
#'     created, files removed by [brfss_cache_clear()], a
#'     size-mismatched or checksum-failing cached file re-downloaded,
#'     a stale catalog refreshed, or the [brfss_download()] summary.}
#'   \item{`brfssdata_download_note`}{A survey year is being downloaded
#'     (once, then cached).}
#'   \item{`brfssdata_manifest_note`}{The manifest or a catalog could
#'     not be refreshed; a cached or bundled copy was used.}
#'   \item{`brfssdata_lonely_psu_note`}{The once-per-session note that
#'     `survey.lonely.psu` was set to `"adjust"`.}
#'   \item{`brfssdata_unverified_note`}{An asset was downloaded without
#'     checksum verification (the available manifest carries no hash
#'     for it).}
#'   \item{`brfssdata_na_note`}{`na = TRUE` set missing-type codes to
#'     `NA`; the counts and the [brfss_missing_codes()] audit trail.}
#'   \item{`brfssdata_na_coverage_note`}{`na = TRUE` was requested for
#'     a year the value-label catalog covers only partially (1998
#'     covers under a quarter of its file's variables), so codes in the
#'     uncatalogued variables passed through unchanged. Years with no
#'     catalog at all raise `brfssdata_na_coverage_warning` instead.}
#'   \item{`brfssdata_weight_subset_note`}{A user-supplied `weight` in
#'     [brfss_design()] is missing on some rows (a module weight covers
#'     only its module's records); those rows were dropped, per CDC's
#'     module-analysis guidance.}
#'   \item{`brfssdata_empty_result`}{A metadata lookup
#'     ([brfss_vars()], [brfss_labels()], [brfss_crosswalk()],
#'     [brfss_year_info()]) matched nothing. From [brfss_vars()] the
#'     message also suggests near misses: close names and labels,
#'     order-blind multi-word matches, and matches confined to other
#'     years.}
#'   \item{`brfssdata_partial_match_note`}{Some requested variables in
#'     [brfss_labels()] or [brfss_crosswalk()] matched nothing while
#'     others matched, so the returned rows cover the matching
#'     variables only. Absence can be legitimate: continuous variables
#'     have no label entries, and most variables belong to no rename
#'     family.}
#'   \item{`brfssdata_full_load_note`}{[read_brfss()] is loading every
#'     column because `vars` was not given; [brfss_design()] passes
#'     `vars` through and inherits it.}
#'   \item{`brfssdata_rename_note`}{A requested variable is empty in
#'     years a sibling generation from the rename crosswalk covers;
#'     see [brfss_crosswalk()].}
#'   \item{`brfssdata_bundled_fallback_note`}{A metadata lookup was
#'     served from the snapshot bundled with the package (frozen at
#'     release) because nothing newer was cached and no download was
#'     possible.}
#' }
#'
#' @name brfssdata-conditions
#' @keywords internal
NULL
