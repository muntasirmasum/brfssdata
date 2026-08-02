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
  expect_message(brfss_cache_clear(), class = "brfssdata_cache_note")
  expect_message(brfss_cache_clear(), class = "brfssdata_cache_note")
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
  # machine that has curl installed, which is every machine that tests
  # this package.
  for (curl_available in c(TRUE, FALSE)) {
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
