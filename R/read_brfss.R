#' Read BRFSS survey microdata
#'
#' @description
#' Returns respondent-level BRFSS data for one or more survey years as a
#' tibble. Each requested year is downloaded once into the local cache
#' (see [brfss_cache_dir()]) and read from there afterwards; the query
#' itself runs through DuckDB, so selecting a handful of variables from a
#' 300-plus column survey stays fast.
#'
#' Different survey years carry different variable sets. When years are
#' combined, variables absent from a year are filled with `NA`. A `year`
#' column always identifies the survey year of each row.
#'
#' @param years Integer vector of survey years, e.g. `2023` or
#'   `2019:2023`. See [brfss_years()] for what is available.
#' @param vars Optional character vector of variable names to return.
#'   The default returns every variable. Names are matched
#'   case-insensitively (`"genhlth"` finds `GENHLTH`), and returned
#'   columns always carry CDC's canonical spelling. Use [brfss_vars()]
#'   to search names across years.
#' @param download If `FALSE`, only cached years are used and missing
#'   years raise an error instead of being downloaded.
#' @param quiet If `TRUE`, suppress download progress output.
#' @param labels If `TRUE`, convert variables with safe value-label maps
#'   to factors using CDC's format libraries (available from 1998 on).
#'   A variable converts only when its format is a pure code-to-label
#'   map, its code set agrees across the requested years, and every
#'   observed value is covered; everything else keeps its numeric codes.
#'   See [brfss_labels()] for the raw catalog.
#'
#' @return A tibble with one row per respondent and a `year` column.
#'
#' @examplesIf interactive()
#' # General health and design variables for two years
#' dat <- read_brfss(2022:2023, vars = c("GENHLTH", "_LLCPWT"))
#' @seealso [brfss_design()] to get a survey-design object instead of a
#'   plain tibble.
#' @export
read_brfss <- function(
  years,
  vars = NULL,
  download = TRUE,
  quiet = FALSE,
  labels = FALSE
) {
  years <- validate_years(years, download = download)
  if (!is.null(vars) && (!is.character(vars) || anyNA(vars))) {
    cli::cli_abort(
      "{.arg vars} must be a character vector of variable names.",
      class = "brfssdata_bad_vars_arg"
    )
  }
  paths <- ensure_years_cached(years, download = download, quiet = quiet)
  dat <- query_parquet(paths, vars = vars)
  if (isTRUE(labels)) {
    dat <- apply_labels(dat, years, quiet = quiet)
  }
  dat
}

ensure_years_cached <- function(
  years,
  download = TRUE,
  quiet = FALSE,
  call = rlang::caller_env()
) {
  paths <- cache_path(year_asset(years))
  missing <- years[!file.exists(paths)]

  if (length(missing) > 0 && !download) {
    cli::cli_abort(
      c(
        "Year{?s} {missing} {?is/are} not in the local cache and
         {.code download = FALSE} was set.",
        "i" = "Cached years: see {.fun brfss_cache_info}."
      ),
      class = "brfssdata_not_cached",
      call = call
    )
  }

  for (year in missing) {
    if (!quiet) {
      cli::cli_inform("Downloading BRFSS {year} (one-time, then cached).")
    }
    download_to_cache(
      year_url(year),
      cache_path(year_asset(year)),
      quiet = quiet,
      call = call
    )
  }
  paths
}
