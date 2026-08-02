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

test_that("single-PSU strata estimate without error (lonely-PSU handling)", {
  dir <- local_brfss_cache(integer(0))
  df <- data.frame(
    year = 2023L,
    psu = 1:5,
    ststr = c(1L, 1L, 2L, 2L, 3L), # stratum 3 has a single PSU
    wt = c(120, 250, 310, 150, 200),
    GENHLTH = c(1L, 2L, 1L, 2L, 1L),
    check.names = FALSE
  )
  names(df) <- c("year", "_PSU", "_STSTR", "_LLCPWT", "GENHLTH")
  write_fixture_parquet(df, file.path(dir, "brfss_2023.parquet"))
  writeLines('{"years": [2023]}', file.path(dir, "manifest.json"))

  withr::local_options(survey.lonely.psu = NULL)
  des <- brfss_design(2023, quiet = TRUE)
  est <- srvyr::summarize(
    des,
    m = srvyr::survey_mean(GENHLTH == 1, na.rm = TRUE)
  )
  expect_true(is.finite(est$m_se))
  expect_identical(getOption("survey.lonely.psu"), "adjust")
})

test_that("a user-chosen lonely-PSU option is respected", {
  local_brfss_cache(2023)
  withr::local_options(survey.lonely.psu = "certainty")
  des <- brfss_design(2023, quiet = TRUE)
  expect_identical(getOption("survey.lonely.psu"), "certainty")
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

# The 2001 and later files number every respondent as their own PSU, so
# the clustering is nominal and the design drops it: same estimates, far
# less work for survey. Files through 2000 share PSUs between respondents
# and must keep the clustered estimator, which gives a different standard
# error and different degrees of freedom.
test_that("singleton PSUs give the same answer as the clustered design", {
  local_brfss_cache(2023)
  des <- brfss_design(2023, quiet = TRUE)
  dat <- des$variables

  clustered <- srvyr::as_survey_design(
    dat,
    ids = brfss_psu,
    strata = brfss_strata,
    weights = brfss_wt,
    nest = TRUE
  )

  got <- survey::svymean(~GENHLTH, des)
  ref <- survey::svymean(~GENHLTH, clustered)
  expect_equal(survey::SE(got), survey::SE(ref))
  expect_equal(coef(got), coef(ref))
  expect_equal(survey::degf(des), survey::degf(clustered))
})

test_that("shared PSUs keep the clustered variance estimator", {
  local_brfss_cache(2023, psu_size = 3)
  des <- brfss_design(2023, quiet = TRUE)
  dat <- des$variables
  expect_gt(sum(duplicated(dat[c("brfss_strata", "brfss_psu")])), 0)

  clustered <- srvyr::as_survey_design(
    dat,
    ids = brfss_psu,
    strata = brfss_strata,
    weights = brfss_wt,
    nest = TRUE
  )
  unclustered <- srvyr::as_survey_design(
    dat,
    strata = brfss_strata,
    weights = brfss_wt
  )

  got <- survey::svymean(~GENHLTH, des)
  expect_equal(
    survey::SE(got),
    survey::SE(survey::svymean(~GENHLTH, clustered))
  )
  expect_equal(survey::degf(des), survey::degf(clustered))
  # and the two estimators really do disagree here, so the branch matters
  expect_false(isTRUE(all.equal(
    survey::degf(clustered),
    survey::degf(unclustered)
  )))
})

test_that("the clustering branch follows the file", {
  local_brfss_cache(2023)
  singleton <- brfss_design(2023, quiet = TRUE)
  # survey stores an unclustered design's ids as row numbers and a
  # clustered one's as the stratum-by-PSU interaction, so whether the
  # cluster column is a factor says which branch ran. Test that rather
  # than typeof(), which reports "integer" for a factor too.
  expect_false(is.factor(singleton$cluster[[1]]))
  expect_identical(singleton$cluster[[1]], seq_len(nrow(singleton$variables)))

  local_brfss_cache(2023, psu_size = 3)
  clustered <- brfss_design(2023, quiet = TRUE)
  expect_s3_class(clustered$cluster[[1]], "factor")
})

test_that("a missing stratum stops the design instead of pooling into one", {
  dir <- local_brfss_cache(integer(0))
  write_fixture_year_na_strata(2023, dir)
  writeLines('{"years": [2023]}', file.path(dir, "manifest.json"))
  expect_error(
    brfss_design(2023, quiet = TRUE),
    class = "brfssdata_bad_design_var"
  )
})

test_that("the 2011 break is the redesign year, not an arbitrary cutoff", {
  expect_identical(BREAK_YEAR, 2011L)
})

test_that("pool_weights divides by the year count, not by two", {
  local_brfss_cache(c(2021, 2022, 2023))
  pooled <- brfss_design(2021:2023, quiet = TRUE)
  unpooled <- brfss_design(2021:2023, pool_weights = FALSE, quiet = TRUE)
  expect_equal(pooled$variables$brfss_wt, unpooled$variables$brfss_wt / 3)
})

test_that("an unclustered design skips survey's nested-clusters check", {
  # survey cross-tabulates clusters by strata unless check_strata is
  # off. Every observation is its own cluster on this path, so the check
  # can only pass, and on pooled years the table it builds exceeds R's
  # vector limit and the call dies. A fixture is far too small to
  # reproduce that, so assert the argument reaches srvyr instead.
  local_brfss_cache(2023)
  seen <- NULL
  real <- srvyr::as_survey_design
  local_mocked_bindings(
    as_survey_design = function(...) {
      seen <<- ...names()
      real(...)
    },
    .package = "srvyr"
  )
  brfss_design(2023, quiet = TRUE)
  expect_true("check_strata" %in% seen)
})
