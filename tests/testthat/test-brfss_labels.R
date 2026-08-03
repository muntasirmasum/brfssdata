test_that("brfss_labels filters by variable and year", {
  dir <- local_brfss_cache(2023)
  write_fixture_labels(dir)
  out <- brfss_labels("GENHLTH", years = 2023)
  expect_identical(nrow(out), 7L)
  expect_identical(out$label[out$code == 1], "Excellent")
})

test_that("brfss_labels matches variables case-insensitively", {
  dir <- local_brfss_cache(2023)
  write_fixture_labels(dir)
  out <- brfss_labels("genhlth", years = 2023)
  expect_identical(nrow(out), 7L)
  expect_identical(unique(out$variable), "GENHLTH")
})

test_that("labels = TRUE converts fully mapped variables to factors", {
  dir <- local_brfss_cache(2023)
  write_fixture_labels(dir)
  dat <- read_brfss(2023, vars = "GENHLTH", quiet = TRUE, labels = TRUE)
  expect_s3_class(dat$GENHLTH, "factor")
  expect_identical(
    levels(dat$GENHLTH),
    c(
      "Excellent",
      "Very good",
      "Good",
      "Fair",
      "Poor",
      "Don't know/Not Sure",
      "Refused"
    )
  )
  expect_identical(sort(unique(dat$year)), 2023L)
})

test_that("incomplete formats keep their numeric codes", {
  dir <- local_brfss_cache(2023)
  write_fixture_labels(dir)
  dat <- read_brfss(2023, quiet = TRUE, labels = TRUE)
  # The contract is "not converted", not a storage type: real files carry
  # doubles, and a factor here would be the bug.
  expect_false(is.factor(dat$PHYSHLTH))
  expect_true(is.numeric(dat$PHYSHLTH))
})

test_that("observed values outside the map block conversion", {
  dir <- local_brfss_cache(integer(0))
  df <- data.frame(
    year = 2023L,
    psu = 1:4,
    ststr = 1L,
    wt = 100,
    GENHLTH = c(1L, 2L, 3L, 42L), # 42 is unmapped
    check.names = FALSE
  )
  names(df) <- c("year", "_PSU", "_STSTR", "_LLCPWT", "GENHLTH")
  write_fixture_parquet(df, file.path(dir, "brfss_2023.parquet"))
  writeLines('{"years": [2023]}', file.path(dir, "manifest.json"))
  write_fixture_labels(dir)
  dat <- read_brfss(2023, quiet = TRUE, labels = TRUE)
  expect_false(is.factor(dat$GENHLTH))
  expect_true(is.numeric(dat$GENHLTH))
})

test_that("code sets that drift across years block conversion", {
  dir <- local_brfss_cache(
    c(2022, 2023),
    extra = list(
      "2022" = "DRIFTVAR",
      "2023" = "DRIFTVAR"
    )
  )
  write_fixture_labels(dir)
  dat <- read_brfss(2022:2023, quiet = TRUE, labels = TRUE)
  expect_false(is.factor(dat$DRIFTVAR))
  expect_true(is.numeric(dat$DRIFTVAR))

  # But single-year requests convert with that year's map.
  one <- read_brfss(2023, quiet = TRUE, labels = TRUE)
  expect_s3_class(one$DRIFTVAR, "factor")
})

test_that("design objects can carry labels without touching design vars", {
  dir <- local_brfss_cache(2023)
  write_fixture_labels(dir)
  des <- brfss_design(2023, vars = "GENHLTH", quiet = TRUE, labels = TRUE)
  expect_s3_class(des$variables$GENHLTH, "factor")
  expect_type(des$variables$brfss_wt, "double")
})

test_that("uncached labels with download = FALSE error cleanly", {
  local_brfss_cache(2023, label_catalog = FALSE)
  expect_error(
    brfss_labels(download = FALSE),
    class = "brfssdata_not_cached"
  )
})

test_that("a map that labels two codes the same keeps its numeric codes", {
  dir <- local_brfss_cache(2023, extra = list("2023" = "DUPLABEL"))
  write_fixture_labels(dir)
  dat <- read_brfss(2023, quiet = TRUE, labels = TRUE)
  # factor() would merge codes 0 and 1 into one "Same" level
  expect_false(is.factor(dat$DUPLABEL))
  expect_length(unique(dat$DUPLABEL[!is.na(dat$DUPLABEL)]), 2)
  # the clean map in the same call still converts
  expect_s3_class(dat$GENHLTH, "factor")
})

test_that("labels = TRUE respects download = FALSE", {
  local_brfss_cache(2023, label_catalog = FALSE)
  expect_error(
    read_brfss(2023, quiet = TRUE, labels = TRUE, download = FALSE),
    class = "brfssdata_not_cached"
  )
})

test_that("labels = 'both' keeps codes in the level text", {
  local_brfss_cache(2023)
  dat <- read_brfss(2023, vars = "GENHLTH", quiet = TRUE, labels = "both")
  expect_s3_class(dat$GENHLTH, "factor")
  expect_identical(
    levels(dat$GENHLTH)[[1]],
    "[1] Excellent"
  )
  expect_true("[7] Don't know/Not Sure" %in% levels(dat$GENHLTH))
})

test_that("'both' mode obeys the same safety rules", {
  local_brfss_cache(2023, extra = list("2023" = "DUPLABEL"))
  dat <- read_brfss(2023, quiet = TRUE, labels = "both")
  expect_false(is.factor(dat$DUPLABEL))
})

test_that("an invalid labels value is rejected", {
  local_brfss_cache(2023)
  expect_error(
    read_brfss(2023, quiet = TRUE, labels = "yes"),
    class = "brfssdata_bad_labels_arg"
  )
})

test_that("semantic label drift warns; identical wording stays silent", {
  local_brfss_cache(
    c(2022, 2023),
    extra = list("2022" = "SEMDRIFT", "2023" = "SEMDRIFT")
  )
  expect_warning(
    dat <- read_brfss(2022:2023, quiet = TRUE, labels = TRUE),
    class = "brfssdata_label_drift_warning"
  )
  expect_s3_class(dat$SEMDRIFT, "factor")
  expect_true("Quit over a year ago" %in% levels(dat$SEMDRIFT))

  # GENHLTH spans the same years with identical wording: no warning.
  expect_no_warning(
    read_brfss(2022:2023, vars = "GENHLTH", quiet = TRUE, labels = TRUE)
  )
})

test_that("a numeric vars argument errors with a year hint", {
  local_brfss_cache(2023)
  err <- expect_error(brfss_labels(2023), class = "brfssdata_bad_vars_arg")
  expect_match(conditionMessage(err), "years")
})

test_that("a malformed years argument is rejected", {
  local_brfss_cache(2023)
  expect_error(
    brfss_labels("GENHLTH", years = "recent"),
    class = "brfssdata_bad_years_arg"
  )
})

test_that("an empty lookup returns zero rows and says so", {
  local_brfss_cache(2023)
  expect_message(
    out <- brfss_labels("NOSUCHVAR"),
    class = "brfssdata_empty_result"
  )
  expect_identical(nrow(out), 0L)
})

test_that("a matching lookup stays silent", {
  local_brfss_cache(2023)
  expect_no_message(
    brfss_labels("GENHLTH", years = 2023),
    class = "brfssdata_empty_result"
  )
})
