#' Manage the local BRFSS data cache
#'
#' @description
#' Downloaded survey years are stored as parquet files in a per-user cache
#' directory so repeat use, and offline work, never re-download. The cache
#' location follows [tools::R_user_dir()] and can be redirected with
#' `options(brfssdata.cache_dir = ...)` or the `R_USER_CACHE_DIR`
#' environment variable.
#'
#' * `brfss_cache_dir()` returns the cache directory path.
#' * `brfss_cache_info()` lists cached files with their sizes. Rows with
#'   `year = NA` are the metadata files (the manifest and the variable
#'   and label catalogs), not survey years.
#' * `brfss_cache_clear()` deletes cached survey years, all of them by
#'   default, and reports what it removed. The manifest and catalogs are
#'   kept unless `catalogs = TRUE`, so offline use of [brfss_vars()] and
#'   [brfss_labels()] survives a data-cache clear.
#'
#' @param years Optional integer vector. If supplied to
#'   `brfss_cache_clear()`, only those survey years are removed;
#'   `integer(0)` removes none (useful with `catalogs = TRUE`).
#' @param catalogs If `TRUE`, `brfss_cache_clear()` also removes the
#'   manifest and the variable and label catalogs.
#'
#' @return
#' `brfss_cache_dir()` returns a path (character). `brfss_cache_info()`
#' returns a tibble with columns `file`, `year`, and `size` (bytes).
#' `brfss_cache_clear()` returns, invisibly, the paths it removed.
#'
#' @examples
#' brfss_cache_dir()
#' brfss_cache_info()
#' @export
brfss_cache_dir <- function() {
  getOption("brfssdata.cache_dir") %||%
    tools::R_user_dir("brfssdata", "cache")
}

#' @rdname brfss_cache_dir
#' @export
brfss_cache_info <- function() {
  dir <- brfss_cache_dir()
  files <- list.files(dir, full.names = TRUE)
  info <- file.info(files)
  tibble::tibble(
    file = basename(files),
    year = cached_file_year(basename(files)),
    size = info$size
  )
}

CACHE_META_FILES <- c(
  "manifest.json",
  "brfss_variables.parquet",
  "brfss_labels.parquet"
)

#' Prefetch BRFSS data and metadata into the local cache
#'
#' @description
#' Downloads the requested survey years, and by default also the data
#' manifest and the variable and label catalogs, so that everything
#' works offline afterwards: [read_brfss()], [brfss_design()],
#' [brfss_vars()], [brfss_labels()], and `labels`/`na` conversion all
#' run from the cache. Use it to populate the cache once on a connected
#' machine (the directory from [brfss_cache_dir()] can then be copied to
#' an air-gapped one), or to pre-download years ahead of a workshop.
#' Files already cached and current are not re-downloaded.
#'
#' @param years Optional integer vector of survey years to cache.
#'   `NULL` fetches only the metadata.
#' @param catalogs If `TRUE` (the default), also cache the manifest and
#'   the variable and label catalogs.
#' @param quiet If `TRUE`, suppress download progress and the summary.
#'
#' @return Invisibly, the [brfss_cache_info()] tibble after the fetch.
#'
#' @examplesIf interactive()
#' brfss_download(2019:2023)
#' @export
brfss_download <- function(years = NULL, catalogs = TRUE, quiet = FALSE) {
  if (!is.null(years)) {
    years <- validate_years(years)
    ensure_years_cached(years, download = TRUE, quiet = quiet)
  }
  if (isTRUE(catalogs)) {
    read_manifest()
    ensure_catalog_cached(
      "brfss_variables.parquet",
      what = "variable catalog",
      quiet = quiet
    )
    ensure_catalog_cached(
      "brfss_labels.parquet",
      what = "label catalog",
      quiet = quiet
    )
  }
  info <- brfss_cache_info()
  if (!quiet) {
    cli::cli_inform(
      "Cache at {.path {brfss_cache_dir()}}: {sum(!is.na(info$year))}
       year{?s}, {format(structure(sum(info$size, na.rm = TRUE),
       class = 'object_size'), units = 'auto')}."
    )
  }
  invisible(info)
}

