#' One row per published BRFSS survey year
#'
#' @description
#' The year inventory that accompanies the data releases: respondent
#' and variable counts, the number of reporting jurisdictions, the
#' hosted file's size in bytes, and the CDC documentation page for the
#' year, plus a locally computed `cached` flag saying whether the year
#' is already in [brfss_cache_dir()]. Use it to see the collection at a
#' glance before downloading anything; [brfss_years()] remains the
#' plain integer vector of published years.
#'
#' @param years Optional integer vector restricting to those years.
#' @inheritParams brfss_labels
#'
#' @return A tibble with columns `year`, `respondents`, `variables`,
#'   `states` (reporting jurisdictions in the file), `size` (bytes of
#'   the hosted parquet), `codebook_url` (CDC's documentation page for
#'   the year), and `cached` (logical, computed locally).
#'
#' @examplesIf interactive()
#' brfss_year_info(2019:2023)
#' @seealso [brfss_years()]; the *datasets* article for the same
#'   numbers in prose.
#' @export
brfss_year_info <- function(years = NULL, download = TRUE, quiet = TRUE) {
  if (!is.null(years)) {
    years <- check_years_arg(years)
  }
  info <- read_catalog(
    "brfss_year_info.parquet",
    what = "year inventory",
    download = download,
    quiet = quiet
  )
  if (!is.null(years)) {
    info <- info[info$year %in% years, , drop = FALSE]
    missing <- setdiff(years, info$year)
    if (length(missing) > 0) {
      cli::cli_inform(
        c(
          "No inventory entry for year{?s}
           {.val {as.character(missing)}}.",
          "i" = "Published years: see {.fun brfss_years}."
        ),
        class = "brfssdata_empty_result"
      )
    }
  }
  info$cached <- file.exists(cache_path(year_asset(info$year)))
  info
}
