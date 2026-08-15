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
  # The fully-cached fast path in validate_years(): no manifest lookup
  # for validation. On the read path with download = TRUE the manifest
  # may refresh on its daily cadence (this one is fresh by mtime, so it
  # does not), and a year-omitting manifest carries no checksum entry,
  # so the recheck has no verdict. Either way a stale or year-omitting
  # manifest (the bundled fallback after
  # brfss_cache_clear(catalogs = TRUE), or a copy predating the year's
  # release) must never block a read of data already on disk, and
  # download = FALSE never consults the network at all.
  dir <- local_brfss_cache(2023)
  writeLines('{"years": [2020]}', file.path(dir, "manifest.json"))
  dat <- read_brfss(2023, quiet = TRUE)
  expect_gt(nrow(dat), 0)
  dat_offline <- read_brfss(2023, quiet = TRUE, download = FALSE)
  expect_identical(nrow(dat_offline), nrow(dat))
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

test_that("a typo'd vars aborts before any year download", {
  dir <- local_brfss_manifest(2020)
  write_fixture_catalog(dir)
  downloads <- 0L
  local_mocked_bindings(
    download_to_cache = function(...) {
      downloads <<- downloads + 1L
      stop("should not be reached")
    }
  )
  err <- expect_error(
    read_brfss(2020, vars = "GENHLT", quiet = TRUE),
    class = "brfssdata_bad_var"
  )
  expect_identical(downloads, 0L)
  # The near miss is named: GENHLT is one edit from GENHLTH.
  expect_match(conditionMessage(err), "GENHLTH", fixed = TRUE)
})

test_that("the gate names the years that do carry a missing variable", {
  dir <- local_brfss_manifest(2022)
  write_fixture_catalog(dir)
  downloads <- 0L
  local_mocked_bindings(
    download_to_cache = function(...) {
      downloads <<- downloads + 1L
      stop("should not be reached")
    }
  )
  # MYSTVAR exists in the catalog, but only in 2020.
  err <- expect_error(
    read_brfss(2022, vars = "MYSTVAR", quiet = TRUE),
    class = "brfssdata_bad_var"
  )
  expect_identical(downloads, 0L)
  expect_match(conditionMessage(err), "2020", fixed = TRUE)

  # The year hint survives even when other unknowns come first.
  err2 <- expect_error(
    read_brfss(
      2022,
      vars = c("AAA1", "BBB2", "CCC3", "MYSTVAR"),
      quiet = TRUE
    ),
    class = "brfssdata_bad_var"
  )
  expect_match(conditionMessage(err2), "2020", fixed = TRUE)
})

test_that("the parquet authority names near misses too", {
  # Fully cached, so the gate is skipped and query_parquet() raises the
  # error from the files' real schema.
  local_brfss_cache(2023)
  err <- expect_error(
    read_brfss(2023, vars = "GENHLT", quiet = TRUE, download = FALSE),
    class = "brfssdata_bad_var"
  )
  expect_match(conditionMessage(err), "GENHLTH", fixed = TRUE)
})

test_that("the pre-download gate passes real vars, `year`, and lowercase", {
  dir <- local_brfss_manifest(integer(0))
  write_fixture_catalog(dir)
  write_fixture_year(2020, dir)
  write_fixture_manifest(dir, 2020)
  real <- file.path(dir, "brfss_2020.parquet")
  keep <- withr::local_tempfile()
  file.copy(real, keep)
  unlink(real)
  local_mocked_bindings(
    download_to_cache = function(url, dest, ...) {
      file.copy(keep, dest)
      dest
    }
  )
  dat <- read_brfss(2020, vars = c("year", "genhlth"), quiet = TRUE)
  expect_gt(nrow(dat), 0)
  expect_true(all(c("year", "GENHLTH") %in% names(dat)))
})

test_that("the gate fails open when the catalog does not cover the years", {
  dir <- local_brfss_manifest(2023)
  write_fixture_catalog(dir) # covers 2019/2020/2022 only
  downloads <- 0L
  local_mocked_bindings(
    download_to_cache = function(url, dest, ...) {
      downloads <<- downloads + 1L
      write_fixture_year(2023, dirname(dest))
      dest
    }
  )
  # The typo still errors, but only after the (mocked) download:
  # query_parquet stays the authority for years the catalog cannot vouch for.
  expect_error(
    read_brfss(2023, vars = "NOPEVAR", quiet = TRUE),
    class = "brfssdata_bad_var"
  )
  expect_identical(downloads, 1L)
})

