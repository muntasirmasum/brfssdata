# The bundled metadata snapshots: metadata functions work on first use
# with no cache and no network, and never serve the snapshot silently.

test_that("catalogs fall back to the bundled snapshot offline", {
  # An empty cache with downloads disabled: before the snapshots
  # shipped this was a brfssdata_not_cached error; now the frozen copy
  # answers, with a note.
  local_brfss_cache(integer(0), label_catalog = FALSE, crosswalk = FALSE)
  expect_message(
    out <- brfss_labels("GENHLTH", years = 2023, download = FALSE),
    class = "brfssdata_bundled_fallback_note"
  )
  expect_gt(nrow(out), 0)
  expect_message(
    xw <- brfss_crosswalk("_DRNKWK1", download = FALSE),
    class = "brfssdata_bundled_fallback_note"
  )
  expect_true(all(c("_DRNKWK1", "_DRNKWK2", "_DRNKWK3") %in% xw$variable))
})

test_that("a cached catalog wins over the bundled snapshot, silently", {
  local_brfss_cache(2023)
  expect_no_message(
    brfss_labels("GENHLTH", years = 2023, download = FALSE),
    class = "brfssdata_bundled_fallback_note"
  )
})

test_that("the year inventory has no bundled fallback", {
  # Its size column describes the hosted bytes, which change with every
  # data release; a frozen copy would lie. Offline first use stays a
  # classed error.
  local_brfss_cache(integer(0), year_info = FALSE)
  expect_error(
    brfss_year_info(download = FALSE),
    class = "brfssdata_not_cached"
  )
})

test_that("the bundled snapshots themselves are readable and coherent", {
  labels_path <- system.file(
    "extdata",
    "brfss_labels.parquet",
    package = "brfssdata"
  )
  xwalk_path <- system.file(
    "extdata",
    "brfss_crosswalk.parquet",
    package = "brfssdata"
  )
  skip_if(labels_path == "" || xwalk_path == "", "snapshots not installed")
  labels <- query_parquet(labels_path)
  expect_true(all(
    c("year", "variable", "code", "label", "complete") %in% names(labels)
  ))
  xwalk <- query_parquet(xwalk_path)
  expect_true(all(
    c("concept", "variable", "year", "generation", "status", "comparable", "note") %in%
      names(xwalk)
  ))
  # Every crosswalk variable exists in the variable catalog snapshot.
  vars_path <- system.file(
    "extdata",
    "brfss_variables.parquet",
    package = "brfssdata"
  )
  vars <- query_parquet(vars_path)
  expect_true(all(xwalk$variable %in% vars$variable))
})
