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

test_that("vars match case-insensitively and return canonical names", {
  local_brfss_cache(2023)
  dat <- read_brfss(2023, vars = "genhlth", quiet = TRUE)
  expect_identical(sort(names(dat)), c("GENHLTH", "year"))
  # exact and case-insensitive spellings of the same variable dedupe
  dat2 <- read_brfss(2023, vars = c("genhlth", "GENHLTH"), quiet = TRUE)
  expect_identical(sort(names(dat2)), c("GENHLTH", "year"))
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
  # Both years missing: pins the {.val} wrapping against cli's crash on
  # plural markers over plain length>1 vectors.
  expect_error(
    read_brfss(2022:2023, download = FALSE, quiet = TRUE),
    class = "brfssdata_not_cached"
  )
})

test_that("a cached year reads offline even when the manifest omits it", {
  # The fully-cached fast path in validate_years(): no manifest lookup,
  # no network. A stale or year-omitting manifest (the bundled fallback
  # after brfss_cache_clear(catalogs = TRUE), or a copy predating the
  # year's release) must not block a read of data already on disk.
  dir <- local_brfss_cache(2023)
  writeLines('{"years": [2020]}', file.path(dir, "manifest.json"))
  dat <- read_brfss(2023, quiet = TRUE)
  expect_gt(nrow(dat), 0)
})

test_that("a column typed text in one year and numeric in another refuses", {
  # union_by_name would promote the numeric year to VARCHAR, so the
  # double 9 becomes "9.0" next to the text year's "9" -- two distinct
  # values for one code with no warning (the real _MSACODE split
  # between 2000 and 2001 before the canonical-type rebuild). The
  # hosted files are now type-consistent, so this arises only from
  # stale cached files, and reading on would corrupt values.
  local_brfss_cache(
    c(2022, 2023),
    extra = list("2022" = "MIXEDVAR", "2023" = "MIXEDVAR"),
    chr_cols = list("2023" = "MIXEDVAR")
  )
  err <- expect_error(
    read_brfss(2022:2023, vars = "MIXEDVAR", quiet = TRUE),
    class = "brfssdata_type_conflict"
  )
  expect_match(conditionMessage(err), "MIXEDVAR")
  expect_match(conditionMessage(err), "brfss_cache_clear")
})

test_that("a single-year read of a retyped column is fine", {
  local_brfss_cache(
    c(2022, 2023),
    extra = list("2022" = "MIXEDVAR", "2023" = "MIXEDVAR"),
    chr_cols = list("2023" = "MIXEDVAR")
  )
  dat <- read_brfss(2023, vars = "MIXEDVAR", quiet = TRUE)
  expect_type(dat$MIXEDVAR, "character")
})

test_that("a type conflict outside the selection never blocks the read", {
  local_brfss_cache(
    c(2022, 2023),
    extra = list("2022" = "MIXEDVAR", "2023" = "MIXEDVAR"),
    chr_cols = list("2023" = "MIXEDVAR")
  )
  dat <- read_brfss(2022:2023, vars = "GENHLTH", quiet = TRUE)
  expect_gt(nrow(dat), 0)
  # A full-width read does hit the conflicted column, and must refuse.
  expect_error(
    read_brfss(2022:2023, quiet = TRUE),
    class = "brfssdata_type_conflict"
  )
})

test_that("a default full-width read says it is loading every column", {
  # 2023 is 351 columns over 433,323 rows, about 1.1 GB materialized,
  # and read_brfss() is the lower-level of the two full-load entry
  # points, so the note belongs here rather than only in brfss_design().
  local_brfss_cache(2023)
  expect_message(
    read_brfss(2023),
    class = "brfssdata_full_load_note"
  )
  # A vars selection has nothing to warn about, and quiet = TRUE keeps
  # its promise.
  expect_no_message(
    read_brfss(2023, vars = "GENHLTH"),
    class = "brfssdata_full_load_note"
  )
  expect_no_message(
    read_brfss(2023, quiet = TRUE),
    class = "brfssdata_full_load_note"
  )
})

test_that("no download is attempted when all years are cached", {
  local_brfss_cache(2023)
  local_mocked_bindings(
    download_to_cache = function(...) stop("network touched")
  )
  # The mock is what proves no download happened; this only checks that
  # quiet = TRUE stays quiet. expect_silent() would also fail on output
  # or a warning from any dependency, which is not what is being tested.
  expect_no_message(dat <- read_brfss(2023, quiet = TRUE))
  expect_gt(nrow(dat), 0)
})