test_that("a virgin cache gates against the bundled catalog, silently", {
  local_brfss_manifest(2023)
  downloads <- 0L
  local_mocked_bindings(
    download_to_cache = function(...) {
      downloads <<- downloads + 1L
      stop("should not be reached")
    }
  )
  expect_no_message(
    expect_error(
      read_brfss(2023, vars = "NOT_A_REAL_COLUMN", quiet = TRUE),
      class = "brfssdata_bad_var"
    ),
    class = "brfssdata_bundled_fallback_note"
  )
  expect_identical(downloads, 0L)
})

test_that("download = FALSE keeps the not-cached error, even for a typo", {
  dir <- local_brfss_manifest(2020)
  write_fixture_catalog(dir)
  expect_error(
    read_brfss(2020, vars = "GENHLT", quiet = TRUE, download = FALSE),
    class = "brfssdata_not_cached"
  )
})

# Rewrite a fixture manifest so one asset's sha256 cannot match, the
# shape a republished release leaves behind.
break_manifest_hash <- function(dir, asset) {
  path <- file.path(dir, "manifest.json")
  m <- jsonlite::read_json(path)
  m$files[[asset]]$sha256 <- strrep("a", 64)
  jsonlite::write_json(m, path, auto_unbox = TRUE)
  invisible(path)
}

test_that("a failed checksum heal stays due and re-announces every call", {
  # The daily recheck used to be memoized before the re-download was
  # known to have succeeded, so an offline session announced the
  # mismatch once and then served the mismatched file in silence for the
  # rest of the session.
  dir <- local_brfss_cache(2023)
  break_manifest_hash(dir, "brfss_2023.parquet")
  local_mocked_bindings(
    download_to_cache = function(...) {
      cli::cli_abort("offline", class = "brfssdata_download_error")
    }
  )
  for (i in 1:2) {
    expect_message(
      expect_error(
        read_brfss(2023, vars = "GENHLTH", quiet = TRUE),
        class = "brfssdata_download_error"
      ),
      class = "brfssdata_cache_note"
    )
  }
  expect_true(asset_check_due("brfss_2023.parquet"))
})

test_that("a passing checksum recheck is memoized for the session", {
  local_brfss_cache(2023)
  expect_no_message(read_brfss(2023, vars = "GENHLTH", quiet = TRUE))
  expect_false(asset_check_due("brfss_2023.parquet"))
})

test_that("an integrity re-download is announced even under quiet", {
  # A republished asset changes the bytes under a stable URL. The
  # self-heal is silent progress, but the fact that the input changed is
  # not, so quiet = TRUE must not hide it.
  local_brfss_cache(2023)
  # One byte appended puts the file's size at odds with the manifest.
  cat("x", file = cache_path("brfss_2023.parquet"), append = TRUE)
  local_mocked_bindings(
    download_to_cache = function(...) {
      cli::cli_abort("offline", class = "brfssdata_download_error")
    }
  )
  expect_message(
    expect_error(
      read_brfss(2023, vars = "GENHLTH", quiet = TRUE),
      class = "brfssdata_download_error"
    ),
    class = "brfssdata_cache_note"
  )
})

test_that("boolean arguments are validated at entry", {
  local_brfss_cache(2023)
  expect_error(
    read_brfss(2023, vars = "GENHLTH", download = "nope"),
    class = "brfssdata_bad_download_arg"
  )
  expect_error(
    read_brfss(2023, vars = "GENHLTH", download = NA),
    class = "brfssdata_bad_download_arg"
  )
  # quiet used to crash only when vars was NULL and be accepted
  # silently otherwise, so both shapes are pinned.
  expect_error(
    read_brfss(2023, vars = "GENHLTH", quiet = "loud"),
    class = "brfssdata_bad_quiet_arg"
  )
  expect_error(
    read_brfss(2023, quiet = "loud"),
    class = "brfssdata_bad_quiet_arg"
  )
  expect_error(
    read_brfss(2023, na = "x", quiet = TRUE),
    class = "brfssdata_bad_na_arg"
  )
  # Every one of them also carries the shared parent class.
  expect_error(
    read_brfss(2023, download = 1),
    class = "brfssdata_bad_bool_arg"
  )
})

