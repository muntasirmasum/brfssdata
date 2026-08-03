# Test fixtures: tiny parquet files shaped like real BRFSS years, plus a
# manifest, written into a temporary cache directory. No test touches the
# network or the user's real cache; both helpers install a guard that
# turns any unexpected download attempt into a loud failure.

write_fixture_year <- function(
  year,
  dir,
  n = 30,
  extra = NULL,
  psu_size = 1,
  alt_weights = FALSE,
  states = 1
) {
  # The column name for the era weight comes from the package constants;
  # tests/testthat/test-constants.R anchors those against a hand-written
  # codebook table, so a swapped constant cannot agree with the fixtures.
  wt_col <- if (year >= BREAK_YEAR) WEIGHT_POST else WEIGHT_PRE
  set.seed(year)
  # psu_size > 1 gives each PSU that many respondents, the shape of the
  # files through 2000; the default makes every respondent their own PSU.
  # The stratum is derived from the PSU so that a PSU never straddles two
  # strata, which is what makes the pair non-unique when psu_size > 1.
  psu <- rep(seq_len(ceiling(n / psu_size)), each = psu_size)[seq_len(n)]
  # Every data column is stored as double because that is what the real
  # files carry: haven::read_xpt() reads numeric SAS variables as double
  # (data-raw/02_build_parquet.R), and only `year` is re-typed integer.
  # GENHLTH includes CDC's don't-know (7) and refused (9) codes, and
  # PHYSHLTH the 77/88/99 family, so tests can see what real analysis
  # variables contain.
  df <- data.frame(
    year = as.integer(year),
    psu = as.numeric(psu),
    ststr = as.numeric(rep(1:3, length.out = max(psu))[psu]),
    wt = stats::runif(n, 100, 500),
    GENHLTH = as.numeric(sample(c(1:5, 7, 9), n, replace = TRUE)),
    PHYSHLTH = as.numeric(sample(c(1:30, 77, 88, 99), n, replace = TRUE)),
    state = as.numeric(rep(states, length.out = n)),
    check.names = FALSE
  )
  names(df) <- c(
    "year",
    DESIGN_PSU,
    DESIGN_STRATA,
    wt_col,
    "GENHLTH",
    "PHYSHLTH",
    "_STATE"
  )
  # Guarantee the special codes appear regardless of the draw, so tests
  # can assert on them deterministically.
  df$GENHLTH[1:2] <- c(7, 9)
  df$PHYSHLTH[1:3] <- c(77, 88, 99)
  if (alt_weights) {
    # Both differ from the main weight on every row, like the real
    # files: _CLLCPWT as a legitimate final-weight override, _LLCPWT2
    # as an intermediate pipeline weight that should warn.
    df[["_CLLCPWT"]] <- df[[wt_col]] * 3 + 7
    df[["_LLCPWT2"]] <- df[[wt_col]] * 5 + 11
  }
  if (!is.null(extra)) {
    df[[extra]] <- as.numeric(sample(0:1, n, replace = TRUE))
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

# The tests that call the real download_to_cache() must stay on the
# local filesystem. A future edit that changed one to http:// would
# reach the network from a CRAN machine, so every such URL is asserted
# to be file:// before it is used.
local_file_url <- function(path) {
  testthat::expect_match(path, "^file://")
  path
}

# Clear the manifest failure memo for the test and restore whatever was
# there before when the test ends. Without the restore, a test that
# drives last_failure would leave the memo set in the session that ran
# devtools::test(), silently skipping real manifest refreshes for a day
# (the same leak class the suite already scopes for survey.lonely.psu).
local_manifest_state <- function(env = parent.frame()) {
  old <- as.list(manifest_state)
  rm(list = ls(manifest_state), envir = manifest_state)
  withr::defer(
    {
      rm(list = ls(manifest_state), envir = manifest_state)
      for (nm in names(old)) {
        assign(nm, old[[nm]], envir = manifest_state)
      }
    },
    envir = env
  )
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
  label_catalog = TRUE,
  psu_size = 1,
  alt_weights = integer(0),
  states = list(),
  schema = 2,
  env = parent.frame()
) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_options(brfssdata.cache_dir = dir, .local_envir = env)
  local_lonely_psu(env)
  local_manifest_state(env)
  guard_network(env)
  for (y in years) {
    write_fixture_year(
      y,
      dir,
      extra = extra[[as.character(y)]],
      psu_size = psu_size,
      alt_weights = y %in% alt_weights,
      states = states[[as.character(y)]] %||% 1
    )
  }
  if (catalog) {
    write_fixture_catalog(dir)
  }
  # The label catalog ships by default because brfss_design(na = TRUE),
  # the default, consults it; tests of the catalog-not-cached paths opt
  # out with label_catalog = FALSE.
  if (label_catalog) {
    write_fixture_labels(dir)
  }
  write_fixture_manifest(dir, years, schema = schema)
  dir
}

# A manifest-only cache: years advertised but no parquet on disk.
local_brfss_manifest <- function(years, schema = 2, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  withr::local_options(brfssdata.cache_dir = dir, .local_envir = env)
  local_lonely_psu(env)
  local_manifest_state(env)
  guard_network(env)
  write_fixture_manifest(dir, years, schema = schema)
  dir
}

# A labels catalog fixture: GENHLTH fully mapped (complete, including
# CDC's don't-know and refused codes, matching the fixture data),
# PHYSHLTH mixed (incomplete), DRIFTVAR with a code set that changes
# across years, DUPLABEL a complete map that gives two codes the same
# label.
write_fixture_labels <- function(dir) {
  genhlth_labels <- c(
    "Excellent",
    "Very good",
    "Good",
    "Fair",
    "Poor",
    "Don't know/Not Sure",
    "Refused"
  )
  genhlth <- data.frame(
    year = rep(c(2022L, 2023L), each = 7),
    variable = "GENHLTH",
    code = rep(c(1:5, 7L, 9L), 2),
    label = rep(genhlth_labels, 2),
    complete = TRUE,
    stringsAsFactors = FALSE
  )
  physhlth <- data.frame(
    year = 2023L,
    variable = "PHYSHLTH",
    code = c(77L, 88L, 99L),
    label = c("Dont know/Not sure", "None", "Refused"),
    complete = FALSE,
    stringsAsFactors = FALSE
  )
  # _STATE has a complete map in every real year; LABEL_EXCLUDE must
  # keep it numeric on every path so `_STATE == 6` keeps working.
  state <- data.frame(
    year = rep(c(2022L, 2023L), each = 2),
    variable = "_STATE",
    code = rep(c(1L, 2L), 2),
    label = rep(c("Alabama", "Alaska"), 2),
    complete = TRUE,
    stringsAsFactors = FALSE
  )
  # A substantive answer that merely contains the word "refused"; the
  # missing-code matcher must never treat it as missing.
  trapvar <- data.frame(
    year = 2023L,
    variable = "TRAPVAR",
    code = c(1L, 2L, 3L),
    label = c("Yes", "No", "Doctor refused when asked"),
    complete = TRUE,
    stringsAsFactors = FALSE
  )
  # Same code set across years but genuinely reworded (not cosmetic):
  # converts with the newest wording and warns. Codes 0/1 so the extra
  # fixture columns (which sample 0:1) stay inside the map.
  semdrift <- data.frame(
    year = c(2022L, 2022L, 2023L, 2023L),
    variable = "SEMDRIFT",
    code = c(0L, 1L, 0L, 1L),
    label = c(
      "Current smoker",
      "Former smoker",
      "Current smoker",
      "Quit over a year ago"
    ),
    complete = TRUE,
    stringsAsFactors = FALSE
  )
  driftvar <- data.frame(
    year = c(2022L, 2022L, 2023L, 2023L, 2023L),
    variable = "DRIFTVAR",
    code = c(0L, 1L, 0L, 1L, 2L),
    label = c("Yes", "No", "Yes", "No", "Maybe"),
    complete = TRUE,
    stringsAsFactors = FALSE
  )
  # A complete map that labels two codes identically, the shape that
  # makes factor() merge them (CDC ships several of these).
  duplabel <- data.frame(
    year = c(2023L, 2023L),
    variable = "DUPLABEL",
    code = c(0L, 1L),
    label = c("Same", "Same"),
    complete = TRUE,
    stringsAsFactors = FALSE
  )
  write_fixture_parquet(
    rbind(genhlth, physhlth, state, trapvar, semdrift, driftvar, duplabel),
    file.path(dir, "brfss_labels.parquet")
  )
}

# A year whose stratum column carries a missing value.
write_fixture_year_na_strata <- function(year, dir, n = 30) {
  wt_col <- if (year >= BREAK_YEAR) WEIGHT_POST else WEIGHT_PRE
  set.seed(year)
  df <- data.frame(
    year = as.integer(year),
    psu = as.numeric(seq_len(n)),
    ststr = as.numeric(c(NA, rep(1:3, length.out = n - 1))),
    wt = stats::runif(n, 100, 500),
    GENHLTH = as.numeric(sample(c(1:5, 7, 9), n, replace = TRUE)),
    check.names = FALSE
  )
  names(df) <- c("year", DESIGN_PSU, DESIGN_STRATA, wt_col, "GENHLTH")
  write_fixture_parquet(df, file.path(dir, sprintf("brfss_%d.parquet", year)))
}
