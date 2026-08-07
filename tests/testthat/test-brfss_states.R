# The states argument: resolution, pushdown, and coverage warnings,
# plus the brfss_states data object itself.

test_that("brfss_states covers every cataloged jurisdiction exactly once", {
  expect_identical(nrow(brfss_states), 56L)
  expect_false(anyDuplicated(brfss_states$fips) > 0)
  expect_false(anyDuplicated(brfss_states$abbr) > 0)
  expect_true(all(c(1L, 11L, 48L, 66L, 72L, 78L) %in% brfss_states$fips))
  # Census regions cover the states and DC; territories are NA.
  expect_false(anyNA(brfss_states$region[brfss_states$fips <= 56]))
  expect_true(all(is.na(brfss_states$region[brfss_states$fips > 56])))
  # R's pre-1984 "North Central" label must have been renamed.
  expect_false("North Central" %in% brfss_states$region)
  expect_true("Midwest" %in% brfss_states$region)
})

test_that("resolve_states accepts FIPS, abbreviations, and names, mixed", {
  expect_identical(resolve_states(c(48, 6)), c(6L, 48L))
  expect_identical(resolve_states(c("tx", "CA")), c(6L, 48L))
  expect_identical(resolve_states(c("Texas", "california")), c(6L, 48L))
  expect_identical(resolve_states(c(48, 48L)), 48L)
  # The documented mixed form: R coerces this to character before
  # resolve_states() ever runs, so "48" must resolve as a FIPS code.
  expect_identical(resolve_states(c(48, "CA", "maine")), c(6L, 23L, 48L))
  expect_identical(resolve_states("48"), 48L)
  expect_null(resolve_states(NULL))
})

test_that("resolve_states rejects malformed and unknown input", {
  expect_error(resolve_states(list(48)), class = "brfssdata_bad_states_arg")
  expect_error(resolve_states(character(0)), class = "brfssdata_bad_states_arg")
  expect_error(resolve_states(c(48, NA)), class = "brfssdata_bad_states_arg")
  expect_error(resolve_states(6.5), class = "brfssdata_bad_states_arg")
  err <- expect_error(resolve_states("ZZ"), class = "brfssdata_bad_state")
  expect_match(conditionMessage(err), "ZZ")
  expect_error(resolve_states(99), class = "brfssdata_bad_state")
})

test_that("states filters rows in the query and returns _STATE", {
  local_brfss_cache(2023, states = list("2023" = 1:3))
  dat <- read_brfss(2023, vars = "GENHLTH", states = "AL", quiet = TRUE)
  expect_true(all(dat$`_STATE` == 1))
  expect_true(all(c("GENHLTH", "_STATE", "year") %in% names(dat)))
  full <- read_brfss(2023, quiet = TRUE)
  expect_identical(nrow(dat), sum(full$`_STATE` == 1))
})

test_that("a state absent from a year warns instead of shrinking silently", {
  local_brfss_cache(
    c(2022, 2023),
    states = list("2022" = 1:2, "2023" = 1:4)
  )
  expect_warning(
    read_brfss(2022:2023, vars = "GENHLTH", states = c(1, 4), quiet = TRUE),
    class = "brfssdata_state_coverage_warning"
  )
  expect_no_warning(
    read_brfss(2022:2023, vars = "GENHLTH", states = 1, quiet = TRUE),
    class = "brfssdata_state_coverage_warning"
  )
})

test_that("a state design equals the post-hoc filtered design", {
  skip_if_not_installed("survey")
  local_brfss_cache(2023, states = list("2023" = 1:3))
  pre <- brfss_design(2023, vars = "GENHLTH", states = 1, quiet = TRUE)
  full <- brfss_design(2023, vars = c("GENHLTH", "_STATE"), quiet = TRUE)
  post <- srvyr::filter(full, `_STATE` == 1)
  got <- srvyr::summarize(
    pre,
    m = srvyr::survey_mean(GENHLTH == 1, na.rm = TRUE)
  )
  ref <- srvyr::summarize(
    post,
    m = srvyr::survey_mean(GENHLTH == 1, na.rm = TRUE)
  )
  expect_equal(got$m, ref$m)
  expect_equal(got$m_se, ref$m_se)
})

test_that("the pooled state-participation warning respects the filter", {
  local_brfss_cache(
    c(2022, 2023),
    states = list("2022" = 1:2, "2023" = 1:4)
  )
  # States 3 and 4 differ across years, but the filter excludes them:
  # no participation warning for a comparison that cannot matter.
  expect_no_warning(
    brfss_design(2022:2023, vars = "GENHLTH", states = 1:2, quiet = TRUE),
    class = "brfssdata_pooled_states_warning"
  )
})
