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
#' * `brfss_cache_info()` lists cached files with their sizes.
#' * `brfss_cache_clear()` deletes cached files, all years by default.
#'
#' @param years Optional integer vector. If supplied to
#'   `brfss_cache_clear()`, only those survey years are removed.
#'
#' @return
#' `brfss_cache_dir()` returns a path (character). `brfss_cache_info()`
#' returns a tibble with columns `file`, `year`, and `size`.
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

#' @rdname brfss_cache_dir
#' @export
brfss_cache_clear <- function(years = NULL) {
  dir <- brfss_cache_dir()
  files <- list.files(dir, full.names = TRUE)
  if (!is.null(years)) {
    keep_year <- cached_file_year(basename(files)) %in% as.integer(years)
    files <- files[!is.na(keep_year) & keep_year]
  }
  unlink(files)
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

# Download a release asset into the cache, failing with an informative,
# classed error (never a warning) if the resource is unavailable.
download_to_cache <- function(
  url,
  dest,
  quiet = FALSE,
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
