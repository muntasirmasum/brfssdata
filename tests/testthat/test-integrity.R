# Download verification and cache self-healing. The README promises
# checksummed artifacts; these tests are what make that promise true in
# code rather than prose.

test_that("a download with a matching checksum lands", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  src <- withr::local_tempfile()
  writeLines("payload", src)
  dest <- file.path(dir, "brfss_2023.parquet")

  download_to_cache(
    local_file_url(paste0("file://", src)),
    dest,
    quiet = TRUE,
    expected_sha256 = cli::hash_file_sha256(src)
  )
  expect_true(file.exists(dest))
})

test_that("a checksum mismatch retries once, then fails with no debris", {
  skip_if_not(has_curl())
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  attempts <- 0L
  local_mocked_bindings(
    curl_download = function(url, destfile, ...) {
      attempts <<- attempts + 1L
      writeLines("wrong bytes", destfile)
      destfile
    },
    .package = "curl"
  )
  dest <- file.path(dir, "brfss_2023.parquet")

  err <- expect_error(
    download_to_cache(
      local_file_url("file://mocked"),
      dest,
      quiet = TRUE,
      expected_sha256 = strrep("0", 64)
    ),
    class = "brfssdata_checksum_error"
  )
  # Subclassing keeps every existing brfssdata_download_error handler
  # (read_manifest's fallback, callers' tryCatch) working unchanged.
  expect_s3_class(err, "brfssdata_download_error")
  expect_identical(attempts, 2L)
  expect_false(file.exists(dest))
  expect_length(list.files(dir, pattern = "\\.tmp$"), 0)
})

test_that("a transient corruption is healed by the retry", {
  skip_if_not(has_curl())
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  good <- withr::local_tempfile()
  writeLines("right bytes", good)
  attempts <- 0L
  local_mocked_bindings(
    curl_download = function(url, destfile, ...) {
      attempts <<- attempts + 1L
      if (attempts == 1L) {
        writeLines("truncated", destfile)
      } else {
        file.copy(good, destfile, overwrite = TRUE)
      }
      destfile
    },
    .package = "curl"
  )
  dest <- file.path(dir, "brfss_2023.parquet")

  download_to_cache(
    local_file_url("file://mocked"),
    dest,
    quiet = TRUE,
    expected_sha256 = cli::hash_file_sha256(good)
  )
  expect_identical(attempts, 2L)
  expect_identical(readLines(dest), "right bytes")
})

test_that("a manifest without hashes downloads unverified, and says so", {
  local_brfss_manifest(2023, schema = 1)
  local_mocked_bindings(
    download_to_cache = function(url, dest, ...) {
      write_fixture_year(2023, dirname(dest))
      dest
    }
  )
  expect_message(
    dat <- read_brfss(2023, quiet = FALSE),
    class = "brfssdata_unverified_note"
  )
  expect_gt(nrow(dat), 0)
})

test_that("quiet suppresses the unverified-download note", {
  local_brfss_manifest(2023, schema = 1)
  local_mocked_bindings(
    download_to_cache = function(url, dest, ...) {
      write_fixture_year(2023, dirname(dest))
      dest
    }
  )
  expect_no_message(
    read_brfss(2023, quiet = TRUE),
    class = "brfssdata_unverified_note"
  )
})

test_that("verified downloads pass the manifest hash through", {
  local_brfss_manifest(integer(0))
  dir <- brfss_cache_dir()
  # Build the year first so the fixture manifest can carry its real hash,
  # then delete the parquet so the read has to "download" it.
  write_fixture_year(2023, dir)
  write_fixture_manifest(dir, 2023)
  real <- file.path(dir, "brfss_2023.parquet")
  keep <- withr::local_tempfile()
  file.copy(real, keep)
  unlink(real)

  seen <- NULL
  local_mocked_bindings(
    download_to_cache = function(url, dest, ..., expected_sha256 = NULL) {
      seen <<- expected_sha256
      file.copy(keep, dest)
      dest
    }
  )
  read_brfss(2023, quiet = TRUE)
  expect_identical(seen, cli::hash_file_sha256(keep))
})

