#' List the BRFSS survey years available for download
#'
#' @description
#' Reads the data manifest that accompanies the hosted parquet releases and
#' returns the survey years currently published. The manifest is cached
#' locally and refreshed at most once a day; pass `refresh = TRUE` to force
#' a new download.
#'
#' @param refresh If `TRUE`, re-download the manifest even if a fresh
#'   cached copy exists.
#'
#' @return An integer vector of available survey years. If the manifest
#'   cannot be refreshed, a message notes the fallback (cached or bundled
#'   copy) that was used instead.
#'
#' @examplesIf interactive()
#' brfss_years()
#' @export
brfss_years <- function(refresh = FALSE) {
  manifest <- read_manifest(refresh = refresh)
  sort(as.integer(manifest$years))
}

MANIFEST_MAX_AGE <- 60 * 60 * 24 # one day, in seconds

manifest_url <- function() release_url("data-meta", "manifest.json")

# Remembers a recent failed refresh so an offline session does not block
# on a fresh download attempt at every call.
manifest_state <- new.env(parent = emptyenv())

bundled_manifest_path <- function() {
  system.file("extdata", "manifest.json", package = "brfssdata")
}

read_manifest <- function(refresh = FALSE) {
  path <- cache_path("manifest.json")

  fresh <- file.exists(path) &&
    difftime(Sys.time(), file.mtime(path), units = "secs") < MANIFEST_MAX_AGE
  recently_failed <- !is.null(manifest_state$last_failure) &&
    difftime(Sys.time(), manifest_state$last_failure, units = "secs") <
      MANIFEST_MAX_AGE

  download_failed <- FALSE
  if (refresh || (!fresh && !recently_failed)) {
    ok <- tryCatch(
      {
        download_to_cache(manifest_url(), path, quiet = TRUE)
        TRUE
      },
      brfssdata_download_error = function(e) FALSE
    )
    if (ok) {
      manifest_state$last_failure <- NULL
    } else {
      manifest_state$last_failure <- Sys.time()
      download_failed <- TRUE
    }
  }

  if (download_failed) {
    fallback <- if (file.exists(path)) "a previously cached" else "the bundled"
    cli::cli_inform(
      c(
        "!" = "Could not refresh the BRFSS data manifest;
               using {fallback} copy."
      ),
      class = "brfssdata_manifest_note"
    )
  }

  if (!file.exists(path)) {
    path <- bundled_manifest_path()
  }
  if (identical(path, "") || !file.exists(path)) {
    return(list(years = integer(0)))
  }
  parse_manifest(path)
}

parse_manifest <- function(path) {
  out <- tryCatch(
    jsonlite::read_json(path, simplifyVector = TRUE),
    error = function(e) NULL
  )
  if (is.null(out) || is.null(out$years)) {
    return(list(years = integer(0)))
  }
  out$years <- as.integer(out$years)
  out
}
