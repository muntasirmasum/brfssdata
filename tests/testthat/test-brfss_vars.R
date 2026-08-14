test_that("brfss_vars searches names and labels case-insensitively", {
  local_brfss_cache(2020, catalog = TRUE)
  out <- brfss_vars("smok")
  expect_identical(out$variable, "SMOKE100")
  out2 <- brfss_vars("general health")
  expect_identical(out2$variable, "GENHLTH")
})

test_that("variables with missing labels are found, not dropped", {
  local_brfss_cache(2020, catalog = TRUE)
  out <- brfss_vars("MYSTVAR")
  expect_identical(out$variable, "MYSTVAR")
  expect_true(is.na(out$label))

  everything <- brfss_vars()
  expect_true("MYSTVAR" %in% everything$variable)
})

test_that("label drift collapses to one row with the latest label", {
  local_brfss_cache(2020, catalog = TRUE)
  out <- brfss_vars("GENHLTH")
  expect_identical(nrow(out), 1L)
  expect_identical(out$label, "General Health Status")
  expect_identical(out$years, "2019-2020, 2022")
})

test_that("no-match searches return an empty tibble and say so", {
  local_brfss_cache(2020, catalog = TRUE)
  expect_message(
    out <- brfss_vars("zzz_no_such_thing"),
    class = "brfssdata_empty_result"
  )
  expect_s3_class(out, "tbl_df")
  expect_identical(nrow(out), 0L)
  expect_identical(names(out), c("variable", "label", "years"))

  expect_message(
    out2 <- brfss_vars(years = 1999),
    class = "brfssdata_empty_result"
  )
  expect_identical(nrow(out2), 0L)
})

test_that("matching searches stay silent", {
  local_brfss_cache(2020, catalog = TRUE)
  expect_no_message(brfss_vars("smok"), class = "brfssdata_empty_result")
})

test_that("a typo'd pattern suggests close names and labels", {
  local_brfss_cache(2020, catalog = TRUE)
  # One edit from the variable name GENHLTH.
  cnd <- expect_message(
    brfss_vars("GENHLPH"),
    class = "brfssdata_empty_result"
  )
  expect_match(conditionMessage(cnd), "GENHLTH", fixed = TRUE)
  # One edit from the word "cigarettes" inside SMOKE100's label.
  cnd <- expect_message(
    brfss_vars("cigarrettes"),
    class = "brfssdata_empty_result"
  )
  expect_match(conditionMessage(cnd), "SMOKE100", fixed = TRUE)
})

test_that("a multi-word miss suggests variables matching every word", {
  local_brfss_cache(2020, catalog = TRUE)
  # Wrong order for a regex, but both words sit in SMOKE100's label.
  cnd <- expect_message(
    brfss_vars("cigarettes smoked"),
    class = "brfssdata_empty_result"
  )
  expect_match(conditionMessage(cnd), "SMOKE100", fixed = TRUE)
})

test_that("a years-restricted miss points at the other years", {
  local_brfss_cache(2020, catalog = TRUE)
  # SMOKE100 exists in 2019-2020 but not in 2022.
  cnd <- expect_message(
    brfss_vars("smok", years = 2022),
    class = "brfssdata_empty_result"
  )
  expect_match(conditionMessage(cnd), "SMOKE100", fixed = TRUE)
  expect_match(conditionMessage(cnd), "2019-2020", fixed = TRUE)
})

test_that("a typo confined to other years still gets a suggestion", {
  local_brfss_cache(2020, catalog = TRUE)
  # MYSTVAX is one edit from MYSTVAR, which exists only in 2020; the
  # fuzzy tier must look past the years filter and say where it lives.
  cnd <- expect_message(
    brfss_vars("MYSTVAX", years = 2022),
    class = "brfssdata_empty_result"
  )
  expect_match(conditionMessage(cnd), "MYSTVAR", fixed = TRUE)
  expect_match(conditionMessage(cnd), "2020", fixed = TRUE)
})

test_that("uncovered years are diagnosed as the problem, not the pattern", {
  local_brfss_cache(2020, catalog = TRUE)
  cnd <- expect_message(
    brfss_vars("qqqq", years = 1999),
    class = "brfssdata_empty_result"
  )
  expect_match(conditionMessage(cnd), "2019-2020, 2022", fixed = TRUE)
})

test_that("very short patterns skip the fuzzy tier", {
  local_brfss_cache(2020, catalog = TRUE)
  # At distance one, a two-character pattern partially matches almost
  # any label; suggestions built from that would be noise.
  cnd <- expect_message(
    brfss_vars("qz"),
    class = "brfssdata_empty_result"
  )
  expect_no_match(conditionMessage(cnd), "Close matches", fixed = TRUE)
})

test_that("regex metacharacters disable fuzzy suggestions", {
  local_brfss_cache(2020, catalog = TRUE)
  # GENHLPH alone would suggest GENHLTH; edits to a deliberate regex
  # are meaningless, so the alternation form must not.
  cnd <- expect_message(
    brfss_vars("GENHLPH|zzz"),
    class = "brfssdata_empty_result"
  )
  expect_no_match(conditionMessage(cnd), "GENHLTH", fixed = TRUE)
})

test_that("uncached catalog with download = FALSE serves the snapshot", {
  local_brfss_manifest(2020)
  expect_message(
    out <- brfss_vars("smok", download = FALSE),
    class = "brfssdata_bundled_fallback_note"
  )
  # The bundled snapshot is the real variable catalog.
  expect_gt(nrow(out), 0)
})

test_that("an invalid regular expression is rejected with its cause", {
  local_brfss_cache(2020, catalog = TRUE)
  expect_error(brfss_vars("("), class = "brfssdata_bad_pattern")
})

test_that("a multi-element pattern is rejected, not silently truncated", {
  # grepl() would use only the first element; with its warning
  # suppressed for the invalid-regex case, the truncation was silent.
  local_brfss_cache(2020, catalog = TRUE)
  expect_error(
    brfss_vars(c("GENHLTH", "SMOK")),
    class = "brfssdata_bad_pattern"
  )
})

test_that("a malformed years argument is rejected", {
  local_brfss_cache(2020, catalog = TRUE)
  expect_error(
    brfss_vars(years = "recent"),
    class = "brfssdata_bad_years_arg"
  )
  expect_error(
    brfss_vars(years = NA_real_),
    class = "brfssdata_bad_years_arg"
  )
  # 2024.9 used to truncate silently to 2024; Inf used to raise a base
  # coercion warning and return an empty tibble with no signal.
  expect_error(
    brfss_vars(years = 2024.9),
    class = "brfssdata_bad_years_arg"
  )
  expect_error(
    brfss_vars(years = Inf),
    class = "brfssdata_bad_years_arg"
  )
  expect_error(
    brfss_vars(years = numeric(0)),
    class = "brfssdata_bad_years_arg"
  )
})
