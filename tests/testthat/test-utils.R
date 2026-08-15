test_that("validate_years rejects malformed input", {
  local_brfss_manifest(2020:2023)
  expect_error(validate_years("2023"), class = "rlang_error")
  expect_error(validate_years(numeric(0)))
  expect_error(validate_years(2022.5))
  expect_error(validate_years(NA_integer_))
})

test_that("check_years_arg is the one strict shape gate", {
  for (bad in list("2024", NaN, Inf, -Inf, 2024.9, NA_real_, numeric(0))) {
    expect_error(check_years_arg(bad), class = "brfssdata_bad_years_arg")
  }
  expect_identical(check_years_arg(c(2023, 2022, 2023)), c(2022L, 2023L))
  # brfss_cache_clear()'s documented remove-nothing request
  expect_identical(
    check_years_arg(numeric(0), allow_empty = TRUE),
    integer(0)
  )
  expect_error(
    check_years_arg(Inf, allow_empty = TRUE),
    class = "brfssdata_bad_years_arg"
  )
})

test_that("validate_years rejects unpublished years", {
  local_brfss_manifest(2020:2023)
  expect_error(validate_years(1999), class = "brfssdata_bad_year")
  expect_error(validate_years(c(2022, 2030)), class = "brfssdata_bad_year")
  # Two missing years at once: pluralization over a plain length>1
  # vector crashes cli, so this pins the {.val} wrapping in the message.
  expect_error(
    validate_years(c(2029, 2030)),
    class = "brfssdata_bad_year"
  )
})

test_that("validate_years sorts, deduplicates, and passes valid years", {
  local_brfss_manifest(2011:2024)
  expect_identical(validate_years(c(2023, 2022, 2023)), c(2022L, 2023L))
})

test_that("validate_years fails informatively with no published years", {
  dir <- withr::local_tempdir()
  withr::local_options(brfssdata.cache_dir = dir)
  writeLines('{"years": []}', file.path(dir, "manifest.json"))
  expect_error(validate_years(2023), class = "brfssdata_no_data")
})

test_that("identifier and literal quoting are injection-safe", {
  expect_identical(quote_ident('a"b'), '"a""b"')
  expect_identical(quote_literal("it's"), "'it''s'")
})

test_that("summarize_years collapses runs", {
  expect_identical(summarize_years(integer(0)), "")
  expect_identical(summarize_years(2020L), "2020")
  expect_identical(
    summarize_years(c(2011:2013, 2020L)),
    "2011-2013, 2020"
  )
})

test_that("duckdb connections keep DuckDB's storage out of ~/.duckdb", {
  # shared_home = FALSE in duckdb_connect() is the load-bearing CRAN
  # write-location argument, and an argument here has been dropped in a
  # merge before (check_strata, restored in 57442b4). With it, DuckDB's
  # storage directories resolve into the session tempdir; without it,
  # into ~/.duckdb.
  con <- duckdb_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  dirs <- vapply(
    c("extension_directory", "secret_directory"),
    function(s) {
      DBI::dbGetQuery(
        con,
        sprintf("SELECT current_setting('%s') AS v", s)
      )$v
    },
    character(1)
  )
  duck_home <- normalizePath("~/.duckdb", mustWork = FALSE)
  for (dir in dirs) {
    expect_false(startsWith(normalizePath(dir, mustWork = FALSE), duck_home))
  }
})

test_that("query_parquet does not create ~/.duckdb", {
  duck_home <- path.expand("~/.duckdb")
  existed <- dir.exists(duck_home)
  dir <- withr::local_tempdir()
  path <- write_fixture_parquet(
    data.frame(year = 2023L, x = 1),
    file.path(dir, "probe.parquet")
  )
  query_parquet(path)
  expect_identical(dir.exists(duck_home), existed)
})

test_that("non-finite states are rejected, naming what was passed", {
  # as.integer(Inf) used to leak a base warning and then report the
  # unknown state as NA, naming the coercion result rather than the
  # input. check_years_arg() guards the same shape with its abs() bound.
  expect_no_warning(
    expect_error(resolve_states(Inf), class = "brfssdata_bad_states_arg")
  )
  e <- expect_error(
    resolve_states(c(48, -Inf)),
    class = "brfssdata_bad_states_arg"
  )
  expect_match(conditionMessage(e), "-Inf")
  expect_identical(resolve_states(c(48, 6)), c(6L, 48L))
})

test_that("error messages truncate pathological user values", {
  dir <- withr::local_tempdir()
  path <- write_fixture_parquet(
    data.frame(year = 2023L, GENHLTH = 1),
    file.path(dir, "probe.parquet")
  )
  huge <- strrep("A", 10000)
  e <- expect_error(
    query_parquet(path, vars = huge),
    class = "brfssdata_bad_var"
  )
  expect_lt(nchar(conditionMessage(e)), 500)
  # Still recognizable as what was typed.
  expect_match(conditionMessage(e), "AAAAAAAA")
})

test_that("truncation keeps short values whole", {
  expect_identical(truncate_values(c("GENHLTH", NA)), c("GENHLTH", NA))
  expect_identical(truncate_values(48), "48")
  expect_identical(
    truncate_values(strrep("A", 50), max_chars = 5L),
    "AAAAA..."
  )
})

test_that("an older duckdb is refused before a connection is opened", {
  # DESCRIPTION's pin is checked at install time only: duckdb's
  # namespace is not loaded when brfssdata loads, so a downgrade, or an
  # older copy earlier in .libPaths(), would otherwise silently lose the
  # shared_home guard.
  local_mocked_bindings(duckdb_version = function() package_version("1.5.4"))
  e <- expect_error(duckdb_connect(), class = "brfssdata_duckdb_version")
  expect_match(conditionMessage(e), DUCKDB_MIN_VERSION, fixed = TRUE)
  expect_match(conditionMessage(e), "1.5.4", fixed = TRUE)
})

test_that("the installed duckdb satisfies the package's own floor", {
  expect_true(duckdb_version() >= DUCKDB_MIN_VERSION)
})
