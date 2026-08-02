test_that("brfss_labels filters by variable and year", {
  dir <- local_brfss_cache(2023)
  write_fixture_labels(dir)
  out <- brfss_labels("GENHLTH", years = 2023)
  expect_identical(nrow(out), 5L)
  expect_identical(out$label[out$code == 1], "Excellent")
})

test_that("brfss_labels matches variables case-insensitively", {
  dir <- local_brfss_cache(2023)
  write_fixture_labels(dir)
  out <- brfss_labels("genhlth", years = 2023)
  expect_identical(nrow(out), 5L)
  expect_identical(unique(out$variable), "GENHLTH")
})

test_that("labels = TRUE converts fully mapped variables to factors", {
  dir <- local_brfss_cache(2023)
  write_fixture_labels(dir)
  dat <- read_brfss(2023, vars = "GENHLTH", quiet = TRUE, labels = TRUE)
  expect_s3_class(dat$GENHLTH, "factor")
  expect_identical(
    levels(dat$GENHLTH),
    c("Excellent", "Very good", "Good", "Fair", "Poor")
  )
  expect_identical(sort(unique(dat$year)), 2023L)
})

test_that("incomplete formats keep their numeric codes", {
  dir <- local_brfss_cache(2023, extra = list("2023" = "PHYSHLTH"))
  write_fixture_labels(dir)
  dat <- read_brfss(2023, quiet = TRUE, labels = TRUE)
  expect_type(dat$PHYSHLTH, "integer")
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
  expect_type(dat$GENHLTH, "integer")
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
  expect_type(dat$DRIFTVAR, "integer")

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
  local_brfss_cache(2023)
  expect_error(
    brfss_labels(download = FALSE),
    class = "brfssdata_not_cached"
  )
})