test_that("a size-mismatched cached file is re-downloaded verified", {
  dir <- local_brfss_cache(2023)
  path <- file.path(dir, "brfss_2023.parquet")
  keep <- withr::local_tempfile()
  file.copy(path, keep)
  # Truncate the cached copy; the manifest still records the true size.
  writeBin(readBin(path, "raw", 10), path)

  called <- FALSE
  local_mocked_bindings(
    download_to_cache = function(url, dest, ..., expected_sha256 = NULL) {
      called <<- TRUE
      file.copy(keep, dest, overwrite = TRUE)
      dest
    }
  )
  dat <- read_brfss(2023, quiet = TRUE)
  expect_true(called)
  expect_gt(nrow(dat), 0)
})

test_that("download = FALSE never deletes a damaged cached file", {
  dir <- local_brfss_cache(2023)
  path <- file.path(dir, "brfss_2023.parquet")
  writeBin(readBin(path, "raw", 10), path)

  # The file is damaged but irreplaceable under download = FALSE; it
  # must be left in place (the query path names the remedy instead).
  expect_error(read_brfss(2023, quiet = TRUE, download = FALSE))
  expect_true(file.exists(path))
})

test_that("a corrupt cached parquet raises a classed error with the remedy", {
  dir <- local_brfss_cache(2023)
  path <- file.path(dir, "brfss_2023.parquet")
  # Corrupt the file while preserving its size (zero the leading magic
  # bytes), so the size-heal cannot catch it and the failure surfaces at
  # query time.
  bytes <- readBin(path, "raw", file.size(path))
  bytes[seq_len(min(100L, length(bytes)))] <- as.raw(0L)
  writeBin(bytes, path)

  err <- expect_error(
    read_brfss(2023, quiet = TRUE),
    class = "brfssdata_corrupt_cache"
  )
  expect_match(conditionMessage(err), "brfss_cache_clear")
  expect_match(conditionMessage(err), "2023")
})

test_that("a genuine query error is rethrown, not blamed on the cache", {
  dir <- local_brfss_cache(2023)
  con <- duckdb_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  # The cached file is healthy, so the probe finds nothing to blame and
  # the original error must come through untouched.
  err <- tryCatch(
    abort_corrupt_or_rethrow(
      simpleError("out of memory"),
      file.path(dir, "brfss_2023.parquet"),
      con,
      rlang::caller_env()
    ),
    error = function(e) e
  )
  expect_false(inherits(err, "brfssdata_corrupt_cache"))
  expect_match(conditionMessage(err), "out of memory")
})

test_that("a stale catalog is refreshed when the manifest hash moves", {
  dir <- local_brfss_cache(2020, catalog = TRUE)
  # Replace the cached catalog with different content; the manifest
  # still records the published hash, so a refresh is due.
  write_fixture_parquet(
    data.frame(
      variable = "STALE",
      label = "old copy",
      year = 2019L,
      stringsAsFactors = FALSE
    ),
    file.path(dir, "brfss_variables.parquet")
  )
  called <- FALSE
  local_mocked_bindings(
    download_to_cache = function(url, dest, ..., expected_sha256 = NULL) {
      called <<- TRUE
      expect_false(is.null(expected_sha256))
      write_fixture_catalog(dirname(dest))
      dest
    }
  )
  out <- brfss_vars("smok")
  expect_true(called)
  expect_identical(out$variable, "SMOKE100")
})

test_that("the catalog freshness check runs at most once per day", {
  dir <- local_brfss_cache(2020, catalog = TRUE)
  # First call performs the check (hash matches, nothing downloads) and
  # memoizes; a second call within the day must not even re-hash.
  brfss_vars("smok")
  expect_false(catalog_check_due("brfss_variables.parquet"))
  brfss_vars("smok")
  succeed()
})

test_that("a catalog with no manifest entry is kept silently", {
  dir <- local_brfss_cache(2023, label_catalog = FALSE)
  # Written after the manifest, so the labels catalog has no files
  # entry: no hash, no verdict, no download (guard_network() proves it).
  write_fixture_labels(dir)
  out <- brfss_labels("GENHLTH", years = 2023)
  expect_identical(nrow(out), 7L)
})
