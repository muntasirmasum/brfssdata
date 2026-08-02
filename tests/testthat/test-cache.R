test_that("cache dir honors the option override", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  expect_identical(brfss_cache_dir(), dir)
})

test_that("cache info lists files with parsed years", {
  local_brfss_cache(c(2022, 2023))
  info <- brfss_cache_info()
  expect_true(all(c("brfss_2022.parquet", "brfss_2023.parquet") %in%
    info$file))
  expect_true(all(c(2022L, 2023L) %in% info$year))
  expect_true(all(info$size[info$year %in% 2022:2023] > 0))
})

test_that("cache clear removes only the requested years", {
  local_brfss_cache(c(2022, 2023))
  brfss_cache_clear(years = 2022)
  info <- brfss_cache_info()
  expect_false("brfss_2022.parquet" %in% info$file)
  expect_true("brfss_2023.parquet" %in% info$file)

  brfss_cache_clear()
  expect_identical(nrow(brfss_cache_info()), 0L)
})

test_that("failed downloads raise a classed error and leave no debris", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  dest <- file.path(dir, "brfss_2023.parquet")
  expect_error(
    download_to_cache("file://does/not/exist.parquet", dest, quiet = TRUE),
    class = "brfssdata_download_error"
  )
  expect_false(file.exists(dest))
  expect_length(list.files(dir, pattern = "\\.tmp$"), 0)
})