#' @rdname brfss_cache_dir
#' @export
brfss_cache_clear <- function(years = NULL, catalogs = FALSE) {
  dir <- brfss_cache_dir()
  files <- list.files(dir, full.names = TRUE)
  file_year <- cached_file_year(basename(files))

  # Only files this package wrote are ever deleted: year assets matching
  # the requested years, plus the metadata files when asked. A foreign
  # file that happens to sit in the cache directory is never touched.
  is_year <- !is.na(file_year)
  if (!is.null(years)) {
    is_year <- is_year & file_year %in% as.integer(years)
  }
  is_meta <- isTRUE(catalogs) & basename(files) %in% CACHE_META_FILES
  files <- files[is_year | is_meta]

  removed_bytes <- sum(file.info(files)$size, na.rm = TRUE)
  unlink(files)
  if (length(files) == 0) {
    cli::cli_inform(
      "Nothing to remove from {.path {dir}}.",
      class = "brfssdata_cache_note"
    )
  } else {
    cli::cli_inform(
      "Removed {length(files)} file{?s}
       ({format(structure(removed_bytes, class = 'object_size'),
                units = 'auto')}) from {.path {dir}}.",
      class = "brfssdata_cache_note"
    )
  }
  invisible(files)
}

cached_file_year <- function(file) {
  # Anchored to the asset name this package writes, so an unrelated file
  # that merely contains four digits is never mistaken for a data year
  # (and so never deleted by brfss_cache_clear(years = ...)).
  m <- regmatches(file, regexec("^brfss_([0-9]{4})\\.parquet$", file))
  vapply(
    m,
    function(x) if (length(x) == 2L) as.integer(x[[2]]) else NA_integer_,
    integer(1)
  )
}

# curl is a Suggests, so the downloader is chosen at call time. Kept as
# its own function so tests can exercise the base R branch on a machine
# that has curl installed.
has_curl <- function() {
  requireNamespace("curl", quietly = TRUE)
}

cache_path <- function(asset) {
  file.path(brfss_cache_dir(), asset)
}

ensure_cache_dir <- function() {
  dir <- brfss_cache_dir()
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE)
    cli::cli_inform(
      c(
        "i" = "Downloaded BRFSS data will be cached in {.path {dir}}.",
        "i" = "Manage it with {.fun brfss_cache_info} and
               {.fun brfss_cache_clear}."
      ),
      class = "brfssdata_cache_note"
    )
  }
  dir
}

# A NULL binding so tests can mock base file.rename (the rename-to-copy
# fallback below). R's call lookup skips non-function bindings, so
# base::file.rename still runs everywhere outside that mock.
file.rename <- NULL

