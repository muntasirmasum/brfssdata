# Contracts that no other test pins down: the exact arguments handed to
# survey, the release URL scheme, and the bundled offline manifest.

# Records how brfss_design() calls srvyr, without forcing the bare column
# symbols it passes (match.call keeps them unevaluated).
capture_design_call <- function(env = parent.frame()) {
  seen <- new.env(parent = emptyenv())
  orig <- srvyr::as_survey_design
  testthat::local_mocked_bindings(
    as_survey_design = function(...) {
      seen$args <- as.list(match.call())[-1]
      orig(...)
    },
    .package = "srvyr",
    .env = env
  )
  seen
}

test_that("singleton-PSU designs drop clustering and skip the strata check", {
  local_brfss_cache(c(2022, 2023))
  seen <- capture_design_call()
  brfss_design(2022:2023, quiet = TRUE)

  # check_strata = FALSE is load-bearing, not an optimisation. With
  # ids = NULL survey's nested-clusters test cross-tabulates every
  # observation against every stratum; on real pooled years that table
  # exceeds R's vector limit and brfss_design(2021:2023) dies with
  # "attempt to make a table with >= 2^31 elements". No fixture is large
  # enough to reproduce that, so the argument itself is pinned here.
  expect_true("check_strata" %in% names(seen$args))
  expect_identical(seen$args$check_strata, FALSE)
  expect_true("ids" %in% names(seen$args))
  expect_null(seen$args$ids)
})

test_that("shared-PSU designs keep clustering and nest it", {
  local_brfss_cache(2023, psu_size = 3)
  seen <- capture_design_call()
  brfss_design(2023, quiet = TRUE)

  expect_identical(seen$args$nest, TRUE)
  expect_false("check_strata" %in% names(seen$args))
  expect_identical(seen$args$ids, quote(brfss_psu))
})

test_that("brfss_design honors download = FALSE", {
  local_brfss_manifest(c(2022, 2023))
  expect_error(
    brfss_design(2023, download = FALSE, quiet = TRUE),
    class = "brfssdata_not_cached"
  )
})

test_that("brfss_design returns only the requested vars plus design cols", {
  local_brfss_cache(2023, extra = list("2023" = "UNWANTED"))
  des <- brfss_design(2023, vars = "GENHLTH", quiet = TRUE)
  expect_false("UNWANTED" %in% names(des$variables))
  expect_setequal(
    names(des$variables),
    c(
      "year",
      "GENHLTH",
      "_PSU",
      "_STSTR",
      "_LLCPWT",
      "brfss_wt",
      "brfss_psu",
      "brfss_strata"
    )
  )
})

# The option is written only for a design that actually carries a
# single-PSU stratum, so both contracts below need a year whose strata
# are not the fixture's evenly filled three.
write_lonely_year <- function(dir) {
  df <- data.frame(
    year = 2023L,
    psu = 1:5,
    ststr = c(1L, 1L, 2L, 2L, 3L), # stratum 3 holds one PSU
    wt = c(120, 250, 310, 150, 200),
    GENHLTH = c(1L, 2L, 1L, 2L, 1L),
    check.names = FALSE
  )
  names(df) <- c("year", DESIGN_PSU, DESIGN_STRATA, WEIGHT_POST, "GENHLTH")
  write_fixture_parquet(df, file.path(dir, "brfss_2023.parquet"))
  writeLines('{"years": [2023]}', file.path(dir, "manifest.json"))
}

test_that("survey's own \"fail\" default is treated as unset", {
  dir <- local_brfss_cache(integer(0))
  write_lonely_year(dir)
  # This is the state of a fresh session with survey loaded, and the
  # case the package exists to smooth over.
  withr::local_options(survey.lonely.psu = "fail")
  brfss_design(2023, quiet = TRUE)
  expect_identical(getOption("survey.lonely.psu"), "adjust")
})

