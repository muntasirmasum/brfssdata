test_that("validate_years rejects malformed input", {
  local_brfss_manifest(2020:2023)
  expect_error(validate_years("2023"), class = "rlang_error")
  expect_error(validate_years(numeric(0)))
  expect_error(validate_years(2022.5))
  expect_error(validate_years(NA_integer_))
})

test_that("validate_years rejects unpublished years", {
  local_brfss_manifest(2020:2023)
  expect_error(validate_years(1999), class = "brfssdata_bad_year")
  expect_error(validate_years(c(2022, 2030)), class = "brfssdata_bad_year")
})

test_that("validate_years sorts, deduplicates, and passes valid years", {
  local_brfss_manifest(2011:2024)
  expect_identical(validate_years(c(2023, 2022, 2023)), c(2022L, 2023L))
})

test_that("validate_years fails informatively with no published years", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  writeLines('{"years": []}', file.path(dir, "manifest.json"))
  expect_error(validate_years(2023), class = "brfssdata_no_data")
})

test_that("identifier and literal quoting are injection-safe", {
  expect_identical(quote_ident('a"b'), '"a""b"')
  expect_identical(quote_literal("it's"), "'it''s'")
})

test_that("summarize_years collapses runs", {
  expect_identical(summarize_years(integer(0)), "")
  expect_identical(summarize_years(2020L), "2020")
  expect_identical(
    summarize_years(c(2011:2013, 2020L)),
    "2011-2013, 2020"
  )
})
