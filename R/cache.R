#' Manage the local BRFSS data cache
#'
#' @description
#' Downloaded survey years are stored as parquet files in a per-user cache
#' directory so repeat use, and offline work, never re-download. The cache
#' location follows [tools::R_user_dir()] and can be redirected with
#' `options(brfssdata.cache_dir = ...)` or the `R_USER_CACHE_DIR`
#' environment variable. The option must be a single non-empty path
#' that is not an existing regular file; anything else is rejected
#' (`brfssdata_bad_option`) rather than read as an empty cache.
#'
#' * `brfss_cache_dir()` returns the cache directory path.
#' * `brfss_cache_info()` lists cached files with their sizes. Rows with
#'   `year = NA` are the metadata files (the manifest and the variable
#'   and label catalogs), not survey years. `verify = TRUE` also hashes
#'   each file and compares it with the data manifest's checksum,
#'   adding a `verified` column: `TRUE` on a match, `FALSE` on a
#'   mismatch, `NA` where the manifest has no entry to compare against
#'   (the manifest itself, foreign files, or a manifest published
#'   without hashes). Hashing reads every byte, roughly two seconds for
#'   a full 40-year cache, so it is off by default; the comparison uses
#'   the cached or bundled manifest and never touches the network.
#' * `brfss_cache_clear()` deletes cached survey years, all of them by
#'   default, and reports what it removed. The manifest and catalogs are
#'   kept unless `catalogs = TRUE`, so offline use of [brfss_vars()] and
#'   [brfss_labels()] survives a data-cache clear. Called with no
#'   `years` argument in an interactive session, it asks for
#'   confirmation before deleting everything; scripts and rendered
#'   documents are never prompted, and an explicit `years = NULL`
#'   clears all years without asking in any session.
#'
#' @param years Optional integer vector. If supplied to
#'   `brfss_cache_clear()`, only those survey years are removed;
#'   `integer(0)` removes none (useful with `catalogs = TRUE`) and
#'   `NULL` removes every year without the interactive confirmation.
#'   Fractional, infinite, missing, or non-numeric years are rejected
#'   (`brfssdata_bad_years_arg`) before anything is deleted.
#' @param verify If `TRUE`, `brfss_cache_info()` hashes every cached
#'   file and adds the `verified` column described above.
#' @param catalogs If `TRUE`, `brfss_cache_clear()` also removes the
#'   manifest and the variable and label catalogs.
#'
#' @return
#' `brfss_cache_dir()` returns a path (character). `brfss_cache_info()`
#' returns a tibble with columns `file`, `year`, and `size` (bytes),
#' plus `verified` (logical) under `verify = TRUE`.
#' `brfss_cache_clear()` returns, invisibly, the paths it removed.
#'
#' @examples
#' brfss_cache_dir()
#' brfss_cache_info()
#' @seealso [brfssdata-options] for every session option the package
#'   reads.
#' @export
brfss_cache_dir <- function() {
  dir <- getOption("brfssdata.cache_dir")
  if (is.null(dir)) {
    return(tools::R_user_dir("brfssdata", "cache"))
  }
  # The documented way to set this is a line in .Rprofile, where a typo
  # is invisible: "" or a path that is really a file used to sail
  # through, and the whole package then reported an empty cache and
  # wrote downloads to a nonsensical path. Validated here because this
  # is the single place the option is read.
  # Trimmed before use, not merely before the emptiness test: a padded
  # path in .Rprofile otherwise passed validation and was then used
  # verbatim, where the leading space makes it a different (relative)
  # directory.
  if (is.character(dir) && length(dir) == 1L && !is.na(dir)) {
    dir <- trimws(dir)
  }
  shaped <- is.character(dir) &&
    length(dir) == 1L &&
    !is.na(dir) &&
    nzchar(dir)
  is_file <- shaped && file.exists(dir) && !dir.exists(dir)
  if (!shaped || is_file) {
    why <- if (is_file) {
      "{.path {dir}} is a file, not a directory."
    } else {
      "Got {.obj_type_friendly {dir}}."
    }
    cli::cli_abort(
      c(
        "{.code options(brfssdata.cache_dir)} must be a single path to a
         directory.",
        "x" = why,
        "i" = "Set it to a writable directory, e.g.
               {.code options(brfssdata.cache_dir = \"~/brfss-cache\")},
               or unset it to use {.path {tools::R_user_dir('brfssdata',
               'cache')}}."
      ),
      class = "brfssdata_bad_option"
    )
  }
  dir
}

#' @rdname brfss_cache_dir
#' @export
brfss_cache_info <- function(verify = FALSE) {
  # Gated rather than read through isTRUE(): verify = "yes" used to skip
  # every hash while reading, to the person who typed it, as a request
  # to check them all.
  verify <- check_bool_arg(verify, "verify")
  dir <- brfss_cache_dir()
  files <- list.files(dir, full.names = TRUE)
  info <- file.info(files, extra_cols = FALSE)
  # Regular files only: a stray subdirectory has no meaningful cache
  # size (file.info() reports its inode size), and listing one as a
  # cached file inflated the total brfss_download() prints.
  keep <- !is.na(info$isdir) & !info$isdir
  files <- files[keep]
  info <- info[keep, , drop = FALSE]
  out <- tibble::tibble(
    file = basename(files),
    year = cached_file_year(basename(files)),
    size = info$size
  )
  if (isTRUE(verify)) {
    manifest <- read_manifest_cached()
    out$verified <- vapply(
      seq_along(files),
      function(i) {
        want <- manifest_sha256(out$file[[i]], manifest)
        if (is.null(want)) {
          return(NA)
        }
        identical(cli::hash_file_sha256(files[[i]]), want)
      },
      logical(1)
    )
  }
  out
}

CACHE_META_FILES <- c(
  "manifest.json",
  "brfss_variables.parquet",
  "brfss_labels.parquet",
  "brfss_crosswalk.parquet",
  "brfss_year_info.parquet"
)

# A frozen-at-release copy of a metadata asset shipped in inst/extdata,
# so the metadata functions work on first use with no network. NULL for
# assets without a snapshot (the year-info table, which carries sizes
# that change with each data release).
bundled_asset_path <- function(asset) {
  path <- system.file("extdata", asset, package = "brfssdata")
  if (nzchar(path)) path else NULL
}

# Bundled snapshots are never served silently: they were frozen at the
# package's release and the hosted copy may since have gained years or
# corrections. One line, because a codebook lookup can consult three
# catalogs in a single call.
note_bundled_asset <- function(what) {
  cli::cli_inform(
    c(
      "!" = "Using the {what} snapshot bundled with the package (frozen
             at release); {.fun brfss_download} caches the current copy."
    ),
    class = "brfssdata_bundled_fallback_note"
  )
}

#' Prefetch BRFSS data and metadata into the local cache
#'
#' @description
#' Downloads the requested survey years, and by default also the data
#' manifest and the metadata catalogs (variables, labels, the rename
#' crosswalk, and the year inventory), so that everything works offline
#' afterwards: [read_brfss()], [brfss_design()], [brfss_vars()],
#' [brfss_labels()], [brfss_crosswalk()], [brfss_year_info()], and
#' `labels`/`na` conversion all run from the cache. Use it to populate
#' the cache once on a connected machine (the directory from
#' [brfss_cache_dir()] can then be copied to an air-gapped one), or to
#' pre-download years ahead of a workshop. Files already cached and
#' current are not re-downloaded.
#'
#' @param years Optional integer vector of survey years to cache.
#'   `NULL` fetches only the metadata.
#' @param catalogs If `TRUE` (the default), also cache the manifest and
#'   the metadata catalogs.
#' @param quiet If `TRUE`, suppress download progress and the summary.
#'
#' @return Invisibly, the [brfss_cache_info()] tibble after the fetch.
#'
#' @examplesIf interactive()
#' brfss_download(2019:2023)
#' @export
brfss_download <- function(years = NULL, catalogs = TRUE, quiet = FALSE) {
  catalogs <- check_bool_arg(catalogs, "catalogs")
  quiet <- check_bool_arg(quiet, "quiet")
  if (!is.null(years)) {
    years <- validate_years(years)
    ensure_years_cached(years, download = TRUE, quiet = quiet)
  }
  if (catalogs) {
    read_manifest(quiet = quiet)
    # fallback = FALSE: a prefetch must cache real files or fail
    # loudly; serving the bundled snapshot here would report success
    # while caching nothing.
    ensure_catalog_cached(
      "brfss_variables.parquet",
      what = "variable catalog",
      quiet = quiet,
      fallback = FALSE
    )
    ensure_catalog_cached(
      "brfss_labels.parquet",
      what = "label catalog",
      quiet = quiet,
      fallback = FALSE
    )
    ensure_catalog_cached(
      "brfss_crosswalk.parquet",
      what = "rename crosswalk",
      quiet = quiet,
      fallback = FALSE
    )
    ensure_catalog_cached(
      "brfss_year_info.parquet",
      what = "year inventory",
      quiet = quiet,
      fallback = FALSE
    )
  }
  info <- brfss_cache_info()
  if (!quiet) {
    cli::cli_inform(
      "Cache at {.path {brfss_cache_dir()}}: {sum(!is.na(info$year))}
       year{?s}, {format(structure(sum(info$size, na.rm = TRUE),
       class = 'object_size'), units = 'auto')}.",
      class = "brfssdata_cache_note"
    )
  }
  invisible(info)
}

#' @rdname brfss_cache_dir
#' @export
brfss_cache_clear <- function(years = NULL, catalogs = FALSE) {
  # Captured before `years` is touched; missing() is unreliable after
  # any assignment. A literal `years = NULL` call is the documented
  # no-prompt escape hatch for scripts, so only the no-argument form
  # ever confirms.
  no_years_given <- missing(years)
  catalogs <- check_bool_arg(catalogs, "catalogs")
  # Validated before anything is touched: as.integer() truncation here
  # meant brfss_cache_clear(2024.9) silently deleted the 2024 file.
  # integer(0) stays the documented remove-nothing request.
  if (!is.null(years)) {
    years <- check_years_arg(years, allow_empty = TRUE)
  }
  dir <- brfss_cache_dir()
  files <- list.files(dir, full.names = TRUE)
  file_year <- cached_file_year(basename(files))

  # Only files this package wrote are ever deleted: year assets matching
  # the requested years, plus the metadata files when asked. A foreign
  # file that happens to sit in the cache directory is never touched.
  is_year <- !is.na(file_year)
  if (!is.null(years)) {
    is_year <- is_year & file_year %in% years
  }
  is_meta <- isTRUE(catalogs) & basename(files) %in% CACHE_META_FILES
  files <- files[is_year | is_meta]

  removed_bytes <- sum(file.info(files)$size, na.rm = TRUE)
  # Deleting the whole cache is cheap to undo only in bandwidth, and a
  # bare brfss_cache_clear() is easy to send by accident. Interactive
  # sessions confirm; scripts and tests (rlang::is_interactive() is
  # FALSE there) behave exactly as before.
  if (no_years_given && length(files) > 0 && rlang::is_interactive()) {
    size_txt <- format(
      structure(removed_bytes, class = "object_size"),
      units = "auto"
    )
    ok <- ask_yes_no(sprintf(
      "Remove all %d cached file(s) (%s) from %s?",
      length(files),
      size_txt,
      dir
    ))
    if (!isTRUE(ok)) {
      cli::cli_inform(
        "Nothing removed from {.path {dir}}.",
        class = "brfssdata_cache_note"
      )
      return(invisible(character(0)))
    }
  }
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

# Isolated so tests can mock it. askYesNo() returns NA on EOF or
# inscrutable input, and the isTRUE() at the call site treats that as a
# refusal: the safe default for a delete.
ask_yes_no <- function(prompt) {
  utils::askYesNo(prompt, default = FALSE)
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

# Fail rather than hang: give up if a connection takes more than a
# minute to establish, or if an established transfer sits below 100
# bytes/s for five minutes (a stalled proxy, not a slow link). libcurl
# sets no transfer-time ceiling of its own, so without these a dead
# middlebox blocks forever.
download_handle <- function() {
  curl::new_handle(
    connecttimeout = 60L,
    low_speed_limit = 100L,
    low_speed_time = 300L
  )
}

# The transport call, separated so tests can substitute classed curl
# failures without touching the network.
perform_download <- function(url, tmp, quiet) {
  if (has_curl()) {
    curl::curl_download(
      url,
      tmp,
      mode = "wb",
      quiet = quiet,
      handle = download_handle()
    )
  } else {
    utils::download.file(url, tmp, mode = "wb", quiet = quiet)
  }
}

# curl signals one classed condition per libcurl error code, which is
# enough to name the likely cause. Anything unrecognized -- including
# every download.file() failure, which arrives as text only -- keeps the
# generic wording. `dir` is the directory the transfer had to land in:
# when it cannot be written, the failure is local and the offline hint
# would send the reader chasing their network instead of their
# permissions.
download_failure_hint <- function(cond, dir = NULL) {
  generic <- c(
    "i" = "The resource may be temporarily unavailable, or you may
           be offline."
  )
  if (!is.null(dir) && !cache_dir_writable(dir)) {
    # Rendered here, where `dir` exists, rather than handed to the
    # caller as a glue template: cli evaluates a bullet's braces in the
    # frame that signals the condition, and that frame has no `dir`, so
    # the lookup used to reach base::dir and abort the abort with an
    # unclassed "cannot coerce type 'closure'". Every fallback handler
    # subscribes to brfssdata_download_error, so losing the class there
    # turned a graceful degradation into a hard failure.
    return(c(
      "i" = escape_cli_braces(cli::format_inline(
        "Nothing could be written to {.path {dir}}, so this is a
         local file-system failure, not a network one."
      )),
      "i" = "Point the cache at a writable directory with
             {.code options(brfssdata.cache_dir = ...)}."
    ))
  }
  if (is.null(cond)) {
    return(generic)
  }
  # Both downloaders report a failed local write in English text of
  # their own making (curl's "Failed to open file", download.file()'s
  # "cannot open destfile"), with no class to dispatch on. A writable
  # directory with no room left is the case the check above misses.
  local_write <- "Failed to open file|cannot open destfile"
  if (grepl(local_write, conditionMessage(cond))) {
    return(c(
      "i" = "The file could not be written locally, so this is not a
             network failure.",
      "i" = "Check that {.fun brfss_cache_dir} is writable and that the
             disk or quota has room."
    ))
  }
  cls <- class(cond)
  unreachable <- c(
    "curl_error_couldnt_resolve_host",
    "curl_error_couldnt_connect",
    "curl_error_no_connection_available"
  )
  proxy_tls <- c(
    "curl_error_peer_failed_verification",
    "curl_error_proxy",
    "curl_error_couldnt_resolve_proxy",
    "curl_error_use_ssl_failed"
  )
  if (any(cls %in% unreachable)) {
    return(c(
      "i" = "GitHub could not be reached; you may be offline, or this
             network may block {.code github.com}."
    ))
  }
  if (any(cls %in% proxy_tls) || any(startsWith(cls, "curl_error_ssl"))) {
    return(c(
      "i" = "This looks like a proxy or TLS-interception failure, common
             on hospital, campus, and corporate networks.",
      "i" = "Downloads made on an unrestricted machine can be copied into
             this one's cache; see {.fun brfss_download}."
    ))
  }
  if ("curl_error_operation_timedout" %in% cls) {
    return(c(
      "i" = "The connection stalled or timed out; retry, or prefetch with
             {.fun brfss_download} on a steadier network."
    ))
  }
  if ("curl_error_http_returned_error" %in% cls) {
    return(c(
      "i" = "The server rejected the request; the published years are
             listed by {.fun brfss_years}."
    ))
  }
  generic
}

cache_path <- function(asset) {
  file.path(brfss_cache_dir(), asset)
}

# file.access() reports the real uid's permissions and is advisory on
# Windows ACLs, so it is used to refuse before a 30 MB transfer and to
# explain a failure afterwards, never as a promise that a write will
# succeed.
cache_dir_writable <- function(dir) {
  dir.exists(dir) && file.access(dir, mode = 2L)[[1L]] == 0L
}

ensure_cache_dir <- function(quiet = FALSE, call = rlang::caller_env()) {
  dir <- brfss_cache_dir()
  if (!dir.exists(dir)) {
    # dir.create() reports failure through a warning and a FALSE
    # return, and both used to be dropped: the note below then
    # announced a directory that does not exist, and the first
    # download blamed the network for a local permission problem. The
    # dir.exists() recheck keeps a concurrent session's creation from
    # counting as failure.
    created <- suppressWarnings(dir.create(dir, recursive = TRUE))
    if (!isTRUE(created) && !dir.exists(dir)) {
      cli::cli_abort(
        c(
          "Could not create the cache directory {.path {dir}}.",
          "x" = "Its parent directory is missing or not writable.",
          "i" = "Point the cache somewhere writable with
                 {.code options(brfssdata.cache_dir = ...)}, in
                 {.file .Rprofile} to make it stick."
        ),
        class = c("brfssdata_cache_unwritable", "brfssdata_download_error"),
        call = call
      )
    }
    if (!isTRUE(quiet)) {
      cli::cli_inform(
        c(
          "i" = "Downloaded BRFSS data will be cached in {.path {dir}}.",
          "i" = "Manage it with {.fun brfss_cache_info} and
                 {.fun brfss_cache_clear}."
        ),
        class = "brfssdata_cache_note"
      )
    }
  }
  if (!cache_dir_writable(dir)) {
    cli::cli_abort(
      c(
        "The cache directory {.path {dir}} is not writable.",
        "x" = "This is a local permission problem, not a network one.",
        "i" = "Point the cache somewhere writable with
               {.code options(brfssdata.cache_dir = ...)}, in
               {.file .Rprofile} to make it stick."
      ),
      class = c("brfssdata_cache_unwritable", "brfssdata_download_error"),
      call = call
    )
  }
  sweep_stale_tmp(dir)
  dir
}

# The staging names this package generates inside the cache directory,
# and nothing else does: download_to_cache()'s per-asset temp file
# (curl appends its own .curltmp while a transfer is live) and
# refresh_manifest()'s staged manifest. Every name this matches ends in
# .tmp, which is the part no file a user keeps has. An earlier version
# also matched a bare "manifest-<hex>.json", which silently deleted
# dated snapshots such as manifest-2024.json and manifest-20240115.json,
# both of which are hex by accident. Every sweep runs through here, so
# this is the one place that decides what the package may delete.
package_tmp_file <- function(file) {
  assets <- c(
    "brfss_[0-9]{4}\\.parquet",
    gsub(".", "\\.", CACHE_META_FILES, fixed = TRUE),
    "manifest-[0-9a-f]+\\.json"
  )
  staging <- sprintf(
    "^(%s)-[0-9a-f]+\\.tmp(\\.curltmp)?$",
    paste(assets, collapse = "|")
  )
  # refresh_manifest() stages as manifest-<hex>.json.tmp, so the
  # extension carries an inner .json the pattern above does not expect.
  manifest_staging <- "^manifest-[0-9a-f]+\\.json\\.tmp(\\.curltmp)?$"
  grepl(staging, file) | grepl(manifest_staging, file)
}

# Partial downloads are unlinked on error and on interrupt, but a
# SIGKILL or a power cut leaves one behind for good: brfss_cache_clear()
# reads it as a foreign file and keeps it, and brfss_cache_info() counts
# its bytes toward the cache total. The manifest's max age is the age
# threshold because no transfer this package starts survives a day, so
# nothing older can still be live in another session.
sweep_stale_tmp <- function(dir) {
  files <- list.files(dir)
  files <- files[package_tmp_file(files)]
  if (length(files) == 0) {
    return(invisible(character(0)))
  }
  paths <- file.path(dir, files)
  age <- difftime(Sys.time(), file.mtime(paths), units = "secs")
  stale <- !is.na(age) & as.numeric(age) > MANIFEST_MAX_AGE
  unlink(paths[stale])
  invisible(paths[stale])
}

# A NULL binding so tests can mock base file.rename (the rename-to-copy
# fallback below). R's call lookup skips non-function bindings, so
# base::file.rename still runs everywhere outside that mock.
file.rename <- NULL

# Move a staged file into its cache path. The rename is atomic on every
# platform the package supports, so a concurrent reader sees the whole
# old file or the whole new one. On Windows it fails while either end is
# held open (an antivirus scanner, another R session reading the year),
# and the byte-by-byte copy that used to follow immediately can be
# observed half-written, leaving a truncated year behind if the session
# dies mid-copy. So: retry the rename briefly, then try once more from a
# fresh staging name that nothing else can be holding, and only then
# copy. Residual limitation: a destination held open for the whole retry
# window still ends in a non-atomic copy, which no portable R call can
# avoid (base R exposes no MoveFileEx replace).
replace_cached_file <- function(from, to, tries = 4L, wait = 0.05) {
  for (i in seq_len(tries)) {
    if (isTRUE(file.rename(from, to))) {
      return(TRUE)
    }
    if (i < tries) {
      Sys.sleep(wait)
    }
  }
  staged <- tempfile(
    pattern = paste0(basename(to), "-"),
    tmpdir = dirname(to),
    fileext = ".tmp"
  )
  on.exit(unlink(staged), add = TRUE)
  if (isTRUE(file.copy(from, staged)) && isTRUE(file.rename(staged, to))) {
    return(TRUE)
  }
  isTRUE(file.copy(from, to, overwrite = TRUE))
}

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
  ensure_cache_dir(quiet = quiet, call = call)
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
    cond <- NULL
    ok <- tryCatch(
      {
        perform_download(url, tmp, quiet)
        TRUE
      },
      error = function(e) {
        cond <<- e
        FALSE
      },
      warning = function(w) {
        cond <<- w
        FALSE
      }
    )
    if (!ok || !file.exists(tmp) || file.size(tmp) == 0) {
      # The condition is kept whole, not just its message: curl's classed
      # errors let the hint below name a proxy/TLS block, a stall, or a
      # rejected request rather than guessing "offline".
      why <- if (!is.null(cond)) conditionMessage(cond)
      if (is.null(why) && file.exists(tmp) && file.size(tmp) == 0) {
        why <- "the server returned an empty file"
      }
      cli::cli_abort(
        c(
          "Could not download {.url {url}}.",
          if (!is.null(why)) c("x" = "{why}"),
          download_failure_hint(cond, dir = dirname(dest)),
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
          "x" = "Expected sha256 {substr(expected_sha256, 1, 12)}...,
                 got {substr(got, 1, 12)}....",
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
  if (!replace_cached_file(tmp, dest)) {
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
  fallback = TRUE,
  call = rlang::caller_env()
) {
  path <- cache_path(asset)

  if (!file.exists(path)) {
    bundled <- if (fallback) bundled_asset_path(asset) else NULL
    if (!download) {
      if (!is.null(bundled)) {
        note_bundled_asset(what)
        return(bundled)
      }
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
    # A failed first fetch falls back to the bundled snapshot when one
    # ships: a metadata lookup should not die on an offline machine
    # that has never cached anything. Two deliberate exceptions: a
    # checksum mismatch always aborts (published bytes disagreeing with
    # the manifest is the package's headline integrity signal, never
    # something to paper over), and brfss_download() disables the
    # fallback entirely (fallback = FALSE), because a prefetch that
    # quietly cached nothing would defeat its whole contract.
    fetched <- tryCatch(
      download_to_cache(
        release_url("data-meta", asset),
        path,
        quiet = quiet,
        expected_sha256 = sha,
        call = call
      ),
      brfssdata_download_error = function(e) {
        if (is.null(bundled) || inherits(e, "brfssdata_checksum_error")) {
          stop(e)
        }
        NULL
      }
    )
    if (is.null(fetched)) {
      note_bundled_asset(what)
      return(bundled)
    }
    asset_checked(asset)
    return(path)
  }

  if (download && asset_check_due(asset)) {
    want <- manifest_sha256(asset, read_manifest())
    if (is.null(want) || identical(cli::hash_file_sha256(path), want)) {
      # Nothing to heal, so the daily memo is honest.
      asset_checked(asset)
    } else {
      if (!quiet) {
        cli::cli_inform(
          "Refreshing the {what}: a newer copy is published.",
          class = "brfssdata_cache_note"
        )
      }
      # A failed refresh keeps the cached copy: it was good enough
      # yesterday, and an offline session must not lose access to it
      # (the same fallback read_manifest() applies to the manifest).
      healed <- tryCatch(
        {
          download_to_cache(
            release_url("data-meta", asset),
            path,
            quiet = quiet,
            expected_sha256 = want,
            call = call
          )
          TRUE
        },
        brfssdata_download_error = function(e) {
          cli::cli_inform(
            c(
              "!" = "Could not refresh the {what}; using the cached copy."
            ),
            class = "brfssdata_manifest_note"
          )
          FALSE
        }
      )
      # Marked only when the refresh actually landed. Marking a failed
      # heal would serve a catalog known not to match the manifest,
      # silently, for the rest of the session; that is the defect this
      # release fixed on the year path, and it lived here too.
      if (isTRUE(healed)) {
        asset_checked(asset)
      }
    }
  }
  path
}

# Session memo of parsed catalog tibbles, keyed by file identity
# (normalized path, invalidated when mtime or size moves). Lives in
# manifest_state so the test fixtures' save/clear/restore scoping covers
# it automatically, like the per-asset check memos. Consulted only AFTER
# ensure_catalog_cached() has decided the on-disk file is current (or
# replaced it): a refresh rewrites the file, which changes the stamp, so
# the next lookup re-reads. A read error propagates and is never
# memoized, so a corrupt file keeps signalling on every call. mtime
# resolution is coarse (1s) on some filesystems; the size half of the
# stamp and the fact that replacements arrive as newly written bytes
# close that window in practice.
catalog_memo_get <- function(path, call = rlang::caller_env()) {
  info <- file.info(path, extra_cols = FALSE)
  key <- tryCatch(
    normalizePath(path, mustWork = FALSE),
    error = function(e) path
  )
  stamp <- c(as.numeric(info$mtime), as.numeric(info$size))
  memo <- manifest_state$catalog_memo %||% list()
  hit <- memo[[key]]
  if (!is.null(hit) && !anyNA(stamp) && identical(hit$stamp, stamp)) {
    return(hit$value)
  }
  value <- query_parquet(path, call = call)
  if (!anyNA(stamp)) {
    memo[[key]] <- list(stamp = stamp, value = value)
    manifest_state$catalog_memo <- memo
  }
  value
}

# One body for the metadata-catalog accessors: ensure the asset is
# cached and fresh, then serve the session memo.
read_catalog <- function(
  asset,
  what,
  download = TRUE,
  quiet = TRUE,
  fallback = TRUE,
  call = rlang::caller_env()
) {
  path <- ensure_catalog_cached(
    asset,
    what = what,
    download = download,
    quiet = quiet,
    fallback = fallback,
    call = call
  )
  catalog_memo_get(path, call = call)
}
