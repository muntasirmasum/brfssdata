#' Conditions signaled by brfssdata
#'
#' @description
#' Every error, warning, and message this package signals carries a
#' class, so `tryCatch()` and `withCallingHandlers()` can react to
#' exactly the situation they mean to and nothing else, e.g.
#' `tryCatch(read_brfss(2023), brfssdata_download_error = \(e) NULL)` or
#' `suppressWarnings(..., classes = "brfssdata_break_warning")`.
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
#'   \item{`brfssdata_bad_pattern`}{`pattern` in [brfss_vars()] is not a
#'     valid regular expression.}
#'   \item{`brfssdata_bad_weight`}{`weight` in [brfss_design()] is
#'     malformed, or the column is absent from a requested year.}
#'   \item{`brfssdata_bad_labels_arg`}{`labels` is something other than
#'     `TRUE`, `FALSE`, or `"both"`.}
#'   \item{`brfssdata_bad_na_arg`}{`na` is not `TRUE` or `FALSE`.}
#'   \item{`brfssdata_bad_option`}{`options(brfssdata.lonely_psu)` is
#'     not a single string.}
#'   \item{`brfssdata_bad_design_var`}{A design variable (era weight,
#'     `_STSTR`, `_PSU`) is absent or carries missing values, so no
#'     valid design can be built.}
#'   \item{`brfssdata_break_error`}{The requested years span the 2011
#'     redesign and `allow_break = TRUE` was not set.}
#'   \item{`brfssdata_not_cached`}{`download = FALSE` was set and the
#'     needed file is not in the cache.}
#'   \item{`brfssdata_download_error`}{A download failed. Also the
#'     parent class of `brfssdata_checksum_error`, so one handler
#'     catches both.}
#'   \item{`brfssdata_checksum_error`}{A downloaded file did not match
#'     the manifest's sha256 after a retry; nothing was cached.}
#'   \item{`brfssdata_corrupt_cache`}{A cached file is unreadable
#'     (typically a corrupted download from before verification); the
#'     message names the file and the [brfss_cache_clear()] remedy.}
#' }
#'
#' @section Warnings:
#' \describe{
#'   \item{`brfssdata_break_warning`}{Pooling across the 2011 redesign
#'     with `allow_break = TRUE`.}
#'   \item{`brfssdata_intermediate_weight_warning`}{`weight` in
#'     [brfss_design()] names an intermediate stage of CDC's weighting
#'     pipeline (e.g. `_LLCPWT2`, the truncated pre-raking design
#'     weight), not a final analysis weight.}
#'   \item{`brfssdata_pooled_states_warning`}{Pooled years differ in
#'     state participation, so totals mix coverage.}
#'   \item{`brfssdata_label_drift_warning`}{Label wording for a
#'     converted variable changed meaning (not just formatting) across
#'     the requested years; the newest wording was applied.}
#' }
#'
#' @section Messages:
#' \describe{
#'   \item{`brfssdata_cache_note`}{Cache lifecycle notes: directory
#'     created, files removed by [brfss_cache_clear()], a
#'     size-mismatched file or stale catalog re-downloaded, or the
#'     [brfss_download()] summary.}
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
#'   \item{`brfssdata_empty_result`}{A [brfss_labels()] lookup matched
#'     nothing.}
#'   \item{`brfssdata_full_load_note`}{[brfss_design()] is loading every
#'     column because `vars` was not given.}
#' }
#'
#' @name brfssdata-conditions
#' @keywords internal
NULL
