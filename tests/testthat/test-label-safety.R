# CDC's SAS format libraries are not always a clean one-to-one map.
# factor(levels = , labels = ) resolves a repeated code silently by row
# order and merges a repeated label into one level, so both produce a
# plausible-looking, wrong variable. These guard the fallback to numeric
# codes, which is what the raw CDC file would have given anyway.

write_labels_catalog <- function(dir, rows) {
  write_fixture_parquet(rows, file.path(dir, "brfss_labels.parquet"))
}

one_year_fixture <- function(dir, var, values) {
  n <- length(values)
  df <- data.frame(
    year = 2023L,
    psu = seq_len(n),
    ststr = rep(1:2, length.out = n),
    wt = rep(100, n),
    v = values,
    check.names = FALSE
  )
  names(df) <- c("year", "_PSU", "_STSTR", "_LLCPWT", var)
  write_fixture_parquet(df, file.path(dir, "brfss_2023.parquet"))
  writeLines('{"years": [2023]}', file.path(dir, "manifest.json"))
}

test_that("a code carrying two different labels keeps its numeric codes", {
  dir <- local_brfss_cache(integer(0))
  one_year_fixture(dir, "RISKVAR", c(1L, 2L, 1L, 2L))
  # Shaped like _RFSMOK2 in 2001, where code 1 is mapped to both "YES"
  # and "NO" by two different formats in the same year. Picking either
  # by row order can invert the variable's meaning.
  write_labels_catalog(
    dir,
    data.frame(
      year = 2023L,
      variable = "RISKVAR",
      code = c(1L, 1L, 2L, 2L),
      label = c("YES", "NO", "NO", "YES"),
      complete = TRUE,
      stringsAsFactors = FALSE
    )
  )

  dat <- read_brfss(2023, quiet = TRUE, labels = TRUE)
  expect_false(is.factor(dat$RISKVAR))
  expect_identical(sort(unique(dat$RISKVAR)), c(1L, 2L))
})

test_that("an empty or missing label keeps its numeric codes", {
  dir <- local_brfss_cache(integer(0))
  one_year_fixture(dir, "GAPVAR", c(1L, 2L, 3L))
  write_labels_catalog(
    dir,
    data.frame(
      year = 2023L,
      variable = "GAPVAR",
      code = 1:3,
      label = c("Yes", "", NA_character_),
      complete = TRUE,
      stringsAsFactors = FALSE
    )
  )

  dat <- read_brfss(2023, quiet = TRUE, labels = TRUE)
  expect_false(is.factor(dat$GAPVAR))
})

test_that("a clean one-to-one map still converts", {
  dir <- local_brfss_cache(integer(0))
  one_year_fixture(dir, "CLEANVAR", c(1L, 2L, 3L))
  write_labels_catalog(
    dir,
    data.frame(
      year = 2023L,
      variable = "CLEANVAR",
      code = 1:3,
      label = c("Low", "Middle", "High"),
      complete = TRUE,
      stringsAsFactors = FALSE
    )
  )

  dat <- read_brfss(2023, quiet = TRUE, labels = TRUE)
  expect_s3_class(dat$CLEANVAR, "factor")
  expect_identical(levels(dat$CLEANVAR), c("Low", "Middle", "High"))
})

test_that("labels never convert the columns the design is built on", {
  dir <- local_brfss_cache(2023)
  # A format for the stratum variable itself. Turning `_STSTR` or its
  # syntactic copy into a factor would corrupt the survey design.
  write_labels_catalog(
    dir,
    data.frame(
      year = 2023L,
      variable = c(rep("GENHLTH", 5), "_STSTR", "_STSTR", "_STSTR"),
      code = c(1:5, 1L, 2L, 3L),
      label = c(
        "Excellent",
        "Very good",
        "Good",
        "Fair",
        "Poor",
        "Stratum A",
        "Stratum B",
        "Stratum C"
      ),
      complete = TRUE,
      stringsAsFactors = FALSE
    )
  )

  des <- brfss_design(2023, quiet = TRUE, labels = TRUE)
  v <- des$variables
  expect_false(is.factor(v$`_STSTR`))
  expect_false(is.factor(v$brfss_strata))
  expect_false(is.factor(v$brfss_psu))
  expect_false(is.factor(v$brfss_wt))
  # a normal analysis variable in the same call still converts
  expect_s3_class(v$GENHLTH, "factor")
})
