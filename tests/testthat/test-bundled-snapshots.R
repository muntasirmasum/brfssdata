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

# The rest of this file pins facts about the label catalog that a
# mis-parsed SAS format library gets wrong quietly: a wrong row looks
# exactly like a right one. Read from the bundled snapshot rather than
# through brfss_labels(), so a stale cache cannot mask a bad build.
bundled_labels <- function() {
  path <- system.file("extdata", "brfss_labels.parquet", package = "brfssdata")
  skip_if(path == "", "snapshot not installed")
  query_parquet(path)
}

test_that("comma-separated SAS code lists reach the catalog whole", {
  # CDC's 1998-2001 libraries write "77,99 = 'UNK/REF'" and
  # ".,7,9 = 'UNK/REF'". Reading only the last code before the "=" left
  # the whole 7 / 77 / 777 don't-know family out of those years, so
  # na = TRUE passed don't-know answers through as data.
  labels <- bundled_labels()
  key <- function(year, variable, code) {
    labels$label[
      labels$year == year &
        toupper(labels$variable) == variable &
        labels$code == code
    ]
  }
  expect_identical(key(2000, "PHYSHLTH", 77L), "UNK/REF")
  expect_identical(key(2001, "PHYSHLTH", 77L), "UNK/REF")
  expect_identical(key(1999, "ASTHMA", 7L), "UNK/REF")
  # 2001 INCOME2 is "1,2 = '< $15,000'" through "5,6 = '$25-$49,999'":
  # the odd-numbered codes existed only in CDC's file, never here.
  expect_identical(key(2001, "INCOME2", 1L), "< $15,000")
  expect_identical(key(2001, "INCOME2", 3L), "$15-$24,999")
  expect_identical(key(2001, "INCOME2", 5L), "$25-$49,999")
  expect_true(all(
    is_missing_label(unlist(lapply(1999:2001, key, "PHYSHLTH", 77L)))
  ))
})

test_that("a range endpoint never becomes a code", {
  # WEIGHT's "244-<777 = '244 +'" left the catalog claiming code 777
  # was a topcoded weight, next to ".,777,999 = 'UNK/REF'" saying it is
  # the don't-know sentinel. A range is not a code and emits no row.
  labels <- bundled_labels()
  wt <- labels[
    toupper(labels$variable) %in% c("WEIGHT", "WTDESIRE") &
      labels$year %in% 1998:2001,
    ,
    drop = FALSE
  ]
  expect_false(any(wt$label == "244 +"))
  expect_false(any(wt$code == 80L))
  expect_true(all(wt$label[wt$code == 777L] == "UNK/REF"))
  expect_true(all(is_missing_label(wt$label[wt$code == 777L])))
  # A format holding a range stays ineligible for factor conversion.
  expect_false(any(wt$complete))
})

test_that("the documented CDC label corrections are in the snapshot", {
  # 2002 hands the generic UNK2DIG format to 17 variables and writes
  # its code 88 as the smoking-module wording. The count items take
  # CDC's own per-variable wording; the two smoking items keep theirs.
  labels <- bundled_labels()
  code_88 <- function(variable) {
    labels$label[
      labels$year == 2002 &
        toupper(labels$variable) == variable &
        labels$code == 88L
    ]
  }
  expect_identical(code_88("PHYSHLTH"), "None")
  expect_identical(code_88("MENTHLTH"), "None")
  expect_identical(code_88("AVEDRNK"), "None")
  expect_identical(code_88("QLSTRES2"), "None")
  expect_identical(code_88("FIRSTSMK"), "Never smoked regularly")
  expect_identical(code_88("REGSMK"), "Never smoked regularly")

  # DISPCODE names call outcomes, so its category 2 is an answer, not a
  # refusal to answer; CDC's 2000 library writes it "02-REFUSED".
  disp <- labels[
    labels$year == 1999 & toupper(labels$variable) == "DISPCODE",
    ,
    drop = FALSE
  ]
  expect_identical(disp$label[disp$code == 2L], "02-REFUSED")
  expect_false(any(is_missing_label(disp$label)))

  # An imputed phone count cannot answer "don't know"; CDC's own
  # _IMPNPH format counts phones at 7.
  imp <- labels[
    labels$year == 2002 & toupper(labels$variable) == "_IMPNPH",
    ,
    drop = FALSE
  ]
  expect_identical(imp$label[imp$code == 7L], "7")
  expect_false(is_missing_label(imp$label[imp$code == 7L]))
})
