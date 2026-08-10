# The rename crosswalk lookup and the read path's rename note.

test_that("any member of a family returns the whole family", {
  local_brfss_cache(2023)
  old <- brfss_crosswalk("OLDGEN", download = FALSE)
  new <- brfss_crosswalk("newgen", download = FALSE)
  expect_setequal(old$variable, c("OLDGEN", "NEWGEN"))
  expect_identical(old, new)
  expect_identical(
    sort(unique(old$generation)),
    c(1L, 2L)
  )
})

test_that("years filters rows but never redefines the family", {
  local_brfss_cache(2023)
  out <- brfss_crosswalk("OLDGEN", years = 2023, download = FALSE)
  expect_identical(out$variable, "NEWGEN")
})

test_that("a variable outside any family returns empty with a message", {
  local_brfss_cache(2023)
  expect_message(
    out <- brfss_crosswalk("GENHLTH", download = FALSE),
    class = "brfssdata_empty_result"
  )
  expect_identical(nrow(out), 0L)
})

test_that("malformed arguments are rejected", {
  expect_error(brfss_crosswalk(1), class = "brfssdata_bad_vars_arg")
  expect_error(
    brfss_crosswalk("X", years = "recent"),
    class = "brfssdata_bad_years_arg"
  )
  expect_error(
    brfss_crosswalk("X", years = Inf),
    class = "brfssdata_bad_years_arg"
  )
  expect_error(
    brfss_crosswalk("X", years = numeric(0)),
    class = "brfssdata_bad_years_arg"
  )
})

test_that("a rename-trap read points at the crosswalk", {
  # OLDGEN has data in 2022 only; the 2023 fixture lacks the column
  # entirely (all NA under union_by_name), while sibling NEWGEN covers
  # 2023. That is exactly the trap the note exists for.
  local_brfss_cache(
    c(2022, 2023),
    add_cols = list("2022" = list(OLDGEN = c(1, 2)))
  )
  msg <- expect_message(
    read_brfss(2022:2023, vars = "OLDGEN"),
    class = "brfssdata_rename_note"
  )
  expect_match(conditionMessage(msg), "OLDGEN")
  expect_match(conditionMessage(msg), "NEWGEN")
  expect_match(conditionMessage(msg), "brfss_crosswalk")
})

test_that("no rename note when the variable has data everywhere", {
  local_brfss_cache(
    c(2022, 2023),
    add_cols = list(
      "2022" = list(OLDGEN = c(1, 2)),
      "2023" = list(OLDGEN = c(1, 2))
    )
  )
  expect_no_message(
    read_brfss(2022:2023, vars = "OLDGEN"),
    class = "brfssdata_rename_note"
  )
})

test_that("the rename note survives quiet = TRUE", {
  # quiet governs progress output only; a variable silently empty in a
  # year its sibling covers is an analytical signal. Silence it by
  # class: suppressMessages(..., classes = "brfssdata_rename_note").
  local_brfss_cache(
    c(2022, 2023),
    add_cols = list("2022" = list(OLDGEN = c(1, 2)))
  )
  expect_message(
    read_brfss(2022:2023, vars = "OLDGEN", quiet = TRUE),
    class = "brfssdata_rename_note"
  )
})

test_that("the rename note never touches the network", {
  # guard_network() is active inside local_brfss_cache(), so reaching
  # the network would already fail loudly; this pins the no-crosswalk
  # case too (nothing cached, offline contract intact -> note simply
  # skipped for fixture vars outside the bundled snapshot's families).
  local_brfss_cache(
    c(2022, 2023),
    crosswalk = FALSE,
    add_cols = list("2022" = list(OLDGEN = c(1, 2)))
  )
  expect_no_message(
    read_brfss(2022:2023, vars = "OLDGEN"),
    class = "brfssdata_rename_note"
  )
})