test_that("a cached file holding another year's data is refused", {
  # The air-gapped workflow is to hand-copy a cache directory, and a
  # botched copy leaves a plausible tibble of the wrong survey year.
  dir <- local_brfss_cache(c(2022, 2023))
  file.copy(
    file.path(dir, "brfss_2022.parquet"),
    file.path(dir, "brfss_2023.parquet"),
    overwrite = TRUE
  )
  err <- expect_error(
    read_brfss(2023, vars = "GENHLTH", download = FALSE, quiet = TRUE),
    class = "brfssdata_wrong_year_cache"
  )
  expect_s3_class(err, "brfssdata_corrupt_cache")
  expect_match(conditionMessage(err), "brfss_2023.parquet", fixed = TRUE)
  expect_match(conditionMessage(err), "2022", fixed = TRUE)
  expect_match(conditionMessage(err), "brfss_cache_clear", fixed = TRUE)
})

test_that("the year check passes multi-year and legitimately empty years", {
  local_brfss_cache(
    c(2022, 2023),
    states = list("2022" = 1, "2023" = 2)
  )
  dat <- read_brfss(2022:2023, vars = "GENHLTH", download = FALSE, quiet = TRUE)
  expect_identical(sort(unique(dat$year)), c(2022L, 2023L))
  # A states filter can leave a requested year with no rows at all,
  # which is an answer, not a damaged cache.
  filtered <- suppressWarnings(
    read_brfss(2022:2023, vars = "GENHLTH", states = 1, download = FALSE, quiet = TRUE)
  )
  expect_identical(unique(filtered$year), 2022L)
})

test_that("the full-load hint waits until the years are known available", {
  local_brfss_manifest(2023)
  expect_no_message(
    expect_error(
      read_brfss(2023, download = FALSE),
      class = "brfssdata_not_cached"
    ),
    class = "brfssdata_full_load_note"
  )
})

test_that("the not-cached error tells unpublished years from prefetchable", {
  local_brfss_manifest(2023)
  err <- expect_error(
    read_brfss(2050, download = FALSE, quiet = TRUE),
    class = "brfssdata_not_cached"
  )
  expect_match(conditionMessage(err), "not among the published releases")
  # Following the old advice failed with brfssdata_bad_year.
  expect_false(grepl("brfss_download(c(2050))", conditionMessage(err), fixed = TRUE))

  # A published year that is merely not cached keeps the prefetch hint.
  err2 <- expect_error(
    read_brfss(2023, download = FALSE, quiet = TRUE),
    class = "brfssdata_not_cached"
  )
  expect_match(
    conditionMessage(err2),
    "brfss_download(c(2023))",
    fixed = TRUE
  )

  # Mixed requests get both halves.
  err3 <- expect_error(
    read_brfss(c(2023, 2050), download = FALSE, quiet = TRUE),
    class = "brfssdata_not_cached"
  )
  expect_match(
    conditionMessage(err3),
    "brfss_download(c(2023))",
    fixed = TRUE
  )
  expect_match(conditionMessage(err3), "not among the published releases")
})

test_that("a case-insensitive match says which spelling came back", {
  # The lowercase name works here and then fails in the next dplyr
  # verb, which reports only that the column does not exist.
  local_brfss_cache(2023)
  msg <- expect_message(
    read_brfss(2023, vars = "genhlth", download = FALSE),
    class = "brfssdata_case_match_note"
  )
  expect_match(conditionMessage(msg), "GENHLTH", fixed = TRUE)
  expect_no_message(
    read_brfss(2023, vars = "genhlth", download = FALSE, quiet = TRUE),
    class = "brfssdata_case_match_note"
  )
  expect_no_message(
    read_brfss(2023, vars = "GENHLTH", download = FALSE),
    class = "brfssdata_case_match_note"
  )
})

test_that("the case note stays one line for a wide lowercase request", {
  local_brfss_cache(2023)
  msgs <- capture_messages(
    read_brfss(
      2023,
      vars = c("genhlth", "physhlth", "_state", "_psu"),
      download = FALSE
    )
  )
  hits <- grep("matched case-insensitively", msgs, fixed = TRUE)
  expect_length(hits, 1L)
  expect_match(msgs[[hits]], "1 more", fixed = TRUE)
})
