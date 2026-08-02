# Test fixtures: tiny parquet files shaped like real BRFSS years, plus a
# manifest, written into a temporary cache directory. No test touches the
# network or the user's real cache; both helpers install a guard that
# turns any unexpected download attempt into a loud failure.

write_fixture_year <- function(year, dir, n = 30, extra = NULL) {
  wt_col <- if (year >= 2011) "_LLCPWT" else "_FINALWT"
  set.seed(year)
  df <- data.frame(
    year = as.integer(year),
    psu = seq_len(n),
    ststr = rep(1:3, length.out = n),
    wt = stats::runif(n, 100, 500),
    GENHLTH = sample(1:5, n, replace = TRUE),
    check.names = FALSE
  )
  names(df) <- c("year", "_PSU", "_STSTR", wt_col, "GENHLTH")
  if (!is.null(extra)) {
    df[[extra]] <- sample(0:1, n, replace = TRUE)
  }
  write_fixture_parquet(df, file.path(dir, sprintf("brfss_%d.parquet", year)))
}

write_fixture_parquet <- function(df, path) {
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  duckdb::duckdb_register(con, "fixture", df)
  DBI::dbExecute(
    con,
    sprintf("COPY fixture TO '%s' (FORMAT parquet)", gsub("'", "''", path))
  )
  path
}

# A small variable catalog exercising NA labels and label drift.
write_fixture_catalog <- function(dir) {
  catalog <- data.frame(
    variable = c(
      "GENHLTH",
      "GENHLTH",
      "GENHLTH",
      "SMOKE100",
      "SMOKE100",
      "MYSTVAR"
    ),
    label = c(
      "General health",
      "General health",
      "General Health Status",
      "Smoked 100 cigarettes",
      "Smoked at least 100 cigarettes",
      NA
    ),
    year = c(2019L, 2020L, 2022L, 2019L, 2020L, 2020L),
    check.names = FALSE
  )
  write_fixture_parquet(catalog, file.path(dir, "brfss_variables.parquet"))
}

guard_network <- function(env) {
  testthat::local_mocked_bindings(
    download_to_cache = function(url, ...) {
      stop("unexpected download attempt in test: ", url)
    },
    .env = env
  )
}

reset_manifest_state <- function() {
  assign("last_failure", NULL, envir = manifest_state)
}

# Point the package at a temp cache stocked with fixture years and a fresh
# manifest. Returns the cache dir. Cleans itself up with the test.
local_brfss_cache <- function(
  years,
  extra = list(),
  catalog = FALSE,
  env = parent.frame()
) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_options(brfssdata.cache_dir = dir, .local_envir = env)
  reset_manifest_state()
  guard_network(env)
  for (y in years) {
    write_fixture_year(y, dir, extra = extra[[as.character(y)]])
  }
  if (catalog) {
    write_fixture_catalog(dir)
  }
  writeLines(
    sprintf('{"years": [%s]}', paste(years, collapse = ", ")),
    file.path(dir, "manifest.json")
  )
  dir
}

# A manifest-only cache: years advertised but no parquet on disk.
local_brfss_manifest <- function(years, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_options(brfssdata.cache_dir = dir, .local_envir = env)
  reset_manifest_state()
  guard_network(env)
  writeLines(
    sprintf('{"years": [%s]}', paste(years, collapse = ", ")),
    file.path(dir, "manifest.json")
  )
  dir
}

# A labels catalog fixture: GENHLTH fully mapped (complete), PHYSHLTH
# mixed (incomplete), DRIFTVAR with a code set that changes across years.
write_fixture_labels <- function(dir) {
  labels <- data.frame(
    year = c(
      rep(2022L, 5),
      rep(2023L, 5),
      2023L,
      2023L,
      2022L,
      2022L,
      2023L,
      2023L,
      2023L
    ),
    variable = c(
      rep("GENHLTH", 10),
      "PHYSHLTH",
      "PHYSHLTH",
      rep("DRIFTVAR", 5)
    ),
    code = c(
      1:5,
      1:5,
      88L,
      99L,
      0L,
      1L,
      0L,
      1L,
      2L
    ),
    label = c(
      "Excellent",
      "Very good",
      "Good",
      "Fair",
      "Poor",
      "Excellent",
      "Very good",
      "Good",
      "Fair",
      "Poor",
      "None",
      "Refused",
      "Yes",
      "No",
      "Yes",
      "No",
      "Maybe"
    ),
    complete = c(rep(TRUE, 10), FALSE, FALSE, rep(TRUE, 5)),
    stringsAsFactors = FALSE
  )
  write_fixture_parquet(labels, file.path(dir, "brfss_labels.parquet"))
}
