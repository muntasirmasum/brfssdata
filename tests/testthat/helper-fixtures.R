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
  states = 1,
  child_states = NULL,
  add_cols = NULL,
  chr_cols = NULL
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
    # files. _CLLCPWT is a legitimate final-weight override, and like
    # the real child weight it exists only for its module's records: NA
    # outside a deterministic first block of rows (in the 2023 file it
    # is NULL on 383,782 of 433,323 rows). _LLCPWT2 is an intermediate
    # pipeline weight that should warn, and in the real files it is
    # complete, so it stays complete here.
    # The default block is a row position, deliberately independent of
    # _STATE, so most tests see a domain that cuts across states.
    # child_states keys the domain on _STATE instead, which is what a
    # real module weight does and the only shape that can tell a
    # file-wide state comparison apart from a domain-wide one.
    covered <- if (is.null(child_states)) {
      seq_len(n) <= ceiling(n / 3)
    } else {
      df[["_STATE"]] %in% child_states
    }
    df[["_CLLCPWT"]] <- ifelse(covered, df[[wt_col]] * 3 + 7, NA_real_)
    df[["_LLCPWT2"]] <- df[[wt_col]] * 5 + 11
  }
  if (!is.null(extra)) {
    df[[extra]] <- as.numeric(sample(0:1, n, replace = TRUE))
  }
  # Named list of extra columns with explicit values, recycled to n;
  # for tests that need specific codes present (a 100000 code, a 9
  # missing bucket) rather than the 0/1 draw `extra` gives.
  if (!is.null(add_cols)) {
    for (nm in names(add_cols)) {
      df[[nm]] <- rep(as.numeric(add_cols[[nm]]), length.out = n)
    }
  }
  # Columns to store as text, for mixed-type fixtures: name a column
  # here in one year but not another and the two files disagree on the
  # stored type, the shape check_type_consistency() refuses.
  if (!is.null(chr_cols)) {
    for (nm in chr_cols) {
      df[[nm]] <- as.character(df[[nm]])
    }
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

# A two-generation rename family: OLDGEN covers 2022, NEWGEN covers
# 2023, so requesting OLDGEN across both years should trip the rename
# note exactly once.
write_fixture_crosswalk <- function(dir) {
  xwalk <- data.frame(
    concept = c("mixgen", "mixgen"),
    variable = c("OLDGEN", "NEWGEN"),
    year = c(2022L, 2023L),
    generation = c(1L, 2L),
    status = c("verified", "verified"),
    comparable = c(NA, TRUE),
    note = c("", ""),
    stringsAsFactors = FALSE
  )
  write_fixture_parquet(xwalk, file.path(dir, "brfss_crosswalk.parquet"))
}

# The year inventory behind brfss_year_info(), shaped like the hosted
# asset (cached is computed locally, so it is not a column here).
write_fixture_year_info <- function(dir, years = c(2022L, 2023L)) {
  years <- sort(as.integer(years))
  info <- data.frame(
    year = years,
    respondents = rep(30L, length(years)),
    variables = rep(6L, length(years)),
    states = rep(1L, length(years)),
    size = rep(1000, length(years)),
    codebook_url = sprintf(
      "https://www.cdc.gov/brfss/annual_data/annual_%d.html",
      years
    ),
    stringsAsFactors = FALSE
  )
  write_fixture_parquet(info, file.path(dir, "brfss_year_info.parquet"))
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
  crosswalk = TRUE,
  year_info = TRUE,
  psu_size = 1,
  alt_weights = integer(0),
  states = list(),
  child_states = list(),
  add_cols = list(),
  chr_cols = list(),
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
      states = states[[as.character(y)]] %||% 1,
      child_states = child_states[[as.character(y)]],
      add_cols = add_cols[[as.character(y)]],
      chr_cols = chr_cols[[as.character(y)]]
    )
  }
  if (catalog) {
    write_fixture_catalog(dir)
  }
  # The label catalog ships by default because brfss_design(na = TRUE),
  # the default, consults it; tests of the catalog-not-cached paths opt
  # out with label_catalog = FALSE. Fixture years from 1998 on get
  # GENHLTH/_STATE rows so the coverage note stays quiet for them, like
  # the real catalog; earlier fixture years get none, also like the
  # real catalog.
  # Boundary caution: a full-width fixture design loads GENHLTH and
  # PHYSHLTH as data columns, and only GENHLTH is catalogued, so
  # coverage sits at exactly 1 of 2 = 0.5 against the strictly-less-
  # than-0.5 partial threshold in note_na_coverage(). Adding a third
  # uncatalogued default column would tip every full-width na = TRUE
  # design test into the partial-coverage note.
  if (label_catalog) {
    write_fixture_labels(dir, extra_years = years)
  }
  # The crosswalk and year inventory ship by default too, so the read
  # path's rename note and brfss_download() resolve against fixtures,
  # never against the bundled snapshots or the network.
  if (crosswalk) {
    write_fixture_crosswalk(dir)
  }
  if (year_info) {
    write_fixture_year_info(dir, years = if (length(years) > 0) years else 2023L)
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
# label, FRUITVAR a calculated-variable missing bucket with a trailing
# noun, BIGCODE a map whose code is at R's scientific-notation
# threshold, SEMDRIFT and COSDRIFT a real and a cosmetic change of
# wording across years. extra_years mirrors the real catalog's
# coverage: fixture years from 1998 on get GENHLTH/_STATE rows; earlier
# years get none.
write_fixture_labels <- function(dir, extra_years = integer(0)) {
  label_years <- sort(unique(c(
    2022L,
    2023L,
    as.integer(extra_years[extra_years >= 1998])
  )))
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
    year = rep(label_years, each = 7),
    variable = "GENHLTH",
    code = rep(c(1:5, 7L, 9L), length(label_years)),
    label = rep(genhlth_labels, length(label_years)),
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
    year = rep(label_years, each = 2),
    variable = "_STATE",
    code = rep(c(1L, 2L), length(label_years)),
    label = rep(c("Alabama", "Alaska"), length(label_years)),
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
  # refuses conversion, keeps the codes, and warns. Codes 0/1 so the
  # extra fixture columns (which sample 0:1) stay inside the map.
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
  # The same map in both years apart from CDC's house abbreviation
  # ("< 12 months" against "less than 12 months"): cosmetic, so it must
  # convert silently. Pins the carve-out in normalize_semantic(), which
  # would otherwise delete the "<" and read the two as different.
  cosdrift <- data.frame(
    year = c(2022L, 2022L, 2023L, 2023L),
    variable = "COSDRIFT",
    code = c(0L, 1L, 0L, 1L),
    label = c(
      "Anytime < 12 months ago",
      "Never",
      "Anytime less than 12 months ago",
      "Never"
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
  # The calculated-variable shape from the real files: the missing
  # bucket's label carries a trailing noun ("... missing values", the
  # _FRTLT1A wording, acute-apostrophe mojibake included), which the
  # whole-token rule alone would reject.
  fruitvar <- data.frame(
    year = 2023L,
    variable = "FRUITVAR",
    code = c(1L, 2L, 9L),
    label = c(
      "Consumed fruit one or more times per day",
      "Consumed fruit less than one time per day",
      "Don´t know, refused or missing values"
    ),
    complete = TRUE,
    stringsAsFactors = FALSE
  )
  # A code at R's scientific-notation threshold: as.character(1e5) is
  # "1e+05", so any string-based code matching silently misses it.
  bigcode <- data.frame(
    year = 2023L,
    variable = "BIGCODE",
    code = c(1L, 100000L),
    label = c("Yes", "Refused"),
    complete = TRUE,
    stringsAsFactors = FALSE
  )
  write_fixture_parquet(
    rbind(
      genhlth,
      physhlth,
      state,
      trapvar,
      semdrift,
      cosdrift,
      driftvar,
      duplabel,
      fruitvar,
      bigcode
    ),
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
