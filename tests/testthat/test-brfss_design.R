test_that("post-2011 designs use the raking weight", {
  local_brfss_cache(2023)
  des <- brfss_design(2023, quiet = TRUE)
  expect_s3_class(des, "tbl_svy")
  dat <- des$variables
  expect_identical(dat$brfss_wt, dat$`_LLCPWT`)
})

test_that("the 2011 boundary year itself uses the raking weight", {
  # Mutation-verified gap: an off-by-one in the era split (< vs <=)
  # passed the whole suite because no test built a design for 2011, the
  # first LLCP year and the boundary the package is documented around.
  local_brfss_cache(2011)
  des <- brfss_design(2011, vars = "GENHLTH", quiet = TRUE)
  expect_identical(des$variables$brfss_wt, des$variables$`_LLCPWT`)
})

test_that("pre-2011 designs use the post-stratification weight", {
  local_brfss_cache(2009)
  des <- brfss_design(2009, quiet = TRUE)
  dat <- des$variables
  expect_identical(dat$brfss_wt, dat$`_FINALWT`)
})

test_that("spanning the 2011 break errors unless explicitly allowed", {
  local_brfss_cache(c(2009, 2023))
  err <- expect_error(
    brfss_design(c(2009, 2023), quiet = TRUE, pool_weights = FALSE),
    class = "brfssdata_break_error"
  )
  # Non-contiguous input renders as a list; "2009-2023" would imply
  # fifteen years were requested when two were.
  expect_match(conditionMessage(err), "2009, 2023")
  expect_no_match(conditionMessage(err), "2009-2023")
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
  skip_if_not_installed("survey")
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

  got <- survey::svymean(~GENHLTH, des, na.rm = TRUE)
  ref <- survey::svymean(~GENHLTH, clustered, na.rm = TRUE)
  expect_equal(survey::SE(got), survey::SE(ref))
  expect_equal(coef(got), coef(ref))
  expect_equal(survey::degf(des), survey::degf(clustered))
})

