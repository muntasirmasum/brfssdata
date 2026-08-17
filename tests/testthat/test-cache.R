test_that("cache dir honors the option override", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  expect_identical(brfss_cache_dir(), dir)
})

test_that("the default cache dir is R_user_dir, not the working directory", {
  withr::local_options(brfssdata.cache_dir = NULL)
  expect_identical(
    brfss_cache_dir(),
    tools::R_user_dir("brfssdata", "cache")
  )
})

test_that("creating the cache announces its location, once", {
  dir <- file.path(withr::local_tempdir(), "brfss-cache")
  withr::local_options(brfssdata.cache_dir = dir)
  expect_message(ensure_cache_dir(), class = "brfssdata_cache_note")
  expect_no_message(ensure_cache_dir())
})

test_that("cache info lists files with parsed years", {
  local_brfss_cache(c(2022, 2023))
  info <- brfss_cache_info()
  expect_true(all(
    c("brfss_2022.parquet", "brfss_2023.parquet") %in%
      info$file
  ))
  expect_true(all(c(2022L, 2023L) %in% info$year))
  expect_true(all(info$size[info$year %in% 2022:2023] > 0))
})

test_that("cache clear removes only the requested years", {
  local_brfss_cache(c(2022, 2023))
  suppressMessages(brfss_cache_clear(years = 2022))
  info <- brfss_cache_info()
  expect_false("brfss_2022.parquet" %in% info$file)
  expect_true("brfss_2023.parquet" %in% info$file)

  suppressMessages(brfss_cache_clear())
  info <- brfss_cache_info()
  expect_false(any(!is.na(info$year)))
  # The metadata survives a data clear, so offline brfss_vars() and
  # brfss_labels() keep working.
  expect_true("manifest.json" %in% info$file)

  suppressMessages(brfss_cache_clear(catalogs = TRUE))
  expect_identical(nrow(brfss_cache_info()), 0L)
})

test_that("catalogs can be cleared without touching data years", {
  local_brfss_cache(2023, catalog = TRUE)
  suppressMessages(brfss_cache_clear(years = integer(0), catalogs = TRUE))
  info <- brfss_cache_info()
  expect_true("brfss_2023.parquet" %in% info$file)
  expect_false("brfss_variables.parquet" %in% info$file)
  expect_false("manifest.json" %in% info$file)
})

test_that("foreign files in the cache dir are never deleted", {
  dir <- local_brfss_cache(2023)
  foreign <- file.path(dir, "notes.txt")
  writeLines("mine", foreign)
  suppressMessages(brfss_cache_clear(catalogs = TRUE))
  expect_true(file.exists(foreign))
})

test_that("cache clear reports what it removed, and when there is nothing", {
  local_brfss_cache(2023)
  # Text matched too: both branches share the class, so a class-only
  # assertion cannot tell "Removed" from "Nothing to remove".
  expect_message(
    brfss_cache_clear(),
    "Removed 1 file",
    class = "brfssdata_cache_note"
  )
  expect_message(
    brfss_cache_clear(),
    "Nothing to remove",
    class = "brfssdata_cache_note"
  )
})

test_that("failed downloads raise a classed error and leave no debris", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  dest <- file.path(dir, "brfss_2023.parquet")
  expect_error(
    download_to_cache(
      local_file_url("file://does/not/exist.parquet"),
      dest,
      quiet = TRUE
    ),
    class = "brfssdata_download_error"
  )
  expect_false(file.exists(dest))
  expect_length(list.files(dir, pattern = "\\.tmp$"), 0)
})

test_that("a successful download lands the file and cleans up its temp copy", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  src <- withr::local_tempfile()
  writeLines("payload", src)
  dest <- file.path(dir, "brfss_2023.parquet")

  download_to_cache(local_file_url(paste0("file://", src)), dest, quiet = TRUE)

  expect_true(file.exists(dest))
  expect_identical(readLines(dest), "payload")
  expect_length(list.files(dir, pattern = "\\.tmp$"), 0)
})

test_that("has_curl reflects whether curl is really installed", {
  # The branch test below mocks has_curl(), so this is what pins the real
  # implementation. Only the false-negative direction is detectable on a
  # machine that has curl; a has_curl() stuck at TRUE would need a
  # curl-free machine to catch, and degrades to a classed download error
  # rather than a wrong answer.
  expect_identical(has_curl(), requireNamespace("curl", quietly = TRUE))
})

