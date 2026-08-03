# CDC's SAS format libraries are not always a clean one-to-one map.
# factor(levels = , labels = ) resolves a repeated code silently by row
# order and merges a repeated label into one level, so both produce a
# plausible-looking, wrong variable. These guard the fallback to numeric
# codes, which is what the raw CDC file would have given anyway.

write_labels_catalog <- function(dir, rows) {
  write_fixture_parquet(rows, file.path(dir, "brfss_labels.parquet"))
  # Keep a v2 fixture manifest's hash entries in sync: a stale hash for
  # the labels file would trigger a refresh download straight into the
  # network guard. v1 manifests carry no hashes and need nothing.
  manifest <- file.path(dir, "manifest.json")
  if (file.exists(manifest)) {
    parsed <- jsonlite::read_json(manifest, simplifyVector = TRUE)
    if (!is.null(parsed$schema_version)) {
      write_fixture_manifest(dir, parsed$years)
    }
  }
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
      # Every label distinct, so only the repeated *code* can block the
      # conversion; a fixture with repeated labels too would pass even
      # if the duplicate-code check were removed.
      code = c(1L, 1L, 1L, 2L),
      label = c("NOT AT RISK", "NO", "YES", "AT RISK"),
      complete = TRUE,
      stringsAsFactors = FALSE
    )
  )

  dat <- read_brfss(2023, quiet = TRUE, labels = TRUE)
  expect_false(is.factor(dat$RISKVAR))
  expect_identical(sort(unique(dat$RISKVAR)), c(1L, 2L))
})

# The blank-label and missing-label cases are kept in separate fixtures
# on purpose: a single fixture carrying both would still be blocked if
# either check were removed, and so could not tell them apart.
test_that("a missing label keeps its numeric codes", {
  dir <- local_brfss_cache(integer(0))
  one_year_fixture(dir, "GAPVAR", c(1L, 2L, 3L))
  write_labels_catalog(
    dir,
    data.frame(
      year = 2023L,
      variable = "GAPVAR",
      code = 1:3,
      label = c("Yes", "No", NA_character_),
      complete = TRUE,
      stringsAsFactors = FALSE
    )
  )

  dat <- read_brfss(2023, quiet = TRUE, labels = TRUE)
  expect_false(is.factor(dat$GAPVAR))
})

test_that("a blank label keeps its numeric codes", {
  dir <- local_brfss_cache(integer(0))
  one_year_fixture(dir, "BLANKVAR", c(1L, 2L, 3L))
  # Shaped like _IMPNPH in 2003, where most codes carry an empty string.
  write_labels_catalog(
    dir,
    data.frame(
      year = 2023L,
      variable = "BLANKVAR",
      code = 1:3,
      label = c("Yes", "No", "  "),
      complete = TRUE,
      stringsAsFactors = FALSE
    )
  )

  dat <- read_brfss(2023, quiet = TRUE, labels = TRUE)
  expect_false(is.factor(dat$BLANKVAR))
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

test_that("factor labels come from the most recent requested year", {
  # CDC rewords labels between years while the code set stays put, so
  # the newest wording should win. A fixture whose wording is identical
  # across years cannot tell max() from min().
  dir <- local_brfss_cache(
    c(2022, 2023),
    extra = list("2022" = "DRIFTLAB", "2023" = "DRIFTLAB")
  )
  write_labels_catalog(
    dir,
    data.frame(
      year = c(2022L, 2022L, 2023L, 2023L),
      variable = "DRIFTLAB",
      code = c(0L, 1L, 0L, 1L),
      label = c("NO", "YES", "No", "Yes"),
      complete = TRUE,
      stringsAsFactors = FALSE
    )
  )

  dat <- read_brfss(2022:2023, quiet = TRUE, labels = TRUE)
  expect_s3_class(dat$DRIFTLAB, "factor")
  expect_identical(levels(dat$DRIFTLAB), c("No", "Yes"))
})

test_that("labels never convert the columns the design is built on", {
  dir <- local_brfss_cache(2023)
  # A format for the stratum variable itself. Turning `_STSTR` or its
  # syntactic copy into a factor would corrupt the survey design.
  write_labels_catalog(
    dir,
    data.frame(
      year = 2023L,
      variable = c(rep("GENHLTH", 7), "_STSTR", "_STSTR", "_STSTR"),
      code = c(1:5, 7L, 9L, 1L, 2L, 3L),
      label = c(
        "Excellent",
        "Very good",
        "Good",
        "Fair",
        "Poor",
        "Don't know/Not Sure",
        "Refused",
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

test_that("an incomplete format never converts, even when fully covered", {
  # PHYSHLTH's incompleteness is shadowed by its uncovered day counts
  # (the observed-coverage gate blocks it regardless), so this fixture
  # isolates the complete-format gate itself: every observed value is on
  # a labeled code, and only `complete = FALSE` stands in the way.
  dir <- local_brfss_cache(integer(0))
  one_year_fixture(dir, "RANGEVAR", c(88, 99))
  write_labels_catalog(
    dir,
    data.frame(
      year = 2023L,
      variable = "RANGEVAR",
      code = c(88L, 99L),
      label = c("None", "Refused"),
      complete = FALSE,
      stringsAsFactors = FALSE
    )
  )
  dat <- read_brfss(2023, quiet = TRUE, labels = TRUE)
  expect_false(is.factor(dat$RANGEVAR))
})

test_that("the read path never converts _STATE", {
  # _STATE carries a complete label map in every real year; a factor of
  # state names would make `_STATE == 6` silently match nothing.
  local_brfss_cache(2023)
  dat <- read_brfss(2023, quiet = TRUE, labels = TRUE)
  expect_false(is.factor(dat$`_STATE`))
  expect_true(is.numeric(dat$`_STATE`))
  expect_identical(sum(dat$`_STATE` == 1), nrow(dat))
})