test_that("shared PSUs keep the clustered variance estimator", {
  skip_if_not_installed("survey")
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

  got <- survey::svymean(~GENHLTH, des, na.rm = TRUE)
  expect_equal(
    survey::SE(got),
    survey::SE(survey::svymean(~GENHLTH, clustered, na.rm = TRUE))
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

test_that("pool_weights divides by the year count, not by two", {
  local_brfss_cache(c(2021, 2022, 2023))
  pooled <- brfss_design(2021:2023, quiet = TRUE)
  unpooled <- brfss_design(2021:2023, pool_weights = FALSE, quiet = TRUE)
  expect_equal(pooled$variables$brfss_wt, unpooled$variables$brfss_wt / 3)
})

test_that("a user-supplied weight overrides the era default", {
  local_brfss_cache(2023, alt_weights = 2023)
  des <- suppressMessages(
    brfss_design(2023, vars = "GENHLTH", weight = "_CLLCPWT", quiet = TRUE),
    classes = "brfssdata_weight_subset_note"
  )
  dat <- des$variables
  expect_identical(dat$brfss_wt, dat$`_CLLCPWT`)
  # the era weight is not even loaded when a weight override is given
  expect_false("_LLCPWT" %in% names(dat))
})

test_that("a domain weight subsets to its covered rows with a note", {
  # The fixture _CLLCPWT is NA outside its first ten rows, the shape of
  # the real child weight (NULL on 383,782 of 433,323 rows in 2023).
  # Before the subsetting behavior, the documented
  # brfss_design(weight = "_CLLCPWT") call always aborted on real data
  # with brfssdata_bad_design_var; the fixture's complete _CLLCPWT
  # masked that for five tests.
  local_brfss_cache(2023, alt_weights = 2023)
  expect_message(
    des <- brfss_design(2023, vars = "GENHLTH", weight = "_CLLCPWT"),
    class = "brfssdata_weight_subset_note"
  )
  dat <- des$variables
  expect_identical(nrow(dat), 10L)
  expect_false(anyNA(dat$brfss_wt))
  expect_identical(dat$brfss_wt, dat$`_CLLCPWT`)
})

test_that("the domain-weight subset note survives quiet = TRUE", {
  # quiet governs progress output only; the subset note is analytical
  # (the design now estimates a different population). The way to
  # silence it is its class, which the second leg demonstrates.
  local_brfss_cache(2023, alt_weights = 2023)
  expect_message(
    brfss_design(2023, vars = "GENHLTH", weight = "_CLLCPWT", quiet = TRUE),
    class = "brfssdata_weight_subset_note"
  )
  expect_no_message(
    suppressMessages(
      brfss_design(2023, vars = "GENHLTH", weight = "_CLLCPWT", quiet = TRUE),
      classes = "brfssdata_weight_subset_note"
    ),
    class = "brfssdata_weight_subset_note"
  )
})

test_that("the automatic era weight still aborts on missing values", {
  # The subsetting treatment is for user-supplied domain weights only:
  # a missing era weight means a damaged file and must stay loud. The
  # "missing weights abort rather than silently degrade" test above
  # pins the same contract from the file side.
  local_brfss_cache(2023, alt_weights = 2023)
  local_mocked_bindings(
    read_brfss = function(...) {
      out <- tibble::tibble(
        year = rep(2023L, 4L),
        GENHLTH = c(1, 2, 1, 2),
        `_LLCPWT` = c(100, NA, 250, 300),
        `_STSTR` = c(1, 1, 2, 2),
        `_PSU` = c(1, 2, 3, 4)
      )
      names(out) <- c("year", "GENHLTH", "_LLCPWT", "_STSTR", "_PSU")
      out
    }
  )
  expect_error(
    brfss_design(2023, vars = "GENHLTH", quiet = TRUE),
    class = "brfssdata_bad_design_var"
  )
})

test_that("a user-supplied weight matches case-insensitively", {
  local_brfss_cache(2023, alt_weights = 2023)
  des <- suppressMessages(
    brfss_design(2023, vars = "GENHLTH", weight = "_cllcpwt", quiet = TRUE),
    classes = "brfssdata_weight_subset_note"
  )
  expect_identical(des$variables$brfss_wt, des$variables$`_CLLCPWT`)
})

test_that("an intermediate pipeline weight is refused without the override", {
  # Contract change from the warn-not-block behavior: the review showed
  # weight = "_WT1" building a design over a non-analysis weight with
  # no more than a warning. Anything that is not a final analysis
  # weight now requires unsafe_weight = TRUE.
  local_brfss_cache(2023, alt_weights = 2023)
  err <- expect_error(
    brfss_design(2023, vars = "GENHLTH", weight = "_LLCPWT2", quiet = TRUE),
    class = "brfssdata_unrecognized_weight"
  )
  # parented on brfssdata_bad_weight, so one handler catches every
  # weight refusal
  expect_s3_class(err, "brfssdata_bad_weight")
  expect_match(conditionMessage(err), "unsafe_weight")
})

test_that("unsafe_weight = TRUE honors an intermediate weight and warns", {
  local_brfss_cache(2023, alt_weights = 2023)
  expect_warning(
    des <- brfss_design(
      2023,
      vars = "GENHLTH",
      weight = "_LLCPWT2",
      unsafe_weight = TRUE,
      quiet = TRUE
    ),
    class = "brfssdata_intermediate_weight_warning"
  )
  # the override is honored: warned, not blocked
  expect_identical(des$variables$brfss_wt, des$variables$`_LLCPWT2`)
})

test_that("a malformed unsafe_weight argument is rejected", {
  local_brfss_cache(2023)
  expect_error(
    brfss_design(2023, vars = "GENHLTH", unsafe_weight = NA),
    class = "brfssdata_bad_unsafe_weight_arg"
  )
  expect_error(
    brfss_design(2023, vars = "GENHLTH", unsafe_weight = "yes"),
    class = "brfssdata_bad_unsafe_weight_arg"
  )
})

test_that("an unsafe non-weight column warns and builds", {
  # The review's live example: weight = "GENHLTH" built a 2023 design
  # with no signal under quiet = TRUE and shifted the estimated female
  # share by 1.8 points. It now requires the override and warns.
  local_brfss_cache(2023)
  expect_warning(
    des <- brfss_design(
      2023,
      vars = "GENHLTH",
      weight = "GENHLTH",
      unsafe_weight = TRUE,
      quiet = TRUE,
      na = FALSE
    ),
    class = "brfssdata_unsafe_weight_warning"
  )
  expect_identical(des$variables$brfss_wt, des$variables$GENHLTH)
})

test_that("an explicit full-sample weight aborts on missing values", {
  # Completeness symmetry: the review showed explicit _LLCPWT silently
  # dropping rows where the automatic path aborted. Both now abort
  # identically, and no subset note fires on the way.
  local_brfss_cache(2023)
  local_mocked_bindings(
    read_brfss = function(...) {
      out <- tibble::tibble(
        year = rep(2023L, 4L),
        GENHLTH = c(1, 2, 1, 2),
        `_LLCPWT` = c(100, NA, 250, 300),
        `_STSTR` = c(1, 1, 2, 2),
        `_PSU` = c(1, 2, 3, 4)
      )
      names(out) <- c("year", "GENHLTH", "_LLCPWT", "_STSTR", "_PSU")
      out
    }
  )
  expect_no_message(
    expect_error(
      brfss_design(2023, vars = "GENHLTH", weight = "_LLCPWT", quiet = TRUE),
      class = "brfssdata_bad_design_var"
    ),
    class = "brfssdata_weight_subset_note"
  )
})

test_that("an explicit full-sample weight equals the automatic design", {
  local_brfss_cache(2023)
  auto <- brfss_design(2023, vars = "GENHLTH", quiet = TRUE)
  explicit <- brfss_design(
    2023,
    vars = "GENHLTH",
    weight = "_LLCPWT",
    quiet = TRUE
  )
  expect_identical(explicit$variables$brfss_wt, auto$variables$brfss_wt)
  expect_identical(nrow(explicit$variables), nrow(auto$variables))
})

test_that("a final weight outside its span fails before any download", {
  # 2023 sits outside _FINALWT's 1985-2010 span. Nothing is cached and
  # guard_network() is active inside the fixture, so reaching the read
  # path would fail loudly; the classed error proves the gate runs
  # pre-load.
  local_brfss_manifest(2023)
  err <- expect_error(
    brfss_design(2023, vars = "GENHLTH", weight = "_FINALWT"),
    class = "brfssdata_bad_weight"
  )
  expect_match(conditionMessage(err), "1985 to 2010")
})

test_that("weight values must be positive and finite", {
  local_brfss_cache(
    2023,
    add_cols = list("2023" = list(BADWT = c(-1, 2)))
  )
  expect_error(
    suppressWarnings(brfss_design(
      2023,
      vars = "GENHLTH",
      weight = "BADWT",
      unsafe_weight = TRUE,
      quiet = TRUE,
      na = FALSE
    )),
    class = "brfssdata_bad_weight"
  )
})

test_that("a zero in a final weight is a damaged file, not a subset", {
  local_brfss_cache(2023, alt_weights = 2023)
  local_mocked_bindings(
    read_brfss = function(...) {
      out <- tibble::tibble(
        year = rep(2023L, 4L),
        GENHLTH = c(1, 2, 1, 2),
        `_CLLCPWT` = c(100, 0, 250, NA),
        `_STSTR` = c(1, 1, 2, 2),
        `_PSU` = c(1, 2, 3, 4)
      )
      names(out) <- c("year", "GENHLTH", "_CLLCPWT", "_STSTR", "_PSU")
      out
    }
  )
  # the NA row leaves via the domain subset; the zero survives it and
  # is invalid in a final analysis weight
  expect_error(
    suppressMessages(
      brfss_design(2023, vars = "GENHLTH", weight = "_CLLCPWT", quiet = TRUE),
      classes = "brfssdata_weight_subset_note"
    ),
    class = "brfssdata_bad_design_var"
  )
})

test_that("a weight absent from a requested year names that year", {
  local_brfss_cache(c(2022, 2023), alt_weights = 2023)
  err <- expect_error(
    brfss_design(
      2022:2023,
      vars = "GENHLTH",
      weight = "_CLLCPWT",
      quiet = TRUE
    ),
    class = "brfssdata_bad_weight"
  )
  expect_match(conditionMessage(err), "2022")
})

test_that("a pooled user-supplied weight is divided by the year count", {
  local_brfss_cache(c(2022, 2023), alt_weights = c(2022, 2023))
  pooled <- suppressMessages(
    brfss_design(
      2022:2023,
      vars = "GENHLTH",
      weight = "_CLLCPWT",
      quiet = TRUE
    ),
    classes = "brfssdata_weight_subset_note"
  )
  unpooled <- suppressMessages(
    brfss_design(
      2022:2023,
      vars = "GENHLTH",
      weight = "_CLLCPWT",
      pool_weights = FALSE,
      quiet = TRUE
    ),
    classes = "brfssdata_weight_subset_note"
  )
  expect_equal(pooled$variables$brfss_wt, unpooled$variables$brfss_wt / 2)
})

test_that("an unknown weight errors with the pointed class", {
  local_brfss_cache(2023)
  expect_error(
    brfss_design(2023, weight = "_NOPE", quiet = TRUE),
    class = "brfssdata_bad_weight"
  )
})

test_that("a malformed weight argument is rejected", {
  local_brfss_cache(2023)
  expect_error(
    brfss_design(2023, weight = c("_A", "_B"), quiet = TRUE),
    class = "brfssdata_bad_weight"
  )
})

test_that("pooling warns when state participation differs across years", {
  # Two uneven states, not one: cli pluralization over a plain length>1
  # vector crashes in this cli version, so the length-2 case is the
  # regression pin for the {.val} wrapping in the warning.
  local_brfss_cache(
    c(2022, 2023),
    states = list("2022" = 1:2, "2023" = 1:4)
  )
  expect_warning(
    brfss_design(2022:2023, vars = "GENHLTH", quiet = TRUE),
    class = "brfssdata_pooled_states_warning"
  )
})

test_that("no state warning when participation is identical", {
  local_brfss_cache(c(2022, 2023))
  expect_no_warning(brfss_design(2022:2023, vars = "GENHLTH", quiet = TRUE))
})

test_that("vars = NULL announces the full-width load", {
  local_brfss_cache(2023)
  expect_message(brfss_design(2023), class = "brfssdata_full_load_note")
  expect_no_message(
    brfss_design(2023, quiet = TRUE),
    class = "brfssdata_full_load_note"
  )
})

test_that("allow_break with pooled weights divides era weights by year count", {
  local_brfss_cache(c(2009, 2023))
  expect_warning(
    des <- brfss_design(c(2009, 2023), allow_break = TRUE, quiet = TRUE),
    "2011"
  )
  dat <- des$variables
  pre <- dat$year < 2011
  expect_equal(dat$brfss_wt[pre], dat$`_FINALWT`[pre] / 2)
  expect_equal(dat$brfss_wt[!pre], dat$`_LLCPWT`[!pre] / 2)
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

# A requested year can contribute no rows at all (Kentucky collected no
# 2023 data, so states = "KY" over 2022:2023 is a 2022-only design).
# Dividing that design's weights by the two years requested halved every
# total with no signal, while leaving means and proportions untouched
# because the constant cancels there.
test_that("a year that contributes nothing does not dilute pooled totals", {
  skip_if_not_installed("survey")
  local_brfss_cache(
    c(2022, 2023),
    states = list("2022" = 1, "2023" = 2)
  )
  pooled <- suppressWarnings(
    brfss_design(2022:2023, vars = "GENHLTH", states = 1, quiet = TRUE)
  )
  single <- brfss_design(2022, vars = "GENHLTH", states = 1, quiet = TRUE)
  expect_identical(pooled$variables$brfss_wt, single$variables$brfss_wt)

  got <- srvyr::summarize(
    pooled,
    total = srvyr::survey_total(),
    m = srvyr::survey_mean(GENHLTH, na.rm = TRUE)
  )
  ref <- srvyr::summarize(
    single,
    total = srvyr::survey_total(),
    m = srvyr::survey_mean(GENHLTH, na.rm = TRUE)
  )
  expect_equal(got$total, ref$total)
  expect_equal(got$m, ref$m)
})

test_that("an empty pooled year warns about the divisor it changed", {
  local_brfss_cache(
    c(2022, 2023),
    states = list("2022" = 1, "2023" = 2)
  )
  w <- expect_warning(
    suppressWarnings(
      brfss_design(2022:2023, vars = "GENHLTH", states = 1, quiet = TRUE),
      classes = c(
        "brfssdata_state_coverage_warning",
        "brfssdata_pooled_states_warning"
      )
    ),
    class = "brfssdata_empty_year_warning"
  )
  expect_match(conditionMessage(w), "2023")
  expect_match(conditionMessage(w), "1 contributing year")
  # and the years that do contribute still divide by their own count
  expect_no_warning(
    suppressWarnings(
      brfss_design(2022:2023, vars = "GENHLTH", quiet = TRUE),
      classes = "brfssdata_pooled_states_warning"
    ),
    class = "brfssdata_empty_year_warning"
  )
})

test_that("the participation diagnostic sees a year with no in-scope rows", {
  # Before the fix, filtering to the one state left a single year-set,
  # and the diagnostic returned early on "fewer than two years".
  local_brfss_cache(
    c(2022, 2023),
    states = list("2022" = 1, "2023" = 2)
  )
  w <- expect_warning(
    suppressWarnings(
      brfss_design(2022:2023, vars = "GENHLTH", states = 1, quiet = TRUE),
      classes = c(
        "brfssdata_state_coverage_warning",
        "brfssdata_empty_year_warning"
      )
    ),
    class = "brfssdata_pooled_states_warning"
  )
  # and the jurisdiction is named the way its sibling warning names it
  expect_match(conditionMessage(w), "AL \\(FIPS 1\\)")
})

test_that("boolean arguments are validated before anything is read", {
  # A manifest-only cache with the network guarded: reaching the read
  # path at all fails loudly, so a classed argument error proves the
  # check runs at entry.
  local_brfss_manifest(2023)
  expect_error(
    brfss_design(2023, allow_break = "yes"),
    class = "brfssdata_bad_allow_break_arg"
  )
  expect_error(
    brfss_design(2023, pool_weights = "x"),
    class = "brfssdata_bad_pool_weights_arg"
  )
  err <- expect_error(
    brfss_design(2023, pool_weights = NA),
    class = "brfssdata_bad_pool_weights_arg"
  )
  # every one of them also carries the shared parent class
  expect_s3_class(err, "brfssdata_bad_bool_arg")
  expect_error(
    brfss_design(2023, download = "yes"),
    class = "brfssdata_bad_download_arg"
  )
  expect_error(
    brfss_design(2023, quiet = NA),
    class = "brfssdata_bad_quiet_arg"
  )
})

test_that("a design with no single-PSU stratum leaves the option alone", {
  # survey reads survey.lonely.psu at estimation time, so the write
  # outlives the call; a later unrelated survey analysis must keep
  # survey's fail-fast default when this design never needed the
  # adjustment. The fixture's three strata hold ten respondents each.
  local_brfss_cache(2023)
  expect_no_message(
    brfss_design(2023, vars = "GENHLTH", quiet = TRUE),
    class = "brfssdata_lonely_psu_note"
  )
  expect_null(getOption("survey.lonely.psu"))
})

test_that("a pinned brfssdata.lonely_psu is copied even without one", {
  # The package option is the documented way to choose the handling for
  # the session, so it is honored whatever the design contains.
  local_brfss_cache(2023)
  withr::local_options(brfssdata.lonely_psu = "certainty")
  brfss_design(2023, vars = "GENHLTH", quiet = TRUE)
  expect_identical(getOption("survey.lonely.psu"), "certainty")
})

test_that("the build states the svyset-equivalent specification", {
  local_brfss_cache(2023)
  msg <- expect_message(
    brfss_design(2023, vars = "GENHLTH", na = FALSE),
    class = "brfssdata_design_spec_note"
  )
  expect_match(conditionMessage(msg), "_LLCPWT")
  expect_match(conditionMessage(msg), "_STSTR")
  expect_match(conditionMessage(msg), "cluster term is omitted")
  expect_no_message(
    brfss_design(2023, vars = "GENHLTH", na = FALSE, quiet = TRUE),
    class = "brfssdata_design_spec_note"
  )
})

test_that("the specification note names the PSU when clustering is real", {
  local_brfss_cache(2023, psu_size = 3)
  msg <- expect_message(
    brfss_design(2023, vars = "GENHLTH", na = FALSE),
    class = "brfssdata_design_spec_note"
  )
  expect_match(conditionMessage(msg), "svyset _PSU")
  expect_no_match(conditionMessage(msg), "cluster term is omitted")
})

test_that("a mistyped lonely-PSU option fails before the download", {
  local_brfss_manifest(2023)
  withr::local_options(brfssdata.lonely_psu = 123)
  expect_error(
    brfss_design(2023, vars = "GENHLTH", quiet = TRUE),
    class = "brfssdata_bad_option"
  )
})

test_that("a missing design column is a damaged file, not a bad var", {
  dir <- local_brfss_cache(integer(0))
  df <- data.frame(
    year = 2023L,
    psu = 1:4,
    wt = c(100, 200, 250, 300),
    GENHLTH = c(1, 2, 1, 2),
    check.names = FALSE
  )
  names(df) <- c("year", "_PSU", "_LLCPWT", "GENHLTH")
  write_fixture_parquet(df, file.path(dir, "brfss_2023.parquet"))
  writeLines('{"years": [2023]}', file.path(dir, "manifest.json"))
  err <- expect_error(
    brfss_design(2023, vars = "GENHLTH", quiet = TRUE),
    class = "brfssdata_bad_design_var"
  )
  expect_match(conditionMessage(err), "_STSTR")
  expect_match(conditionMessage(err), "brfss_cache_clear")
})

test_that("a variable the user asked for keeps the variable-search error", {
  local_brfss_cache(2023)
  expect_error(
    brfss_design(2023, vars = "NOPEVAR", quiet = TRUE),
    class = "brfssdata_bad_var"
  )
})

test_that("the subset note claims CDC guidance only for a CDC weight", {
  local_brfss_cache(
    2023,
    alt_weights = 2023,
    add_cols = list("2023" = list(ODDWT = c(5, NA)))
  )
  unsafe <- expect_message(
    suppressWarnings(
      brfss_design(
        2023,
        vars = "GENHLTH",
        weight = "ODDWT",
        unsafe_weight = TRUE,
        na = FALSE,
        quiet = TRUE
      )
    ),
    class = "brfssdata_weight_subset_note"
  )
  expect_no_match(conditionMessage(unsafe), "CDC")
  module <- expect_message(
    brfss_design(
      2023,
      vars = "GENHLTH",
      weight = "_CLLCPWT",
      na = FALSE,
      quiet = TRUE
    ),
    class = "brfssdata_weight_subset_note"
  )
  expect_match(conditionMessage(module), "CDC's module-analysis guidance")
})

test_that("a non-numeric weight column says so", {
  # SEQNO is VARCHAR in the hosted files, and the positivity test alone
  # reported every row as "zero, negative, or not finite", which is the
  # wrong reason for a correct refusal.
  local_brfss_cache(
    2023,
    add_cols = list("2023" = list(TXTWT = c(1, 2))),
    chr_cols = list("2023" = "TXTWT")
  )
  err <- expect_error(
    suppressWarnings(
      brfss_design(
        2023,
        vars = "GENHLTH",
        weight = "TXTWT",
        unsafe_weight = TRUE,
        na = FALSE,
        quiet = TRUE
      )
    ),
    class = "brfssdata_bad_weight"
  )
  expect_match(conditionMessage(err), "not a numeric column")
  expect_no_match(conditionMessage(err), "zero, negative")
})