test_that("both downloaders land the file, whichever one is available", {
  # curl is a Suggests. The base R branch would otherwise never run on a
  # machine that has curl installed; the curl branch can only run where
  # curl actually exists (mocking has_curl() to TRUE on a noSuggests
  # machine would call a package that is not there).
  branches <- if (requireNamespace("curl", quietly = TRUE)) {
    c(TRUE, FALSE)
  } else {
    FALSE
  }
  for (curl_available in branches) {
    dir <- withr::local_tempdir()
    withr::local_options(brfssdata.cache_dir = dir)
    local_mocked_bindings(has_curl = function() curl_available)
    src <- withr::local_tempfile()
    writeLines("payload", src)
    dest <- file.path(dir, "brfss_2023.parquet")

    download_to_cache(
      local_file_url(paste0("file://", src)),
      dest,
      quiet = TRUE
    )

    expect_true(file.exists(dest))
    expect_identical(readLines(dest), "payload")
  }
})

test_that("a failed rename falls back to copying into place", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  src <- withr::local_tempfile()
  writeLines("payload", src)
  dest <- file.path(dir, "brfss_2023.parquet")
  # Cross-filesystem moves make file.rename() return FALSE; the copy
  # fallback is what keeps the download usable there. Mocked in this
  # package's namespace only: curl_download() renames internally too, and
  # a base-wide mock would break the download itself.
  local_mocked_bindings(file.rename = function(...) FALSE)
  download_to_cache(local_file_url(paste0("file://", src)), dest, quiet = TRUE)
  expect_true(file.exists(dest))
  expect_identical(readLines(dest), "payload")
})

test_that("an empty download is treated as a failure", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  src <- withr::local_tempfile()
  file.create(src)
  dest <- file.path(dir, "brfss_2023.parquet")

  expect_error(
    download_to_cache(
      local_file_url(paste0("file://", src)),
      dest,
      quiet = TRUE
    ),
    class = "brfssdata_download_error"
  )
  expect_false(file.exists(dest))
  expect_length(list.files(dir, pattern = "\\.tmp$"), 0)
})

test_that("download_handle builds a guarded curl handle", {
  skip_if_not_installed("curl")
  # new_handle() rejects unknown option names at construction, so this
  # also pins the connecttimeout/low_speed spellings.
  expect_s3_class(download_handle(), "curl_handle")
})

test_that("the curl branch downloads through the guarded handle", {
  skip_if_not_installed("curl")
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  used <- FALSE
  local_mocked_bindings(
    has_curl = function() TRUE,
    download_handle = function() {
      used <<- TRUE
      curl::new_handle()
    }
  )
  src <- withr::local_tempfile()
  writeLines("payload", src)
  download_to_cache(
    local_file_url(paste0("file://", src)),
    file.path(dir, "brfss_2023.parquet"),
    quiet = TRUE
  )
  expect_true(used)
})

test_that("classed curl failures get a targeted hint, same condition class", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  dest <- file.path(dir, "brfss_2023.parquet")
  curl_classed_error <- function(class) {
    structure(
      class = c(class, "curl_error", "error", "condition"),
      list(message = "transport detail", call = NULL)
    )
  }
  cases <- list(
    list("curl_error_couldnt_resolve_host", "GitHub could not be reached"),
    list("curl_error_couldnt_connect", "GitHub could not be reached"),
    list("curl_error_ssl_connect_error", "proxy or TLS-interception"),
    list("curl_error_peer_failed_verification", "proxy or TLS-interception"),
    list("curl_error_operation_timedout", "stalled or timed out"),
    list("curl_error_http_returned_error", "server rejected the request")
  )
  for (case in cases) {
    local({
      local_mocked_bindings(
        perform_download = function(url, tmp, quiet) {
          stop(curl_classed_error(case[[1]]))
        }
      )
      expect_error(
        download_to_cache("https://example.invalid/x.parquet", dest,
          quiet = TRUE
        ),
        case[[2]],
        class = "brfssdata_download_error"
      )
    })
  }
  expect_false(file.exists(dest))
})

test_that("unclassed failures keep the generic offline hint", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  local_mocked_bindings(
    perform_download = function(url, tmp, quiet) stop("plain transport error")
  )
  expect_error(
    download_to_cache(
      "https://example.invalid/x.parquet",
      file.path(dir, "brfss_2023.parquet"),
      quiet = TRUE
    ),
    "temporarily unavailable",
    class = "brfssdata_download_error"
  )
})