# Download a release asset into the cache, failing with an informative,
# classed error (never a warning) if the resource is unavailable. When
# expected_sha256 is supplied, the payload is verified before it ever
# enters the cache; a mismatch is re-attempted (transient truncation is
# the common failure) and then aborts, leaving the cache untouched.
download_to_cache <- function(
  url,
  dest,
  quiet = FALSE,
  expected_sha256 = NULL,
  retries = 1L,
  call = rlang::caller_env()
) {
  ensure_cache_dir()
  # Unique tmp in the cache dir itself: concurrent sessions cannot
  # interleave writes, and the final rename stays same-filesystem.
  tmp <- tempfile(
    pattern = paste0(basename(dest), "-"),
    tmpdir = dirname(dest),
    fileext = ".tmp"
  )
  on.exit(unlink(tmp), add = TRUE)

  # R's default 60s timeout aborts real data-year downloads.
  old <- options(timeout = max(3600, getOption("timeout")))
  on.exit(options(old), add = TRUE)

  attempts <- 1L + max(0L, as.integer(retries))
  for (attempt in seq_len(attempts)) {
    why <- NULL
    ok <- tryCatch(
      {
        if (has_curl()) {
          curl::curl_download(url, tmp, mode = "wb", quiet = quiet)
        } else {
          utils::download.file(url, tmp, mode = "wb", quiet = quiet)
        }
        TRUE
      },
      error = function(e) {
        why <<- conditionMessage(e)
        FALSE
      },
      warning = function(w) {
        why <<- conditionMessage(w)
        FALSE
      }
    )
    if (!ok || !file.exists(tmp) || file.size(tmp) == 0) {
      if (is.null(why) && file.exists(tmp) && file.size(tmp) == 0) {
        why <- "the server returned an empty file"
      }
      cli::cli_abort(
        c(
          "Could not download {.url {url}}.",
          # The underlying condition distinguishes a proxy, TLS, disk-full
          # or 404 failure from simply being offline.
          if (!is.null(why)) c("x" = "{why}"),
          "i" = "The resource may be temporarily unavailable, or you may
                 be offline.",
          "i" = "Cached years remain usable; see {.fun brfss_cache_info}."
        ),
        class = "brfssdata_download_error",
        call = call
      )
    }
    if (is.null(expected_sha256)) {
      break
    }
    got <- cli::hash_file_sha256(tmp)
    if (identical(got, expected_sha256)) {
      break
    }
    unlink(tmp)
    if (attempt == attempts) {
      cli::cli_abort(
        c(
          "Downloaded {.url {url}} but its checksum does not match the
           data manifest ({attempts} attempt{?s}).",
          "x" = "Expected sha256 {substr(expected_sha256, 1, 12)}…,
                 got {substr(got, 1, 12)}….",
          "i" = "Nothing was written to the cache.",
          "i" = "If the release was recently republished, refresh the
                 manifest with {.code brfss_years(refresh = TRUE)} and
                 try again."
        ),
        class = c("brfssdata_checksum_error", "brfssdata_download_error"),
        call = call
      )
    }
  }
  if (
    !isTRUE(file.rename(tmp, dest)) &&
      !isTRUE(file.copy(tmp, dest, overwrite = TRUE))
  ) {
    cli::cli_abort(
      c(
        "Downloaded {.url {url}} but could not move it into the cache
         at {.path {dest}}.",
        "i" = "Check that the cache directory is writable and that the
               file is not open in another process."
      ),
      class = "brfssdata_download_error",
      call = call
    )
  }
  dest
}

# One informational note per call for assets fetched without a published
# checksum (a v1 or bundled manifest). Deliberately state-free rather
# than once-per-session, so tests stay order-independent.
note_unverified <- function(assets, quiet) {
  if (isTRUE(quiet) || length(assets) == 0) {
    return(invisible())
  }
  cli::cli_inform(
    c(
      "!" = "No published checksum for {.file {assets}}; downloading
             without verification.",
      "i" = "Refresh the manifest with {.code brfss_years(refresh = TRUE)}
             to pick one up."
    ),
    class = "brfssdata_unverified_note"
  )
}

# Ensure a data-meta catalog asset is cached, verified, and reasonably
# fresh. Freshness piggybacks on the manifest's daily cadence: at most
# once per day per session, the cached file's hash is compared with the
# manifest's entry and the file re-downloaded when they differ, so a
# cache populated before a new data release picks up the new catalogs
# within a day. Offline, or under a manifest without hashes, the cached
# copy is kept silently: no hash, no verdict.
ensure_catalog_cached <- function(
  asset,
  what,
  download = TRUE,
  quiet = TRUE,
  call = rlang::caller_env()
) {
  path <- cache_path(asset)

  if (!file.exists(path)) {
    if (!download) {
      cli::cli_abort(
        c(
          "The {what} is not cached and {.code download = FALSE} was set.",
          "i" = "Call once with {.code download = TRUE} (the default) on
                 a connected machine, or prefetch everything with
                 {.fun brfss_download}."
        ),
        class = "brfssdata_not_cached",
        call = call
      )
    }
    sha <- manifest_sha256(asset, read_manifest())
    if (is.null(sha)) {
      note_unverified(asset, quiet)
    }
    download_to_cache(
      release_url("data-meta", asset),
      path,
      quiet = quiet,
      expected_sha256 = sha,
      call = call
    )
    catalog_checked(asset)
    return(path)
  }

  if (download && catalog_check_due(asset)) {
    want <- manifest_sha256(asset, read_manifest())
    if (!is.null(want) && !identical(cli::hash_file_sha256(path), want)) {
      if (!quiet) {
        cli::cli_inform(
          "Refreshing the {what}: a newer copy is published."
        )
      }
      download_to_cache(
        release_url("data-meta", asset),
        path,
        quiet = quiet,
        expected_sha256 = want,
        call = call
      )
    }
    catalog_checked(asset)
  }
  path
}
