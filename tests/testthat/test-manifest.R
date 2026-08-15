test_that("brfss_years reads a fresh cached manifest without downloading", {
  local_brfss_manifest(c(2020, 2023, 2021))
  expect_identical(brfss_years(), c(2020L, 2021L, 2023L))
})

test_that("offline fallback actually reaches the bundled manifest", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  local_manifest_state()
  sentinel <- withr::local_tempfile(lines = '{"years": [1999]}')
  local_mocked_bindings(
    download_to_cache = function(...) {
      cli::cli_abort("offline", class = "brfssdata_download_error")
    },
    bundled_manifest_path = function() sentinel
  )
  expect_message(
    years <- brfss_years(),
    class = "brfssdata_manifest_note"
  )
  expect_identical(years, 1999L)
})

test_that("a stale manifest triggers one refresh attempt, then falls back", {
  dir <- local_brfss_manifest(c(2020, 2021))
  # Not every filesystem honors this; without a stale mtime the test
  # would fail for a reason that has nothing to do with the manifest.
  aged <- Sys.setFileTime(
    file.path(dir, "manifest.json"),
    Sys.time() - 2 * 86400
  )
  skip_if_not(isTRUE(aged), "cannot set file mtime on this filesystem")
  calls <- 0L
  local_mocked_bindings(
    download_to_cache = function(...) {
      calls <<- calls + 1L
      cli::cli_abort("offline", class = "brfssdata_download_error")
    }
  )
  expect_message(
    years <- brfss_years(),
    class = "brfssdata_manifest_note"
  )
  expect_identical(years, c(2020L, 2021L))
  expect_identical(calls, 1L)

  # A recent failure is remembered: the next call does not re-attempt.
  expect_identical(brfss_years(), c(2020L, 2021L))
  expect_identical(calls, 1L)

  # refresh = TRUE bypasses the memo.
  expect_message(
    brfss_years(refresh = TRUE),
    class = "brfssdata_manifest_note"
  )
  expect_identical(calls, 2L)
})

test_that("parse_manifest tolerates malformed files", {
  local_manifest_state()
  path <- withr::local_tempfile(lines = "not json at all")
  expect_identical(parse_manifest(path)$years, integer(0))
})

test_that("parse_manifest does not mistake other numbers for years", {
  local_manifest_state()
  path <- withr::local_tempfile(
    lines = '{"years": [2022, 2023], "generated": "2026-08-02"}'
  )
  expect_identical(parse_manifest(path)$years, c(2022L, 2023L))
})

test_that("parse_manifest normalizes a v1 manifest", {
  local_manifest_state()
  path <- withr::local_tempfile(lines = '{"years": [2022, 2023]}')
  m <- parse_manifest(path)
  expect_identical(m$schema_version, 1L)
  expect_null(m$files)
  expect_identical(m$years, c(2022L, 2023L))
})

test_that("parse_manifest reads v2 checksums and drops unusable entries", {
  local_manifest_state()
  path <- withr::local_tempfile(
    lines = '{
      "schema_version": 2,
      "years": [2023],
      "files": {
        "brfss_2023.parquet": {"sha256": "abc123", "size": 42},
        "no-hash.parquet": {"size": 7},
        "blank-hash.parquet": {"sha256": ""}
      }
    }'
  )
  m <- parse_manifest(path)
  expect_identical(m$schema_version, 2L)
  expect_identical(manifest_sha256("brfss_2023.parquet", m), "abc123")
  expect_identical(manifest_size("brfss_2023.parquet", m), 42)
  expect_null(manifest_sha256("no-hash.parquet", m))
  expect_null(manifest_sha256("blank-hash.parquet", m))
  expect_true(is.na(manifest_size("not-listed.parquet", m)))
})

