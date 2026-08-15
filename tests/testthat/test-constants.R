# Independent anchor for the design constants. The fixture helpers derive
# their column names from BREAK_YEAR/WEIGHT_PRE/WEIGHT_POST, so every
# fixture-based test would agree with a swapped or mistyped constant.
# This table is transcribed by hand from CDC's annual codebooks instead
# and must never be rewritten in terms of the package constants.
#
# Sources: the BRFSS codebooks at https://www.cdc.gov/brfss/annual_data/
# list _FINALWT as the final weight through 2010 (post-stratification
# era) and _LLCPWT from 2011 on (the first landline-and-cell raking
# year); _PSU and _STSTR appear in every year's variable layout.

test_that("era weights match the CDC codebooks, not the fixtures", {
  codebook <- data.frame(
    year = c(1993L, 2000L, 2010L, 2011L, 2015L, 2023L),
    weight = c(
      "_FINALWT",
      "_FINALWT",
      "_FINALWT",
      "_LLCPWT",
      "_LLCPWT",
      "_LLCPWT"
    ),
    stringsAsFactors = FALSE
  )
  got <- ifelse(codebook$year >= BREAK_YEAR, WEIGHT_POST, WEIGHT_PRE)
  expect_identical(got, codebook$weight)
})

test_that("design variable names match the CDC codebooks", {
  expect_identical(DESIGN_PSU, "_PSU")
  expect_identical(DESIGN_STRATA, "_STSTR")
})

# The final-weight allowlist, transcribed by hand from CDC's annual
# codebooks and variable layouts, never from the package constants:
# _FINALWT is the final weight 1985-2010 and _LLCPWT from 2011 on (as
# above); the 2006-2010 codebooks list _CHILDWT ("final child weight")
# and _HOUSEWT ("final household weight"); _CLLCPWT is the combined
# landline-and-cell child weight from 2011 on; the 2007 codebook lists
# the questionnaire-version final weights _FINALQ1/_FINALQ2 and the
# child versions _CHILDQ1/_CHILDQ2. Only _FINALWT and _LLCPWT cover the
# full sample; the rest are domain weights.

test_that("the final-weight allowlist matches the CDC codebooks", {
  codebook <- data.frame(
    weight = c(
      "_FINALWT",
      "_LLCPWT",
      "_CLLCPWT",
      "_CHILDWT",
      "_HOUSEWT",
      "_FINALQ1",
      "_FINALQ2",
      "_CHILDQ1",
      "_CHILDQ2"
    ),
    first_year = c(
      1985L,
      2011L,
      2011L,
      2006L,
      2006L,
      2007L,
      2007L,
      2007L,
      2007L
    ),
    last_year = c(2010L, NA, NA, 2010L, 2010L, 2007L, 2007L, 2007L, 2007L),
    full_sample = c(
      TRUE,
      TRUE,
      FALSE,
      FALSE,
      FALSE,
      FALSE,
      FALSE,
      FALSE,
      FALSE
    ),
    stringsAsFactors = FALSE
  )
  idx <- match(codebook$weight, FINAL_WEIGHTS$weight)
  expect_false(anyNA(idx))
  expect_identical(nrow(FINAL_WEIGHTS), nrow(codebook))
  expect_identical(FINAL_WEIGHTS$first_year[idx], codebook$first_year)
  expect_identical(FINAL_WEIGHTS$last_year[idx], codebook$last_year)
  expect_identical(FINAL_WEIGHTS$full_sample[idx], codebook$full_sample)
})

test_that("the weight tables are disjoint and exclude body measures", {
  expect_length(intersect(FINAL_WEIGHTS$weight, INTERMEDIATE_WEIGHTS), 0)
  # respondent body-weight questions and the weight-for-height percent,
  # one plausible guess away from `weight =`
  body_measures <- c(
    "WEIGHT",
    "WEIGHT2",
    "WTKG",
    "WTKG2",
    "WTKG3",
    "LOSEWT",
    "WTDESIRE",
    "_WTFORHT"
  )
  expect_length(intersect(body_measures, FINAL_WEIGHTS$weight), 0)
  expect_length(intersect(body_measures, INTERMEDIATE_WEIGHTS), 0)
})

test_that("every weight is excluded from labeling and recoding", {
  expect_true(all(FINAL_WEIGHTS$weight %in% LABEL_EXCLUDE))
  expect_true(all(INTERMEDIATE_WEIGHTS %in% LABEL_EXCLUDE))
})

# The duckdb floor is stated twice: DESCRIPTION's Imports pin, which
# only R CMD INSTALL enforces, and DUCKDB_MIN_VERSION, which
# duckdb_connect() enforces in the running session. A bump to one
# without the other would leave the runtime guard checking for a version
# nobody installs.
test_that("the duckdb version floor matches the DESCRIPTION pin", {
  imports <- read.dcf(
    system.file("DESCRIPTION", package = "brfssdata"),
    fields = "Imports"
  )[[1L]]
  pin <- regmatches(imports, regexpr("duckdb \\(>= [0-9.]+\\)", imports))
  expect_identical(pin, sprintf("duckdb (>= %s)", DUCKDB_MIN_VERSION))
})