test_that("malformed years never reach the delete filter", {
  # brfss_cache_clear(2024.9) used to truncate to 2024 and silently
  # delete that year's file; "2024" coerced and deleted it too.
  local_brfss_cache(2024)
  target <- file.path(brfss_cache_dir(), "brfss_2024.parquet")
  expect_true(file.exists(target))
  expect_error(
    brfss_cache_clear(2024.9),
    class = "brfssdata_bad_years_arg"
  )
  expect_true(file.exists(target))
  expect_error(
    brfss_cache_clear("2024"),
    class = "brfssdata_bad_years_arg"
  )
  expect_true(file.exists(target))
  expect_error(
    brfss_cache_clear(Inf),
    class = "brfssdata_bad_years_arg"
  )
  expect_true(file.exists(target))
})

test_that("brfss_cache_info(verify = TRUE) reports the tri-state verdict", {
  dir <- local_brfss_cache(2023)
  # a foreign file the manifest knows nothing about
  writeLines("not ours", file.path(dir, "notes.txt"))
  plain <- brfss_cache_info()
  expect_false("verified" %in% names(plain))
  info <- brfss_cache_info(verify = TRUE)
  expect_true(info$verified[info$file == "brfss_2023.parquet"])
  expect_true(is.na(info$verified[info$file == "manifest.json"]))
  expect_true(is.na(info$verified[info$file == "notes.txt"]))
  # corrupt the year file preserving size: FALSE, not NA
  path <- file.path(dir, "brfss_2023.parquet")
  bytes <- readBin(path, "raw", file.size(path))
  bytes[seq_len(min(100L, length(bytes)))] <- as.raw(0L)
  writeBin(bytes, path)
  info2 <- brfss_cache_info(verify = TRUE)
  expect_false(info2$verified[info2$file == "brfss_2023.parquet"])
})

test_that("catalog reads are memoized within a session", {
  local_brfss_cache(2023)
  real_query <- query_parquet
  reads <- 0L
  local_mocked_bindings(
    query_parquet = function(...) {
      reads <<- reads + 1L
      real_query(...)
    }
  )
  first <- brfss_labels(years = 2023)
  second <- brfss_labels(years = 2023)
  expect_identical(reads, 1L)
  expect_identical(first, second)
})

test_that("a replaced catalog file invalidates the session memo", {
  dir <- local_brfss_cache(2023)
  first <- brfss_labels(years = 2023)
  expect_gt(nrow(first), 0)
  # Rewrite the label catalog with an extra year: new bytes on disk,
  # plus an explicit mtime bump for coarse-mtime filesystems.
  write_fixture_labels(dir, extra_years = c(2022L, 2023L))
  path <- file.path(dir, "brfss_labels.parquet")
  bumped <- Sys.setFileTime(path, Sys.time() + 2)
  skip_if_not(isTRUE(bumped), "cannot set file mtime on this filesystem")
  refreshed <- brfss_labels(years = 2022)
  expect_true(all(refreshed$year == 2022L))
  expect_gt(nrow(refreshed), 0)
})

test_that("a bare interactive cache clear asks first, and a refusal keeps files", {
  dir <- local_brfss_cache(2023)
  target <- file.path(dir, "brfss_2023.parquet")
  withr::local_options(rlang_interactive = TRUE)
  local_mocked_bindings(ask_yes_no = function(...) FALSE)
  expect_message(
    removed <- brfss_cache_clear(),
    class = "brfssdata_cache_note"
  )
  expect_identical(removed, character(0))
  expect_true(file.exists(target))

  # NA (EOF, closed stdin) counts as a refusal too.
  local_mocked_bindings(ask_yes_no = function(...) NA)
  suppressMessages(removed <- brfss_cache_clear())
  expect_true(file.exists(target))

  local_mocked_bindings(ask_yes_no = function(...) TRUE)
  suppressMessages(removed <- brfss_cache_clear())
  expect_false(file.exists(target))
  expect_identical(basename(removed), "brfss_2023.parquet")
})

test_that("explicit years and years = NULL never prompt", {
  dir <- local_brfss_cache(2022:2023)
  withr::local_options(rlang_interactive = TRUE)
  local_mocked_bindings(
    ask_yes_no = function(...) stop("prompt must not be reached")
  )
  suppressMessages(brfss_cache_clear(2022))
  expect_false(file.exists(file.path(dir, "brfss_2022.parquet")))
  expect_true(file.exists(file.path(dir, "brfss_2023.parquet")))
  suppressMessages(brfss_cache_clear(years = NULL))
  expect_false(file.exists(file.path(dir, "brfss_2023.parquet")))
})

