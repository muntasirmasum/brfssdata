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
#'   cannot be refreshed, or the cached copy is unreadable, a message
#'   notes the fallback (cached or bundled copy) that was used instead.
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

# Freshness is about content, not presence. The manifest is the one asset
# fetched without an expected hash (it cannot verify itself) and
# download_to_cache() accepts any non-empty payload, so a captive portal
# or proxy error page served with HTTP 200 lands in the cache looking
# perfectly fresh. Counting that as usable would empty brfss_years() and,
# worse, blank every manifest_sha256() lookup, so all later downloads
# would proceed unverified for a day.
#
# Usable means the bytes still parse as the JSON object a manifest is:
# an HTML sign-in page, a truncated transfer, and an API error body such
# as {"message": "Not Found"} all fail. A manifest that parses but lists
# no years is a different thing, a real statement that nothing is
# published, and keeps its own error (`brfssdata_no_data`) rather than
# being papered over with the bundled copy.
manifest_usable <- function(path) {
  parsed <- manifest_json(path)
  is.list(parsed) && !is.null(parsed$years)
}

# Raw JSON parse memo: NULL for an unparseable file, the jsonlite result
# otherwise, keyed by path plus mtime and size so a replaced file (the
# staged-rename in refresh_manifest(), a repaired cache) re-parses on its
# next use. A missing file returns NULL without memoizing. One
# read_manifest() call previously parsed the same bytes up to three
# times (freshness check, fallback check, parse_manifest); the memo
# makes it one. Lives in manifest_state, which the test fixtures'
# save/clear/restore scoping already covers.
manifest_json <- function(path) {
  info <- file.info(path, extra_cols = FALSE)
  if (is.na(info$size)) {
    return(NULL)
  }
  key <- tryCatch(
    normalizePath(path, mustWork = FALSE),
    error = function(e) path
  )
  stamp <- c(as.numeric(info$mtime), as.numeric(info$size))
  memo <- manifest_state$json_memo %||% list()
  hit <- memo[[key]]
  if (!is.null(hit) && !anyNA(stamp) && identical(hit$stamp, stamp)) {
    return(hit$value)
  }
  value <- tryCatch(
    jsonlite::read_json(path, simplifyVector = TRUE),
    error = function(e) NULL
  )
  if (!anyNA(stamp)) {
    # list() storage keeps a memoized NULL (unparseable file) distinct
    # from "no entry".
    memo[[key]] <- list(stamp = stamp, value = value)
    manifest_state$json_memo <- memo
  }
  value
}

read_manifest <- function(refresh = FALSE) {
  path <- cache_path("manifest.json")

  fresh <- manifest_usable(path) &&
    difftime(Sys.time(), file.mtime(path), units = "secs") < MANIFEST_MAX_AGE
  recently_failed <- !is.null(manifest_state$last_failure) &&
    difftime(Sys.time(), manifest_state$last_failure, units = "secs") <
      MANIFEST_MAX_AGE

  download_failed <- FALSE
  if (refresh || (!fresh && !recently_failed)) {
    ok <- tryCatch(
      refresh_manifest(path),
      brfssdata_download_error = function(e) FALSE
    )
    if (ok) {
      manifest_state$last_failure <- NULL
      manifest_state$unusable_noted <- NULL
    } else {
      manifest_state$last_failure <- Sys.time()
      download_failed <- TRUE
    }
  }

  if (download_failed) {
    fallback <- if (manifest_usable(path)) {
      "a previously cached"
    } else {
      "the bundled"
    }
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

# Download into a staging file inside the cache directory and promote it
# only once it parses. A payload that is not a manifest is treated as a
# failed refresh, so a good cached copy survives an error page and the
# daily failure memo keeps the next call from retrying immediately.
refresh_manifest <- function(path) {
  ensure_cache_dir()
  staged <- tempfile(
    pattern = "manifest-",
    tmpdir = dirname(path),
    fileext = ".json"
  )
  on.exit(unlink(staged), add = TRUE)
  download_to_cache(manifest_url(), staged, quiet = TRUE)
  if (!manifest_usable(staged)) {
    return(FALSE)
  }
  isTRUE(file.rename(staged, path)) ||
    isTRUE(file.copy(staged, path, overwrite = TRUE))
}

# Parse the manifest without ever touching the network: the cached copy
# if present, the bundled fallback otherwise. The verification lookups on
# the read path use this so a fully cached request stays offline.
read_manifest_cached <- function() {
  path <- cache_path("manifest.json")
  if (!manifest_usable(path)) {
    if (file.exists(path)) {
      note_unusable_manifest()
    }
    path <- bundled_manifest_path()
  }
  if (identical(path, "") || !file.exists(path)) {
    return(empty_manifest())
  }
  parse_manifest(path)
}

# Once per session: read_manifest_cached() sits on the verification path
# of every download, so an unreadable cache file would otherwise repeat
# this several times per call. The memo lives in manifest_state, which
# the test fixtures already save and restore, and a successful refresh
# clears it.
note_unusable_manifest <- function() {
  if (isTRUE(manifest_state$unusable_noted)) {
    return(invisible())
  }
  manifest_state$unusable_noted <- TRUE
  cli::cli_inform(
    c(
      "!" = "The cached BRFSS data manifest is unreadable; using the
             bundled copy.",
      "i" = "Repair it with {.code brfss_years(refresh = TRUE)}."
    ),
    class = "brfssdata_manifest_note"
  )
}

empty_manifest <- function() {
  list(years = integer(0), schema_version = 1L, files = NULL)
}

# Normalizes both manifest schemas: v1 carries only `years`; v2 adds
# `schema_version` and a `files` map of per-asset sha256/size entries.
# Entries without a usable sha256 are dropped, so downstream code can
# treat "no entry" and "unusable entry" identically (unverified asset).
parse_manifest <- function(path) {
  out <- manifest_json(path)
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

# Per-asset freshness memo, shared by the metadata catalogs and the
# cached year files, kept inside manifest_state so the test helpers'
# save/clear/restore scoping covers it automatically. In-memory, so
# "daily" means at most once per day per R session.
asset_check_due <- function(asset) {
  checked <- manifest_state$asset_checked[[asset]]
  is.null(checked) ||
    difftime(Sys.time(), checked, units = "secs") >= MANIFEST_MAX_AGE
}

asset_checked <- function(asset) {
  memo <- manifest_state$asset_checked %||% list()
  memo[[asset]] <- Sys.time()
  manifest_state$asset_checked <- memo
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