test_that("manifest_json memoizes per file state and invalidates on change", {
  local_manifest_state()
  path <- withr::local_tempfile(lines = '{"years": [2023]}')
  expect_identical(manifest_json(path)$years, 2023L)

  # Prove the second call is served from the memo, not a re-parse: plant
  # a sentinel in the stored value and watch it come back.
  key <- normalizePath(path, mustWork = FALSE)
  memo <- manifest_state$json_memo
  memo[[key]]$value <- list(years = "sentinel")
  manifest_state$json_memo <- memo
  expect_identical(manifest_json(path)$years, "sentinel")

  # A rewritten file (different size, later mtime) is re-parsed.
  writeLines('{"years": [2022, 2023]}', path)
  bumped <- Sys.setFileTime(path, Sys.time() + 2)
  skip_if_not(isTRUE(bumped), "cannot set file mtime on this filesystem")
  expect_identical(manifest_json(path)$years, c(2022L, 2023L))
})

test_that("manifest_json keeps an unparseable file distinct from a missing one", {
  local_manifest_state()
  expect_null(manifest_json(file.path(tempdir(), "no-such-manifest.json")))
  expect_length(manifest_state$json_memo, 0)

  path <- withr::local_tempfile(lines = "not json at all")
  expect_null(manifest_json(path))
  # The failed parse is memoized (keyed to these bytes), so repeated
  # freshness checks on a corrupt cache do not re-parse it.
  key <- normalizePath(path, mustWork = FALSE)
  expect_true(key %in% names(manifest_state$json_memo))
})

test_that("read_manifest_cached reads the cache without touching the network", {
  local_brfss_manifest(2023)
  m <- read_manifest_cached()
  expect_identical(m$years, 2023L)
  expect_identical(m$schema_version, 2L)
})

test_that("read_manifest_cached falls back to the bundled manifest", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  sentinel <- withr::local_tempfile(lines = '{"years": [1999]}')
  local_mocked_bindings(bundled_manifest_path = function() sentinel)
  expect_identical(read_manifest_cached()$years, 1999L)
})

# The manifest is the one asset fetched without an expected hash, and
# download_to_cache() accepts any non-empty payload, so the error page a
# captive portal or proxy serves with HTTP 200 can land in the cache
# looking brand new. Freshness therefore has to read the content: a
# present-but-unparseable file must never beat the bundled copy, or
# brfss_years() empties and every manifest_sha256() lookup returns NULL,
# which would let all later downloads proceed unverified for a day.
local_corrupt_manifest <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_options(brfssdata.cache_dir = dir, .local_envir = env)
  local_manifest_state(env)
  writeLines(
    "<html><body>Sign in to this network to continue</body></html>",
    file.path(dir, "manifest.json")
  )
  dir
}

test_that("a fresh but corrupt cached manifest falls back to the bundle", {
  local_corrupt_manifest()
  sentinel <- withr::local_tempfile(lines = '{"years": [1999]}')
  local_mocked_bindings(
    download_to_cache = function(...) {
      cli::cli_abort("offline", class = "brfssdata_download_error")
    },
    bundled_manifest_path = function() sentinel
  )
  # Two notes: the refresh failed, and the cached copy is unreadable.
  expect_message(
    expect_message(
      years <- brfss_years(),
      class = "brfssdata_manifest_note"
    ),
    class = "brfssdata_manifest_note"
  )
  expect_identical(years, 1999L)
})

test_that("an unreadable cached manifest names the repair command", {
  local_corrupt_manifest()
  sentinel <- withr::local_tempfile(lines = '{"years": [1999]}')
  local_mocked_bindings(bundled_manifest_path = function() sentinel)
  # read_manifest_cached() never touches the network, so this is the
  # unreadable-cache note on its own.
  expect_message(m <- read_manifest_cached(), "unreadable")
  expect_identical(m$years, 1999L)
  # Once per session, not once per checksum lookup.
  expect_no_message(read_manifest_cached())
})

test_that("a corrupt cached manifest is not treated as fresh", {
  local_corrupt_manifest()
  calls <- 0L
  local_mocked_bindings(
    download_to_cache = function(url, dest, ...) {
      calls <<- calls + 1L
      writeLines('{"years": [2020, 2021]}', dest)
      dest
    }
  )
  expect_identical(brfss_years(), c(2020L, 2021L))
  expect_identical(calls, 1L)
  # The repaired copy is fresh, so the next call reads it in silence.
  expect_no_message(expect_identical(brfss_years(), c(2020L, 2021L)))
  expect_identical(calls, 1L)
})

