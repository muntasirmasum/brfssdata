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

  read_manifest_cached()
}

# Parse the manifest without ever touching the network: the cached copy
# if present, the bundled fallback otherwise. The verification lookups on
# the read path use this so a fully cached request stays offline.
read_manifest_cached <- function() {
  path <- cache_path("manifest.json")
  if (!file.exists(path)) {
    path <- bundled_manifest_path()
  }
  if (identical(path, "") || !file.exists(path)) {
    return(empty_manifest())
  }
  parse_manifest(path)
}

empty_manifest <- function() {
  list(years = integer(0), schema_version = 1L, files = NULL)
}

# Normalizes both manifest schemas: v1 carries only `years`; v2 adds
# `schema_version` and a `files` map of per-asset sha256/size entries.
# Entries without a usable sha256 are dropped, so downstream code can
# treat "no entry" and "unusable entry" identically (unverified asset).
parse_manifest <- function(path) {
  out <- tryCatch(
    jsonlite::read_json(path, simplifyVector = TRUE),
    error = function(e) NULL
  )
  if (is.null(out) || is.null(out$years)) {
    return(empty_manifest())
  }
  out$years <- as.integer(out$years)

  version <- suppressWarnings(as.integer(out$schema_version))
  if (length(version) != 1L || is.na(version)) {
    version <- 1L
  }
  out$schema_version <- version

  files <- out$files
  if (!is.list(files) || is.null(names(files))) {
    files <- NULL
  } else {
    usable <- vapply(
      files,
      function(f) {
        is.list(f) &&
          is.character(f$sha256) &&
          length(f$sha256) == 1L &&
          !is.na(f$sha256) &&
          nzchar(f$sha256)
      },
      logical(1)
    )
    files <- files[usable]
    if (length(files) == 0) {
      files <- NULL
    }
  }
  out$files <- files
  out
}

# Catalog freshness memo, kept inside manifest_state so the test
# helpers' save/clear/restore scoping covers it automatically.
catalog_check_due <- function(asset) {
  checked <- manifest_state$catalog_checked[[asset]]
  is.null(checked) ||
    difftime(Sys.time(), checked, units = "secs") >= MANIFEST_MAX_AGE
}

catalog_checked <- function(asset) {
  memo <- manifest_state$catalog_checked %||% list()
  memo[[asset]] <- Sys.time()
  manifest_state$catalog_checked <- memo
  invisible()
}

manifest_sha256 <- function(asset, manifest = read_manifest_cached()) {
  entry <- manifest$files[[asset]]
  if (is.null(entry)) NULL else entry$sha256
}

manifest_size <- function(asset, manifest = read_manifest_cached()) {
  entry <- manifest$files[[asset]]
  size <- if (is.null(entry)) NULL else entry$size
  size <- suppressWarnings(as.numeric(size))
  if (length(size) != 1L || is.na(size)) NA_real_ else size
}
