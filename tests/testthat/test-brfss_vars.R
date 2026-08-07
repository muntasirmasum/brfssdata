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

test_that("uncached catalog with download = FALSE serves the snapshot", {
  local_brfss_manifest(2020)
  expect_message(
    out <- brfss_vars("smok", download = FALSE),
    class = "brfssdata_bundled_fallback_note"
  )
  # The bundled snapshot is the real variable catalog.
  expect_gt(nrow(out), 0)
})

test_that("an invalid regular expression is rejected with its cause", {
  local_brfss_cache(2020, catalog = TRUE)
  expect_error(brfss_vars("("), class = "brfssdata_bad_pattern")
})

test_that("a multi-element pattern is rejected, not silently truncated", {
  # grepl() would use only the first element; with its warning
  # suppressed for the invalid-regex case, the truncation was silent.
  local_brfss_cache(2020, catalog = TRUE)
  expect_error(
    brfss_vars(c("GENHLTH", "SMOK")),
    class = "brfssdata_bad_pattern"
  )
})

test_that("a malformed years argument is rejected", {
  local_brfss_cache(2020, catalog = TRUE)
  expect_error(
    brfss_vars(years = "recent"),
    class = "brfssdata_bad_years_arg"
  )
  expect_error(
    brfss_vars(years = NA_real_),
    class = "brfssdata_bad_years_arg"
  )
})
