test_that("post-2011 designs use the raking weight", {
  local_brfss_cache(2023)
  des <- brfss_design(2023, quiet = TRUE)
  expect_s3_class(des, "tbl_svy")
  dat <- des$variables
  expect_identical(dat$brfss_wt, dat$`_LLCPWT`)
})

test_that("pre-2011 designs use the post-stratification weight", {
  local_brfss_cache(2009)
  des <- brfss_design(2009, quiet = TRUE)
  dat <- des$variables
  expect_identical(dat$brfss_wt, dat$`_FINALWT`)
})

test_that("spanning the 2011 break errors unless explicitly allowed", {
  local_brfss_cache(c(2009, 2023))
  expect_error(
    brfss_design(c(2009, 2023), quiet = TRUE, pool_weights = FALSE),
    class = "brfssdata_break_error"
  )
})

test_that("allow_break pools with a warning and era-correct weights", {
  local_brfss_cache(c(2009, 2023))
  expect_warning(
    des <- brfss_design(
      c(2009, 2023),
      allow_break = TRUE,
      pool_weights = FALSE,
      quiet = TRUE
    ),
    "2011"
  )
  dat <- des$variables
  pre <- dat$year < 2011
  expect_identical(dat$brfss_wt[pre], dat$`_FINALWT`[pre])
  expect_identical(dat$brfss_wt[!pre], dat$`_LLCPWT`[!pre])
})

test_that("pool_weights divides weights by the number of years", {
  local_brfss_cache(c(2022, 2023))
  pooled <- brfss_design(2022:2023, quiet = TRUE)
  unpooled <- brfss_design(2022:2023, pool_weights = FALSE, quiet = TRUE)
  expect_equal(
    pooled$variables$brfss_wt,
    unpooled$variables$brfss_wt / 2
  )
})

test_that("pooled designs stratify on the year-by-stratum interaction", {
  local_brfss_cache(c(2022, 2023))
  pooled <- brfss_design(2022:2023, quiet = TRUE)
  dat <- pooled$variables
  expect_identical(
    dat$brfss_strata,
    paste(dat$year, dat$`_STSTR`, sep = "_")
  )

  single <- brfss_design(2023, quiet = TRUE)
  expect_identical(single$variables$brfss_strata, single$variables$`_STSTR`)
})

test_that("missing design variables abort with a classed error", {
  local_brfss_cache(2023)
  local_mocked_bindings(
    read_brfss = function(...) {
      tibble::tibble(year = 2023L, GENHLTH = 1L)
    }
  )
  expect_error(
    brfss_design(2023, quiet = TRUE),
    class = "brfssdata_bad_design_var"
  )
})

test_that("missing weights abort rather than silently degrade", {
  dir <- local_brfss_cache(integer(0))
  df <- data.frame(
    year = 2023L,
    psu = 1:4,
    ststr = c(1L, 1L, 2L, 2L),
    wt = c(100, NA, 250, 300),
    check.names = FALSE
  )
  names(df) <- c("year", "_PSU", "_STSTR", "_LLCPWT")
  write_fixture_parquet(df, file.path(dir, "brfss_2023.parquet"))
  writeLines('{"years": [2023]}', file.path(dir, "manifest.json"))
  expect_error(
    brfss_design(2023, quiet = TRUE),
    class = "brfssdata_bad_design_var"
  )
})

test_that("analysis vars ride along with design vars", {
  local_brfss_cache(2023)
  des <- brfss_design(2023, vars = "GENHLTH", quiet = TRUE)
  expect_true(all(
    c("GENHLTH", "_LLCPWT", "_STSTR", "_PSU", "brfss_wt", "year") %in%
      names(des$variables)
  ))
})
