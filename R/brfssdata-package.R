#' @keywords internal
#'
#' @section Getting started:
#' [read_brfss()] downloads a survey year once, caches it, and reads the
#' columns you name into a tibble. [brfss_design()] returns the same
#' extract as an srvyr survey design with the year's own weight,
#' strata, and PSU already set, which is what prevalence estimates and
#' their intervals need.
#'
#' To find out what to ask for, [brfss_vars()] searches variable names
#' and labels across years, [brfss_codebook()] prints what the catalogs
#' know about a variable, and [brfss_crosswalk()] follows CDC's renames
#' across generations. [brfss_labels()] and [brfss_missing_codes()] are
#' the value-label and missing-code tables behind the `labels` and `na`
#' arguments of the two read paths.
#'
#' [brfss_years()], [brfss_year_info()], and [brfss_download()] cover
#' what is published and what is cached; [brfss_cache_dir()],
#' [brfss_cache_info()], and [brfss_cache_clear()] manage the cache
#' itself, and [brfss_citation()] cites the years you used.
#' [brfssdata-conditions] lists the class of every error, warning, and
#' message the package signals.
"_PACKAGE"

## usethis namespace: start
#' @importFrom rlang %||%
## usethis namespace: end
NULL

# Columns created inside brfss_design() and referenced via srvyr's
# data-masking interface, plus the lazy-loaded package dataset that
# resolve_states() and warn_state_coverage() consult.
utils::globalVariables(c("brfss_psu", "brfss_strata", "brfss_wt", "brfss_states"))