test_that("non-interactive sessions clear without prompting", {
  dir <- local_brfss_cache(2023)
  withr::local_options(rlang_interactive = FALSE)
  local_mocked_bindings(
    ask_yes_no = function(...) stop("prompt must not be reached")
  )
  suppressMessages(brfss_cache_clear())
  expect_false(file.exists(file.path(dir, "brfss_2023.parquet")))
})

# Dropping write permission is a no-op for a superuser, and some
# filesystems ignore it outright, so the permission tests below check
# that the chmod took before they assert on it.
skip_if_still_writable <- function(dir) {
  testthat::skip_if(
    file.access(dir, mode = 2L)[[1L]] == 0L,
    "cannot drop write permission on this filesystem"
  )
}

test_that("an uncreatable cache directory names the permission problem", {
  parent <- withr::local_tempdir()
  target <- file.path(parent, "cache")
  Sys.chmod(parent, "0555")
  withr::defer(Sys.chmod(parent, "0755"))
  skip_if_still_writable(parent)
  withr::local_options(brfssdata.cache_dir = target)
  # dir.create()'s FALSE used to be ignored, so this printed the
  # first-run cache note for a directory that was never created.
  expect_error(ensure_cache_dir(), class = "brfssdata_cache_unwritable")
  expect_false(dir.exists(target))
})

test_that("a read-only cache dir fails as local, never as offline", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  src <- withr::local_tempfile()
  writeLines("payload", src)
  Sys.chmod(dir, "0555")
  withr::defer(Sys.chmod(dir, "0755"))
  skip_if_still_writable(dir)
  e <- expect_error(
    download_to_cache(
      local_file_url(paste0("file://", src)),
      file.path(dir, "brfss_2023.parquet"),
      quiet = TRUE
    ),
    class = "brfssdata_cache_unwritable"
  )
  expect_match(conditionMessage(e), "not writable")
  expect_false(grepl("offline", conditionMessage(e)))
  # The metadata fallbacks catch the download class, so it must stay.
  expect_s3_class(e, "brfssdata_download_error")
})

test_that("the download hint separates a local write failure from offline", {
  dir <- withr::local_tempdir()
  expect_match(download_failure_hint(NULL), "offline", all = FALSE)
  Sys.chmod(dir, "0555")
  withr::defer(Sys.chmod(dir, "0755"))
  skip_if_still_writable(dir)
  hint <- download_failure_hint(NULL, dir = dir)
  expect_match(hint, "local file-system failure", all = FALSE)
  expect_false(any(grepl("offline", hint)))
  # A writable directory with no room left: the downloaders say so in
  # text, with no class to dispatch on.
  wrote <- simpleError("Failed to open file /tmp/x.tmp.curltmp")
  expect_match(
    download_failure_hint(wrote),
    "could not be written locally",
    all = FALSE
  )
})

test_that("a malformed cache_dir option is rejected where it is read", {
  # The documented way to set this is a line in .Rprofile, where a typo
  # used to read as an empty cache rather than as a mistake.
  for (bad in list("", "   ", c("a", "b"), NA_character_, 1L, TRUE)) {
    withr::local_options(brfssdata.cache_dir = bad)
    expect_error(brfss_cache_dir(), class = "brfssdata_bad_option")
  }
  path <- withr::local_tempfile()
  writeLines("not a directory", path)
  withr::local_options(brfssdata.cache_dir = path)
  expect_error(brfss_cache_info(), class = "brfssdata_bad_option")
})

