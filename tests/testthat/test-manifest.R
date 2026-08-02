test_that("brfss_years reads a fresh cached manifest without downloading", {
  local_brfss_manifest(c(2020, 2023, 2021))
  expect_identical(brfss_years(), c(2020L, 2021L, 2023L))
})

test_that("offline fallback actually reaches the bundled manifest", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  reset_manifest_state()
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
  path <- withr::local_tempfile(lines = "not json at all")
  expect_identical(parse_manifest(path)$years, integer(0))
})

test_that("parse_manifest does not mistake other numbers for years", {
  path <- withr::local_tempfile(
    lines = '{"years": [2022, 2023], "generated": "2026-08-02"}'
  )
  expect_identical(parse_manifest(path)$years, c(2022L, 2023L))
})