test_that("a refresh that returns junk keeps the cached manifest", {
  dir <- local_brfss_manifest(c(2020, 2021))
  local_mocked_bindings(
    download_to_cache = function(url, dest, ...) {
      writeLines("<html>proxy error</html>", dest)
      dest
    }
  )
  expect_message(
    years <- brfss_years(refresh = TRUE),
    class = "brfssdata_manifest_note"
  )
  expect_identical(years, c(2020L, 2021L))
  expect_identical(read_manifest_cached()$years, c(2020L, 2021L))
  # A junk payload counts as a failed refresh, memo and all, and leaves
  # nothing staged behind in the cache.
  expect_false(is.null(manifest_state$last_failure))
  expect_length(list.files(dir, pattern = "^manifest-"), 0L)
})

test_that("fixture manifests carry real hashes of the fixture files", {
  dir <- local_brfss_cache(2023)
  m <- read_manifest_cached()
  expect_identical(
    manifest_sha256("brfss_2023.parquet", m),
    cli::hash_file_sha256(file.path(dir, "brfss_2023.parquet"))
  )
})

test_that("a successful refresh clears the failure memo", {
  local_brfss_manifest(2020)
  manifest_state$last_failure <- Sys.time() - 10
  local_mocked_bindings(
    download_to_cache = function(url, dest, ...) {
      writeLines('{"years": [2020]}', dest)
      dest
    }
  )
  brfss_years(refresh = TRUE)
  expect_null(manifest_state$last_failure)
})

test_that("brfss_years validates its boolean arguments", {
  local_brfss_manifest(2023)
  expect_error(brfss_years(refresh = "x"), class = "brfssdata_bad_refresh_arg")
  expect_error(brfss_years(download = 1), class = "brfssdata_bad_download_arg")
  expect_error(brfss_years(quiet = NULL), class = "brfssdata_bad_quiet_arg")
  expect_error(brfss_years(refresh = NA), class = "brfssdata_bad_bool_arg")
})

test_that("brfss_years(download = FALSE) never touches the network", {
  dir <- local_brfss_manifest(c(2020, 2021))
  aged <- Sys.setFileTime(
    file.path(dir, "manifest.json"),
    Sys.time() - 2 * 86400
  )
  skip_if_not(isTRUE(aged), "cannot set file mtime on this filesystem")
  # guard_network() is still installed: any attempt fails the test.
  expect_identical(brfss_years(download = FALSE), c(2020L, 2021L))

  # download = FALSE is the stronger promise, so refresh cannot override
  # it, and the skipped refresh is reported rather than assumed.
  expect_message(
    expect_identical(
      brfss_years(refresh = TRUE, download = FALSE),
      c(2020L, 2021L)
    ),
    class = "brfssdata_manifest_note"
  )
  expect_no_message(
    brfss_years(refresh = TRUE, download = FALSE, quiet = TRUE),
    class = "brfssdata_manifest_note"
  )
})

test_that("brfss_years(quiet = TRUE) silences the fallback note", {
  dir <- local_brfss_manifest(c(2020, 2021))
  aged <- Sys.setFileTime(
    file.path(dir, "manifest.json"),
    Sys.time() - 2 * 86400
  )
  skip_if_not(isTRUE(aged), "cannot set file mtime on this filesystem")
  local_mocked_bindings(
    download_to_cache = function(...) {
      cli::cli_abort("offline", class = "brfssdata_download_error")
    }
  )
  expect_no_message(
    years <- brfss_years(quiet = TRUE),
    class = "brfssdata_manifest_note"
  )
  expect_identical(years, c(2020L, 2021L))
})

# These two run as a pair, in file order: the first deliberately drives
# the failure memo inside a fixture scope, the second proves the scope
# restored it. This is the contract that keeps devtools::test() from
# leaving a session that skips real manifest refreshes for a day.
test_that("a test can drive the manifest failure memo", {
  local_brfss_manifest(2020)
  manifest_state$last_failure <- Sys.time()
  expect_false(is.null(manifest_state$last_failure))
})

test_that("the manifest failure memo was restored by the fixture scope", {
  expect_null(manifest_state$last_failure)
})
