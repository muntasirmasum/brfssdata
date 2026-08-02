# Test fixtures: tiny parquet files shaped like real BRFSS years, plus a
# manifest, written into a temporary cache directory. No test touches the
# network or the user's real cache; both helpers install a guard that
# turns any unexpected download attempt into a loud failure.

write_fixture_year <- function(year, dir, n = 30, extra = NULL, psu_size = 1) {
  wt_col <- if (year >= 2011) "_LLCPWT" else "_FINALWT"
  set.seed(year)
  # psu_size > 1 gives each PSU that many respondents, the shape of the
  # files through 2000; the default makes every respondent their own PSU.
  # The stratum is derived from the PSU so that a PSU never straddles two
  # strata, which is what makes the pair non-unique when psu_size > 1.
  psu <- rep(seq_len(ceiling(n / psu_size)), each = psu_size)[seq_len(n)]
  df <- data.frame(
    year = as.integer(year),
    psu = psu,
    ststr = rep(1:3, length.out = max(psu))[psu],
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

# brfss_design() deliberately sets survey.lonely.psu for the session, so
# without this every test that builds a design leaks the option into the
# ones that follow and into the calling session. Scoping it per test also
# keeps the suite order-independent. A test that wants a specific value
# sets it after the fixture helper runs, and so still wins.
local_lonely_psu <- function(env) {
  withr::local_options(survey.lonely.psu = NULL, .local_envir = env)
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

# Write a manifest covering whatever parquet files are in `dir`. Schema 2
# (the default, matching what data-raw/04_upload.R publishes) carries a
# per-asset sha256/size map computed from the fixture files themselves,
# so the suite exercises the verified download path by default. Schema 1
# reproduces the pre-checksum layout for the fail-open tests.
write_fixture_manifest <- function(dir, years, schema = 2) {
  years <- sort(as.integer(years))
  if (schema == 1) {
    writeLines(
      sprintf('{"years": [%s]}', paste(years, collapse = ", ")),
      file.path(dir, "manifest.json")
    )
    return(invisible())
  }
  assets <- list.files(dir, pattern = "\\.parquet$")
  files <- lapply(file.path(dir, assets), function(path) {
    list(sha256 = cli::hash_file_sha256(path), size = file.size(path))
  })
  names(files) <- assets
  body <- list(schema_version = 2L, generated = "2026-01-01", years = years)
  if (length(files) > 0) {
    body$files <- files
  }
  jsonlite::write_json(
    body,
    file.path(dir, "manifest.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  invisible()
}

# Point the package at a temp cache stocked with fixture years and a fresh
# manifest. Returns the cache dir. Cleans itself up with the test.
local_brfss_cache <- function(
  years,
  extra = list(),
  catalog = FALSE,
  psu_size = 1,
  schema = 2,
  env = parent.frame()
) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_options(brfssdata.cache_dir = dir, .local_envir = env)
  local_lonely_psu(env)
  reset_manifest_state()
  guard_network(env)
  for (y in years) {
    write_fixture_year(
      y,
      dir,
      extra = extra[[as.character(y)]],
      psu_size = psu_size
    )
  }
  if (catalog) {
    write_fixture_catalog(dir)
  }
  write_fixture_manifest(dir, years, schema = schema)
  dir
}

# A manifest-only cache: years advertised but no parquet on disk.
local_brfss_manifest <- function(years, schema = 2, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_options(brfssdata.cache_dir = dir, .local_envir = env)
  local_lonely_psu(env)
  reset_manifest_state()
  guard_network(env)
  write_fixture_manifest(dir, years, schema = schema)
  dir
}

# A labels catalog fixture: GENHLTH fully mapped (complete), PHYSHLTH
# mixed (incomplete), DRIFTVAR with a code set that changes across years,
# DUPLABEL a complete map that gives two codes the same label.
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
  # A complete map that labels two codes identically, the shape that
  # makes factor() merge them (CDC ships several of these).
  labels <- rbind(
    labels,
    data.frame(
      year = c(2023L, 2023L),
      variable = c("DUPLABEL", "DUPLABEL"),
      code = c(0L, 1L),
      label = c("Same", "Same"),
      complete = c(TRUE, TRUE),
      stringsAsFactors = FALSE
    )
  )
  write_fixture_parquet(labels, file.path(dir, "brfss_labels.parquet"))
}

# A year whose stratum column carries a missing value.
write_fixture_year_na_strata <- function(year, dir, n = 30) {
  wt_col <- if (year >= 2011) "_LLCPWT" else "_FINALWT"
  set.seed(year)
  df <- data.frame(
    year = as.integer(year),
    psu = seq_len(n),
    ststr = c(NA_integer_, rep(1:3, length.out = n - 1)),
    wt = stats::runif(n, 100, 500),
    GENHLTH = sample(1:5, n, replace = TRUE),
    check.names = FALSE
  )
  names(df) <- c("year", "_PSU", "_STSTR", wt_col, "GENHLTH")
  write_fixture_parquet(df, file.path(dir, sprintf("brfss_%d.parquet", year)))
}