test_that("stale partial downloads are swept and foreign files are not", {
  dir <- local_brfss_cache(2023)
  ours <- file.path(
    dir,
    c(
      "brfss_2019.parquet-0123abcd.tmp",
      "brfss_labels.parquet-89ab12.tmp.curltmp",
      "manifest-4f2a99.json.tmp",
      # download_to_cache() staging ONTO the staged manifest name, the
      # composed residue a killed daily refresh really leaves.
      "manifest-77aa00.json.tmp-0badbeef.tmp",
      "manifest-77aa00.json.tmp-0badbeef.tmp.curltmp"
    )
  )
  # Same age, not ours: the only thing keeping these is the name rule.
  # The dated manifest snapshots are the ones an earlier pattern ate:
  # every character is hex by accident, so only the missing .tmp tells
  # a user's file from a staged download.
  theirs <- file.path(
    dir,
    c(
      "notes.txt",
      "brfss_2019.parquet.tmp",
      "my-brfss_2020.parquet-x.tmp",
      "manifest-2024.json",
      "manifest-20240115.json"
    )
  )
  live <- file.path(dir, "brfss_2021.parquet-beef00.tmp")
  for (f in c(ours, theirs, live)) {
    writeLines("partial", f)
  }
  for (f in c(ours, theirs)) {
    Sys.setFileTime(f, Sys.time() - 3 * MANIFEST_MAX_AGE)
  }
  ensure_cache_dir(quiet = TRUE)
  expect_false(any(file.exists(ours)))
  expect_true(all(file.exists(theirs)))
  # A transfer younger than the manifest max age may still be running.
  expect_true(file.exists(live))
  expect_true(file.exists(file.path(dir, "brfss_2023.parquet")))
  # The real manifest shares the staging file's stem; only the hex tail
  # tells them apart.
  expect_true(file.exists(file.path(dir, "manifest.json")))
  expect_false(any(basename(ours) %in% brfss_cache_info()$file))
})

test_that("quiet suppresses the first-run cache directory note", {
  dir <- file.path(withr::local_tempdir(), "brfss-cache")
  withr::local_options(brfssdata.cache_dir = dir)
  src <- withr::local_tempfile()
  writeLines("payload", src)
  expect_no_message(
    download_to_cache(
      local_file_url(paste0("file://", src)),
      file.path(dir, "brfss_2023.parquet"),
      quiet = TRUE
    )
  )
  expect_true(file.exists(file.path(dir, "brfss_2023.parquet")))
})

test_that("a transient rename failure is retried instead of copied", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  src <- withr::local_tempfile()
  writeLines("payload", src)
  dest <- file.path(dir, "brfss_2023.parquet")
  # Windows fails the rename while another process holds either end
  # open; one retry clears the common case, and only the retried rename
  # keeps the replacement atomic.
  calls <- 0L
  local_mocked_bindings(
    file.rename = function(from, to) {
      calls <<- calls + 1L
      if (calls == 1L) FALSE else base::file.rename(from, to)
    }
  )
  download_to_cache(local_file_url(paste0("file://", src)), dest, quiet = TRUE)
  expect_identical(calls, 2L)
  expect_identical(readLines(dest), "payload")
  expect_length(list.files(dir, pattern = "\\.tmp$"), 0)
})

test_that("cache info lists files only, never subdirectories", {
  dir <- local_brfss_cache(2023)
  dir.create(file.path(dir, "stray-subdir"))
  info <- brfss_cache_info()
  expect_false("stray-subdir" %in% info$file)
  expect_true("brfss_2023.parquet" %in% info$file)
  expect_false(anyNA(info$size))
})

test_that("a failed catalog refresh stays due instead of being memoized", {
  # The year path had this defect and fixed it; the catalog path had
  # the identical one. A refresh that throws must not mark the asset
  # checked, or a catalog known not to match the manifest is served
  # silently for the rest of the session.
  dir <- local_brfss_cache(2023)
  asset <- "brfss_labels.parquet"
  writeLines("corrupt but present", file.path(dir, asset))
  local_mocked_bindings(
    manifest_sha256 = function(...) strrep("a", 64),
    download_to_cache = function(...) {
      cli::cli_abort("no network", class = "brfssdata_download_error")
    }
  )
  expect_true(asset_check_due(asset))
  suppressMessages(ensure_catalog_cached(asset, "label catalog"))
  expect_true(asset_check_due(asset))
})

test_that("a local-write failure keeps its classed condition", {
  # download_failure_hint() renders the directory into its bullet. Left
  # as a glue template, cli evaluated it in the signalling frame, found
  # no `dir` there, reached base::dir and died with an unclassed
  # coercion error, taking brfssdata_download_error with it.
  hint <- download_failure_hint(NULL, dir = file.path(tempdir(), "nope"))
  expect_false(any(grepl("{dir}", hint, fixed = TRUE)))
  raise <- function(bullets) {
    cli::cli_abort(c("Could not download.", bullets),
      class = "brfssdata_download_error")
  }
  err <- expect_error(raise(hint), class = "brfssdata_download_error")
  expect_match(conditionMessage(err), "local file-system failure")
})
