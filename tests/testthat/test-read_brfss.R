test_that("read_brfss returns cached years as a tibble with a year column", {
  local_brfss_cache(c(2022, 2023))
  dat <- read_brfss(2022:2023, quiet = TRUE)
  expect_s3_class(dat, "tbl_df")
  expect_identical(sort(unique(dat$year)), c(2022L, 2023L))
  expect_true(all(c("_PSU", "_STSTR", "_LLCPWT", "GENHLTH") %in% names(dat)))
})

test_that("vars selection always carries the year column", {
  local_brfss_cache(2023)
  dat <- read_brfss(2023, vars = "GENHLTH", quiet = TRUE)
  expect_identical(sort(names(dat)), c("GENHLTH", "year"))
})

test_that("variables absent from a year come back as NA", {
  local_brfss_cache(c(2022, 2023), extra = list("2023" = "NEWVAR23"))
  dat <- read_brfss(2022:2023, vars = "NEWVAR23", quiet = TRUE)
  expect_true(all(is.na(dat$NEWVAR23[dat$year == 2022])))
  expect_false(anyNA(dat$NEWVAR23[dat$year == 2023]))
})

test_that("unknown variables produce an informative classed error", {
  local_brfss_cache(2023)
  expect_error(
    read_brfss(2023, vars = c("GENHLTH", "NOPE"), quiet = TRUE),
    class = "brfssdata_bad_var"
  )
})

test_that("malformed vars argument is rejected by the argument check", {
  local_brfss_cache(2023)
  expect_error(
    read_brfss(2023, vars = 1:3, quiet = TRUE),
    class = "brfssdata_bad_vars_arg"
  )
  expect_error(
    read_brfss(2023, vars = c("GENHLTH", NA), quiet = TRUE),
    class = "brfssdata_bad_vars_arg"
  )
})

test_that("download = FALSE refuses to fetch missing years", {
  local_brfss_manifest(c(2022, 2023))
  expect_error(
    read_brfss(2023, download = FALSE, quiet = TRUE),
    class = "brfssdata_not_cached"
  )
})

test_that("no download is attempted when all years are cached", {
  local_brfss_cache(2023)
  local_mocked_bindings(
    download_to_cache = function(...) stop("network touched")
  )
  expect_silent(dat <- read_brfss(2023, quiet = TRUE))
  expect_gt(nrow(dat), 0)
})
