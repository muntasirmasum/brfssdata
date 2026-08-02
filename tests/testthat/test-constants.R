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
