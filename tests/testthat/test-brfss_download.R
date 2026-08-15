# brfss_download() is what makes "everything after the first pull works
# offline" true: one call caches years, the manifest, and both catalogs.

mock_asset_downloads <- function(env = parent.frame()) {
  local_mocked_bindings(
    download_to_cache = function(url, dest, ...) {
      if (grepl("brfss_2023[.]parquet$", dest)) {
        write_fixture_year(2023, dirname(dest))
      } else if (grepl("brfss_variables[.]parquet$", dest)) {
        write_fixture_catalog(dirname(dest))
      } else if (grepl("brfss_labels[.]parquet$", dest)) {
        write_fixture_labels(dirname(dest))
      } else if (grepl("brfss_crosswalk[.]parquet$", dest)) {
        write_fixture_crosswalk(dirname(dest))
      } else if (grepl("brfss_year_info[.]parquet$", dest)) {
        write_fixture_year_info(dirname(dest))
      } else {
        stop("unexpected asset in test: ", dest)
      }
      dest
    },
    .env = env
  )
}

test_that("brfss_download caches years and catalogs", {
  local_brfss_manifest(2023)
  mock_asset_downloads()
  suppressMessages(brfss_download(2023))
  info <- brfss_cache_info()
  expect_true(all(
    c(
      "brfss_2023.parquet",
      "brfss_variables.parquet",
      "brfss_labels.parquet",
      "brfss_crosswalk.parquet",
      "brfss_year_info.parquet",
      "manifest.json"
    ) %in%
      info$file
  ))
})

test_that("brfss_download with years = NULL fetches metadata only", {
  local_brfss_manifest(2023)
  mock_asset_downloads()
  suppressMessages(brfss_download())
  info <- brfss_cache_info()
  expect_false("brfss_2023.parquet" %in% info$file)
  expect_true("brfss_variables.parquet" %in% info$file)
  expect_true("brfss_labels.parquet" %in% info$file)
})

test_that("already-cached files are not re-downloaded", {
  # guard_network() stays active: any download attempt fails the test.
  local_brfss_cache(2023, catalog = TRUE)
  out <- suppressMessages(brfss_download(2023))
  expect_s3_class(out, "tbl_df")
})

test_that("quiet suppresses the summary", {
  local_brfss_cache(2023, catalog = TRUE)
  expect_no_message(brfss_download(2023, quiet = TRUE))
})

test_that("quiet still reports a cached year re-fetched for integrity", {
  # A republished asset changes the bytes under a stable URL. Progress
  # narration is silenceable; the fact that the input changed is not.
  local_brfss_cache(2023, catalog = TRUE)
  # One byte appended puts the file's size at odds with the manifest.
  cat("x", file = cache_path("brfss_2023.parquet"), append = TRUE)
  local_mocked_bindings(
    download_to_cache = function(...) {
      cli::cli_abort("offline", class = "brfssdata_download_error")
    }
  )
  expect_message(
    expect_error(
      brfss_download(2023, quiet = TRUE),
      class = "brfssdata_download_error"
    ),
    class = "brfssdata_cache_note"
  )
})