test_that("tests do not inherit a lonely-PSU option from each other", {
  # brfss_design() sets the option for the session when the design needs
  # it. The fixture helper scopes it per test so the suite stays
  # order-independent and does not leave "adjust" behind in the calling
  # session.
  dir <- local_brfss_cache(integer(0))
  write_lonely_year(dir)
  expect_null(getOption("survey.lonely.psu"))
  brfss_design(2023, quiet = TRUE)
  expect_identical(getOption("survey.lonely.psu"), "adjust")
})

test_that("a malformed lonely-PSU option does not error the design", {
  local_brfss_cache(2023)
  withr::local_options(survey.lonely.psu = c("adjust", "remove"))
  expect_no_error(brfss_design(2023, quiet = TRUE))
})

test_that("brfssdata.lonely_psu wins, including a deliberate fail", {
  local_brfss_cache(2023)
  withr::local_options(
    brfssdata.lonely_psu = "fail",
    survey.lonely.psu = NULL
  )
  brfss_design(2023, vars = "GENHLTH", quiet = TRUE)
  expect_identical(getOption("survey.lonely.psu"), "fail")
})

test_that("a malformed brfssdata.lonely_psu aborts", {
  local_brfss_cache(2023)
  withr::local_options(brfssdata.lonely_psu = c("adjust", "fail"))
  expect_error(
    brfss_design(2023, vars = "GENHLTH", quiet = TRUE),
    class = "brfssdata_bad_option"
  )
})

test_that("release URLs follow the documented scheme", {
  expect_identical(
    year_url(2023),
    paste0(
      "https://github.com/muntasirmasum/brfssdata/releases/download/",
      "data-2023/brfss_2023.parquet"
    )
  )
  expect_identical(
    release_url("data-meta", "manifest.json"),
    paste0(
      "https://github.com/muntasirmasum/brfssdata/releases/download/",
      "data-meta/manifest.json"
    )
  )
  withr::local_options(brfssdata.repo = "someone/fork")
  expect_match(
    year_url(1999),
    "^https://github\\.com/someone/fork/releases/download/data-1999/"
  )
})

test_that("a missing year is fetched from its release URL", {
  dir <- local_brfss_manifest(2023)
  seen <- NULL
  local_mocked_bindings(
    download_to_cache = function(url, dest, ...) {
      seen <<- url
      write_fixture_year(2023, dirname(dest))
      dest
    }
  )
  read_brfss(2023, quiet = TRUE)
  expect_identical(seen, year_url(2023))
})

test_that("quiet controls whether a download announces itself", {
  fetch <- function(quiet) {
    local_brfss_manifest(2023)
    local_mocked_bindings(
      download_to_cache = function(url, dest, ...) {
        write_fixture_year(2023, dirname(dest))
        dest
      }
    )
    read_brfss(2023, quiet = quiet)
  }
  expect_message(fetch(quiet = FALSE), "Downloading BRFSS 2023")
  expect_no_message(fetch(quiet = TRUE))
})

test_that("the bundled offline manifest ships and parses", {
  # The last-resort fallback when the manifest cannot be refreshed, and
  # the path a machine with no network takes.
  path <- bundled_manifest_path()
  expect_true(nzchar(path) && file.exists(path))
  years <- parse_manifest(path)$years
  expect_type(years, "integer")
  expect_gt(length(years), 30)
  expect_true(all(c(1985L, 2011L) %in% years))
  expect_identical(years, sort(unique(years)))
})

test_that("cache year parsing only matches this package's asset names", {
  expect_identical(
    cached_file_year(c(
      "brfss_2023.parquet",
      "brfss_labels.parquet",
      "xx12345678.parquet",
      "manifest.json"
    )),
    c(2023L, NA_integer_, NA_integer_, NA_integer_)
  )
})

test_that("an empty vars request is rejected rather than silently ignored", {
  local_brfss_cache(2023)
  expect_error(
    read_brfss(2023, vars = character(0), quiet = TRUE),
    class = "brfssdata_bad_vars_arg"
  )
})
