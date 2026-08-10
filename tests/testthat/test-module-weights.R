# The module-weight confinement detector: a requested variable with
# data almost only inside a domain weight's records, analyzed under a
# full-sample weight, is very likely a module analysis under the wrong
# weight. Fixtures use na = FALSE so the uncatalogued module column
# never trips the missing-code coverage signals, which are a different
# contract.

test_that("a module-shaped variable under the default weight warns", {
  local_brfss_cache(
    2023,
    alt_weights = 2023,
    module_cols = list("2023" = "KIDVAR")
  )
  w <- expect_warning(
    brfss_design(2023, vars = "KIDVAR", na = FALSE, quiet = TRUE),
    class = "brfssdata_module_weight_warning"
  )
  expect_match(conditionMessage(w), "_CLLCPWT")
  expect_match(conditionMessage(w), "KIDVAR")
})

test_that("choosing the matching domain weight silences the detector", {
  local_brfss_cache(
    2023,
    alt_weights = 2023,
    module_cols = list("2023" = "KIDVAR")
  )
  expect_no_warning(
    suppressMessages(
      brfss_design(
        2023,
        vars = "KIDVAR",
        weight = "_CLLCPWT",
        na = FALSE,
        quiet = TRUE
      ),
      classes = "brfssdata_weight_subset_note"
    ),
    class = "brfssdata_module_weight_warning"
  )
})

test_that("a core variable does not warn", {
  # GENHLTH has data on every row, so its confinement to the child
  # domain equals the domain's base rate (a third of the fixture file),
  # far under the threshold.
  local_brfss_cache(2023, alt_weights = 2023)
  expect_no_warning(
    brfss_design(2023, vars = "GENHLTH", na = FALSE, quiet = TRUE),
    class = "brfssdata_module_weight_warning"
  )
})

test_that("the detector is skipped when vars is not given", {
  # The full-width frame carries the candidate weight columns where the
  # user can see them, and the full-load note already pushes toward
  # vars=; scanning every column would be cost without calibration.
  local_brfss_cache(
    2023,
    alt_weights = 2023,
    module_cols = list("2023" = "KIDVAR")
  )
  expect_no_warning(
    brfss_design(2023, na = FALSE, quiet = TRUE),
    class = "brfssdata_module_weight_warning"
  )
})

test_that("the off switch works and a malformed option is rejected", {
  local_brfss_cache(
    2023,
    alt_weights = 2023,
    module_cols = list("2023" = "KIDVAR")
  )
  withr::local_options(brfssdata.module_weight_check = FALSE)
  expect_no_warning(
    brfss_design(2023, vars = "KIDVAR", na = FALSE, quiet = TRUE),
    class = "brfssdata_module_weight_warning"
  )
  withr::local_options(brfssdata.module_weight_check = "yes")
  expect_error(
    brfss_design(2023, vars = "KIDVAR", na = FALSE, quiet = TRUE),
    class = "brfssdata_bad_option"
  )
})

test_that("a failed confinement query degrades to silence", {
  local_brfss_cache(
    2023,
    alt_weights = 2023,
    module_cols = list("2023" = "KIDVAR")
  )
  local_mocked_bindings(try_parquet_aggregate = function(...) NULL)
  expect_no_warning(
    des <- brfss_design(2023, vars = "KIDVAR", na = FALSE, quiet = TRUE),
    class = "brfssdata_module_weight_warning"
  )
  expect_s3_class(des, "tbl_svy")
})

test_that("confinement must hold in every requested year", {
  # KIDVAR is module-shaped in 2023 but answered file-wide in 2022, so
  # one uneven year clears the flag.
  local_brfss_cache(
    c(2022, 2023),
    alt_weights = c(2022, 2023),
    module_cols = list("2023" = "KIDVAR"),
    add_cols = list("2022" = list(KIDVAR = c(1, 2)))
  )
  expect_no_warning(
    brfss_design(2022:2023, vars = "KIDVAR", na = FALSE, quiet = TRUE),
    class = "brfssdata_module_weight_warning"
  )
  # and module-shaped in both years warns
  local_brfss_cache(
    c(2022, 2023),
    alt_weights = c(2022, 2023),
    module_cols = list("2022" = "KIDVAR", "2023" = "KIDVAR")
  )
  expect_warning(
    brfss_design(2022:2023, vars = "KIDVAR", na = FALSE, quiet = TRUE),
    class = "brfssdata_module_weight_warning"
  )
})

test_that("a degenerate domain covering the whole file stays silent", {
  # With every fixture state inside child_states, _CLLCPWT covers 100%
  # of the file; a domain that separates nothing must not flag, even
  # though the module column is fully confined to it.
  local_brfss_cache(
    2023,
    alt_weights = 2023,
    states = list("2023" = 1:2),
    child_states = list("2023" = 1:2),
    module_cols = list("2023" = "KIDVAR")
  )
  expect_no_warning(
    brfss_design(2023, vars = "KIDVAR", na = FALSE, quiet = TRUE),
    class = "brfssdata_module_weight_warning"
  )
})
