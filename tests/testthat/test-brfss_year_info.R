# The year inventory: hosted columns plus the locally computed cached
# flag.

test_that("brfss_year_info returns the inventory with a cached flag", {
  dir <- local_brfss_cache(2023)
  # The inventory lists both years, but only 2023's parquet is cached.
  write_fixture_year_info(dir, years = c(2022, 2023))
  info <- brfss_year_info(download = FALSE)
  expect_s3_class(info, "tbl_df")
  expect_true(all(
    c(
      "year",
      "respondents",
      "variables",
      "states",
      "size",
      "codebook_url",
      "source_file",
      "source_format",
      "source_sha256",
      "downloaded",
      "cached"
    ) %in%
      names(info)
  ))
  # The source-identity columns arrive typed, not as bare text dates.
  expect_s3_class(info$downloaded, "Date")
  expect_match(info$source_sha256, "^[0-9a-f]{64}$")
  # 2023's parquet is in the fixture cache; 2022's is not.
  expect_true(info$cached[info$year == 2023])
  expect_false(info$cached[info$year == 2022])
})

test_that("years filters and unknown years say so", {
  local_brfss_cache(2023)
  info <- brfss_year_info(2023, download = FALSE)
  expect_identical(info$year, 2023L)
  expect_message(
    out <- brfss_year_info(c(2023, 1888), download = FALSE),
    class = "brfssdata_empty_result"
  )
  expect_identical(out$year, 2023L)
})

test_that("malformed years are rejected", {
  expect_error(
    brfss_year_info("recent"),
    class = "brfssdata_bad_years_arg"
  )
  # Inf used to pass, warn on coercion, and empty-result on year NA
  expect_error(
    brfss_year_info(Inf),
    class = "brfssdata_bad_years_arg"
  )
  expect_error(
    brfss_year_info(numeric(0)),
    class = "brfssdata_bad_years_arg"
  )
})
