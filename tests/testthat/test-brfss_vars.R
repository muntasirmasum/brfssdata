test_that("brfss_vars searches names and labels case-insensitively", {
  local_brfss_cache(2020, catalog = TRUE)
  out <- brfss_vars("smok")
  expect_identical(out$variable, "SMOKE100")
  out2 <- brfss_vars("general health")
  expect_identical(out2$variable, "GENHLTH")
})

test_that("variables with missing labels are found, not dropped", {
  local_brfss_cache(2020, catalog = TRUE)
  out <- brfss_vars("MYSTVAR")
  expect_identical(out$variable, "MYSTVAR")
  expect_true(is.na(out$label))

  everything <- brfss_vars()
  expect_true("MYSTVAR" %in% everything$variable)
})

test_that("label drift collapses to one row with the latest label", {
  local_brfss_cache(2020, catalog = TRUE)
  out <- brfss_vars("GENHLTH")
  expect_identical(nrow(out), 1L)
  expect_identical(out$label, "General Health Status")
  expect_identical(out$years, "2019-2020, 2022")
})

test_that("no-match searches return an empty tibble, not an error", {
  local_brfss_cache(2020, catalog = TRUE)
  out <- brfss_vars("zzz_no_such_thing")
  expect_s3_class(out, "tbl_df")
  expect_identical(nrow(out), 0L)
  expect_identical(names(out), c("variable", "label", "years"))

  out2 <- brfss_vars(years = 1999)
  expect_identical(nrow(out2), 0L)
})

test_that("uncached catalog with download = FALSE errors cleanly", {
  local_brfss_manifest(2020)
  expect_error(
    brfss_vars("smok", download = FALSE),
    class = "brfssdata_not_cached"
  )
})
