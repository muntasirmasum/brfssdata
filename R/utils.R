# Internal constants and helpers

# First survey year of the combined landline-and-cell-phone (LLCP) design.
# Weighting changed from post-stratification (_FINALWT) to raking (_LLCPWT);
# CDC states estimates are not directly comparable across this boundary.
BREAK_YEAR <- 2011L

DESIGN_PSU <- "_PSU"
DESIGN_STRATA <- "_STSTR"
WEIGHT_PRE <- "_FINALWT"
WEIGHT_POST <- "_LLCPWT"

# CDC's final analysis weights, the only columns brfss_design() accepts
# as `weight` without unsafe_weight = TRUE. Membership is by name from
# the hosted variable catalog and CDC's annual codebooks, never by
# label rule (_FINALWT's pre-1999 catalog label is "PRODUCT OF _POSTSTR
# AND _WT1", which no text rule would keep). The spans are anchored
# independently in tests/testthat/test-constants.R; last_year NA means
# still published. full_sample separates weights that must cover every
# respondent (a missing value there means a damaged file) from domain
# weights that cover only their module's records (missing values there
# subset the design to the domain).
FINAL_WEIGHTS <- data.frame(
  weight = c(
    "_FINALWT",
    "_LLCPWT",
    "_CLLCPWT",
    "_CHILDWT",
    "_HOUSEWT",
    "_FINALQ1",
    "_FINALQ2",
    "_CHILDQ1",
    "_CHILDQ2"
  ),
  first_year = c(
    1985L,
    2011L,
    2011L,
    2006L,
    2006L,
    2007L,
    2007L,
    2007L,
    2007L
  ),
  last_year = c(2010L, NA, NA, 2010L, 2010L, 2007L, 2007L, 2007L, 2007L),
  full_sample = c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE),
  stringsAsFactors = FALSE
)

# Intermediate stages of CDC's weighting pipeline that ship in the files
# but are not final analysis weights. Their own catalog labels say so:
# stratum weight, post-stratification weight, raw weighting factor,
# design weight, density and area-code stratum weights, probability of
# selection, and the 2007 questionnaire-version variants of each.
# brfss_design() refuses them unless unsafe_weight = TRUE, and then
# warns with the pointed class.
INTERMEDIATE_WEIGHTS <- c(
  "_STRWT",
  "_POSTSTR",
  "_RAWRAKE",
  "_WT2RAKE",
  "_LLCPWT2",
  "_WT1",
  "_WT2",
  "_RAW",
  "_CSA",
  "_WT2CH",
  "_WT2HH",
  "_RAWCH",
  "_RAWHH",
  "_POSTCH",
  "_POSTHH",
  "_DENWT",
  "_GEOWT",
  "_ACPRWT",
  "BPSELWT",
  "_WT2Q1",
  "_WT2Q2",
  "_WT2CH1",
  "_WT2CH2",
  "_POSTQ1",
  "_POSTQ2",
  "_POSTCH1",
  "_POSTCH2",
  "_RAWQ1",
  "_RAWQ2",
  "_RAWCH1",
  "_RAWCH2"
)

# Columns that keep their numeric codes on every labeling and
# missing-code path, on both the read and the design routes: a factor
# _STATE would make `_STATE == 6` silently match nothing, and a labeled
# weight or design variable would corrupt the survey design. Built from
# the weight tables above so no weight, final or intermediate, is ever
# labeled or na-recoded.
LABEL_EXCLUDE <- c(
  "_STATE",
  DESIGN_PSU,
  DESIGN_STRATA,
  FINAL_WEIGHTS$weight,
  INTERMEDIATE_WEIGHTS,
  "year"
)

brfss_repo <- function() {
  getOption("brfssdata.repo", "muntasirmasum/brfssdata")
}

release_url <- function(tag, asset) {
  sprintf(
    "https://github.com/%s/releases/download/%s/%s",
    brfss_repo(),
    tag,
    asset
  )
}

year_asset <- function(year) sprintf("brfss_%d.parquet", year)

year_url <- function(year) {
  release_url(sprintf("data-%d", year), year_asset(year))
}

# Shared argument-shape validation for every user-facing `years`
# argument: numeric, non-empty (unless allow_empty), no NA, whole, and
# inside integer range. The abs() bound is the only guard that rejects
# Inf, because Inf == trunc(Inf). Returns years sorted, deduplicated,
# and as integers, so callers filter without their own as.integer()
# (whose silent truncation is exactly the bug this closes:
# brfss_cache_clear(2024.9) used to delete the 2024 file).
# validate_years() layers the published-years check on top for the
# download paths; catalog-filtering entry points call this directly.
# allow_empty = TRUE serves brfss_cache_clear(), where integer(0) is
# the documented remove-nothing request.
check_years_arg <- function(
  years,
  allow_empty = FALSE,
  call = rlang::caller_env()
) {
  if (
    !is.numeric(years) ||
      (!allow_empty && length(years) == 0) ||
      anyNA(years) ||
      any(years != trunc(years)) ||
      any(abs(years) > .Machine$integer.max)
  ) {
    cli::cli_abort(
      c(
        "{.arg years} must be one or more whole survey years,
         e.g. {.code 2019:2023}.",
        "x" = "Got {.obj_type_friendly {years}}."
      ),
      class = "brfssdata_bad_years_arg",
      call = call
    )
  }
  sort(unique(as.integer(years)))
}

# The one gate for every TRUE/FALSE argument in the package. The
# switches used to divide into three camps: `na` and `unsafe_weight`
# aborted with a class, `download` and friends reached `&&` and died
# with base R's "invalid 'y' type in 'x && y'" (no class, no argument
# named), and `verify` and `catalogs` took anything at all through
# isTRUE() and quietly behaved as FALSE, so `verify = "yes"` hashed
# nothing while reading as a request to hash. Each caller passes the
# per-argument class the conditions page already documents.
check_bool_arg <- function(
  x,
  arg,
  class = paste0("brfssdata_bad_", arg, "_arg"),
  call = rlang::caller_env()
) {
  if (isTRUE(x) || isFALSE(x)) {
    return(x)
  }
  cli::cli_abort(
    c(
      "{.arg {arg}} must be TRUE or FALSE.",
      "x" = "Got {.obj_type_friendly {x}}."
    ),
    class = c(class, "brfssdata_bad_bool_arg"),
    call = call
  )
}

# Shared year-sniff for the metadata lookups' vars guards: when a
# numeric first argument looks like survey years, say which argument
# they belong in. Returns a cli bullet to append to the abort, or NULL.
# The predicate is brfss_labels()'s original, kept verbatim: numeric(0)
# vacuously passes all() and keeps its hint, as it always has.
vars_arg_year_hint <- function(vars, fn) {
  year_like <- is.numeric(vars) &&
    all(vars >= 1984 & vars <= 2100, na.rm = TRUE)
  if (!year_like) {
    return(NULL)
  }
  c(
    "i" = paste0(
      "Did you mean {.code ",
      fn,
      "(years = ...)}? The first
       argument is variable names; survey years come second."
    )
  )
}

validate_years <- function(
  years,
  download = TRUE,
  quiet = FALSE,
  call = rlang::caller_env()
) {
  years <- check_years_arg(years, call = call)

  # Fully cached requests are honored as-is: no manifest lookup, no
  # network, keeping the documented offline contract.
  if (all(file.exists(cache_path(year_asset(years))))) {
    return(years)
  }
  # With download = FALSE the manifest is irrelevant too; the caller's
  # cache check raises the precise not-cached error.
  if (!download) {
    return(years)
  }

  available <- brfss_years(quiet = quiet)
  if (length(available) == 0) {
    cli::cli_abort(
      c(
        "No BRFSS data releases are available.",
        "i" = "The data manifest could not be read or lists no published years.",
        "i" = "Check {.url https://github.com/{brfss_repo()}/releases} or try again later."
      ),
      class = "brfssdata_no_data",
      call = call
    )
  }
  missing <- setdiff(years, available)
  if (length(missing) > 0) {
    cli::cli_abort(
      c(
        "Year{?s} {.val {as.character(missing)}} {?is/are} not available.",
        "i" = "Published years: {summarize_years(available)}
               ({length(available)} year{?s})."
      ),
      class = "brfssdata_bad_year",
      call = call
    )
  }
  years
}

# Collapse c(2011, 2012, 2013, 2020) to "2011-2013, 2020". Used in
# messages everywhere a plain {min}-{max} range would misrepresent
# non-contiguous input.
summarize_years <- function(years) {
  if (length(years) == 0) {
    return("")
  }
  # The run-length logic below assumes ascending, deduplicated input.
  years <- sort(unique(years))
  breaks <- c(0, which(diff(years) != 1), length(years))
  runs <- mapply(
    function(from, to) {
      if (years[from] == years[to]) {
        as.character(years[from])
      } else {
        paste0(years[from], "-", years[to])
      }
    },
    from = utils::head(breaks, -1) + 1,
    to = utils::tail(breaks, -1)
  )
  paste(runs, collapse = ", ")
}

# Nearest names for a did-you-mean hint: case-insensitive edit distance
# against the candidate pool, with a length-scaled threshold so short
# names tolerate one edit and longer ones a few (GENHLT reaches
# GENHLTH; MYSTVAR never reaches GENHLTH). Ordered by distance, ties
# alphabetical; empty when nothing is close.
suggest_similar_vars <- function(unknown, known, n_max = 3L) {
  unknown <- unique(unknown)
  known <- unique(known)
  if (length(unknown) == 0 || length(known) == 0) {
    return(character(0))
  }
  d <- utils::adist(toupper(unknown), toupper(known))
  ok <- sweep(d, 1L, edit_distance_limit(unknown), `<=`)
  if (!any(ok)) {
    return(character(0))
  }
  hit <- which(ok, arr.ind = TRUE)
  cand <- data.frame(
    name = known[hit[, "col"]],
    dist = d[hit],
    stringsAsFactors = FALSE
  )
  cand <- cand[order(cand$dist, cand$name, method = "radix"), , drop = FALSE]
  utils::head(unique(cand$name), n_max)
}

# How many edits away a name may be and still count as close: one for
# short names, scaling up slowly (GENHLT reaches GENHLTH; MYSTVAR
# never reaches GENHLTH). The single tuning knob for every fuzzy path.
edit_distance_limit <- function(x) {
  pmax(1L, ceiling(nchar(x) / 4))
}

# Hint bullets for an unknown-variable error: the years that do carry
# each missing variable (it exists, just not in the requested scope),
# then a did-you-mean against the in-scope names for the rest. The
# split is decided for every unknown, so a real variable never falls
# through to the typo hint; only the emitted year bullets are capped.
# Bullets come back fully rendered and brace-escaped, ready to append
# to a cli message.
var_not_found_hints <- function(unknown, catalog_vars, catalog_years, scope_vars) {
  unknown <- unknown[!duplicated(toupper(unknown))]
  up <- toupper(catalog_vars)
  exists_elsewhere <- vapply(
    unknown,
    function(u) any(up == toupper(u)),
    logical(1)
  )
  hints <- vapply(
    utils::head(unknown[exists_elsewhere], 3L),
    function(u) {
      yrs <- catalog_years[up == toupper(u)]
      shown <- truncate_values(u)
      cli::format_inline(
        "{.val {shown}} is available in {summarize_years(yrs)}."
      )
    },
    character(1),
    USE.NAMES = FALSE
  )
  sugg <- suggest_similar_vars(unknown[!exists_elsewhere], scope_vars)
  if (length(sugg) > 0) {
    hints <- c(hints, cli::format_inline("Did you mean {.val {sugg}}?"))
  }
  escape_cli_braces(hints)
}

# User-typed values are quoted back so the reader recognizes what they
# passed, and the head is what makes them recognizable: a 10,000-
# character "variable name" reproduced whole turned a 130-character
# error into a 10,132-character one. Only the rendered text is
# shortened; matching and lookups still use the value as typed.
truncate_values <- function(x, max_chars = 40L) {
  x <- as.character(x)
  n <- nchar(x, type = "chars", allowNA = TRUE)
  long <- !is.na(x) & !is.na(n) & n > max_chars
  x[long] <- paste0(substr(x[long], 1L, max_chars), "...")
  x
}

# cli re-reads message vectors as glue templates, so text that is
# already rendered (or that carries user-typed braces) must have its
# braces doubled before it is passed along.
escape_cli_braces <- function(x) {
  gsub("{", "{{", gsub("}", "}}", x, fixed = TRUE), fixed = TRUE)
}

# Quote a DuckDB identifier (double quotes, doubled internal quotes).
quote_ident <- function(x) {
  paste0('"', gsub('"', '""', x, fixed = TRUE), '"')
}

# Quote a DuckDB string literal (single quotes, doubled internal quotes).
quote_literal <- function(x) {
  paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
}

# The first duckdb release carrying shared_home; kept in step with
# DESCRIPTION's Imports pin by tests/testthat/test-constants.R.
DUCKDB_MIN_VERSION <- "1.5.5"

# Split out so tests can pin a version without disturbing the installed
# package.
duckdb_version <- function() {
  utils::packageVersion("duckdb")
}

# DESCRIPTION's pin is enforced at install time only: duckdb's namespace
# is not loaded when brfssdata loads, so R's load-time version check
# never runs, and a later downgrade (or an older duckdb earlier in
# .libPaths()) would silently drop shared_home below, either resuming
# home-directory writes or failing with an argument error that never
# mentions the version. Checked per connection rather than memoized:
# packageVersion() reads the loaded namespace's metadata and measures at
# roughly 1% of the cost of opening a connection.
check_duckdb_version <- function(call = rlang::caller_env()) {
  have <- duckdb_version()
  if (have >= DUCKDB_MIN_VERSION) {
    return(invisible(have))
  }
  cli::cli_abort(
    c(
      "{.pkg duckdb} {DUCKDB_MIN_VERSION} or later is required; found
       {as.character(have)}.",
      "x" = "Earlier versions have no {.arg shared_home} argument, which
             is what keeps DuckDB from writing to your home directory.",
      "i" = "Update with {.code install.packages(\"duckdb\")}, and check
             {.code find.package(\"duckdb\", .libPaths())} if an older
             copy shadows it."
    ),
    class = "brfssdata_duckdb_version",
    call = call
  )
}

duckdb_connect <- function(call = rlang::caller_env()) {
  check_duckdb_version(call = call)
  # shared_home = FALSE keeps DuckDB from writing to ~/.duckdb; local
  # parquet queries need no extensions, so a temporary home is fine (and
  # required by CRAN policy on writing outside the session tempdir).
  DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
}

# Map requested variable names onto the actual columns,
# case-insensitively. An exact match always wins; otherwise a
# case-insensitive match substitutes the canonical CDC name (users
# often type genhlth for GENHLTH). Names that match nothing are
# returned as typed so the caller's error shows the original input.
match_vars_ci <- function(vars, columns) {
  # ifelse() on a zero-length test returns logical(0), which would turn
  # an empty request into "every column matched"; keep the type instead.
  if (length(vars) == 0) {
    return(character(0))
  }
  exact <- vars %in% columns
  ci <- match(toupper(vars), toupper(columns))
  ifelse(!exact & !is.na(ci), columns[ci], vars)
}

# Resolve the states argument to _STATE FIPS codes. Accepts integer
# FIPS, two-letter postal abbreviations, and full jurisdiction names,
# mixed freely and matched case-insensitively against brfss_states.
resolve_states <- function(states, call = rlang::caller_env()) {
  if (is.null(states)) {
    return(NULL)
  }
  if (
    length(states) == 0 ||
      anyNA(states) ||
      !(is.numeric(states) || is.character(states))
  ) {
    cli::cli_abort(
      c(
        "{.arg states} must be a vector of state FIPS codes, postal
         abbreviations, or names, e.g. {.code c(48, \"CA\", \"Maine\")}.",
        "x" = "Got {.obj_type_friendly {states}}."
      ),
      class = "brfssdata_bad_states_arg",
      call = call
    )
  }
  if (is.numeric(states)) {
    # is.finite() is the guard that rejects Inf, because Inf == trunc(Inf);
    # without it as.integer(Inf) reached the FIPS lookup as NA and the
    # error named NA rather than what the user typed. check_years_arg()
    # makes the same point with its abs() bound.
    bad <- states[!is.finite(states) | states != trunc(states)]
    if (length(bad) > 0) {
      cli::cli_abort(
        c(
          "Numeric {.arg states} must be whole FIPS codes.",
          "x" = "Got {.val {bad}}."
        ),
        class = "brfssdata_bad_states_arg",
        call = call
      )
    }
    fips <- as.integer(states)
    unknown <- setdiff(fips, brfss_states$fips)
  } else {
    # c(48, "CA", "Maine") reaches here as character: R coerced the 48
    # to "48" before this function ever ran, so digit-only entries are
    # FIPS codes, not names.
    key <- toupper(trimws(states))
    idx <- match(key, toupper(brfss_states$abbr))
    idx <- ifelse(is.na(idx), match(key, toupper(brfss_states$name)), idx)
    numeric_like <- grepl("^[0-9]+$", key)
    idx <- ifelse(
      is.na(idx) & numeric_like,
      match(suppressWarnings(as.integer(key)), brfss_states$fips),
      idx
    )
    unknown <- states[is.na(idx)]
    fips <- brfss_states$fips[idx[!is.na(idx)]]
  }
  if (length(unknown) > 0) {
    shown <- truncate_values(unknown)
    cli::cli_abort(
      c(
        "Unknown state{?s} {.val {shown}}.",
        "i" = "See {.code brfss_states} for the FIPS codes, postal
               abbreviations, and names of every BRFSS jurisdiction."
      ),
      class = "brfssdata_bad_state",
      call = call
    )
  }
  sort(unique(fips))
}

# Query one or more local parquet files, optionally selecting columns.
# union_by_name handles the fact that different survey years carry
# different variable sets: absent columns come back as NA. states, when
# given, is a vector of already-resolved _STATE FIPS codes pushed down
# as a WHERE clause, so filtered rows never reach R.
query_parquet <- function(
  paths,
  vars = NULL,
  states = NULL,
  call = rlang::caller_env()
) {
  con <- duckdb_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  run <- function(sql) {
    tryCatch(
      DBI::dbGetQuery(con, sql),
      error = function(e) abort_corrupt_or_rethrow(e, paths, con, call)
    )
  }

  files_sql <- paste0(
    "[",
    paste(quote_literal(paths), collapse = ", "),
    "]"
  )
  from_sql <- sprintf("read_parquet(%s, union_by_name = true)", files_sql)

  if (!is.null(vars)) {
    schema <- run(sprintf("DESCRIBE SELECT * FROM %s", from_sql))
    vars <- match_vars_ci(vars, schema$column_name)
    unknown <- setdiff(vars, schema$column_name)
    if (length(unknown) > 0) {
      # No catalog here, only the files' real schema; the empty catalog
      # vectors degrade var_not_found_hints() to its did-you-mean tier.
      hints <- var_not_found_hints(
        unknown,
        catalog_vars = character(0),
        catalog_years = integer(0),
        scope_vars = schema$column_name
      )
      shown <- truncate_values(unknown)
      cli::cli_abort(
        c(
          "Variable{?s} {.val {shown}} {?was/were} not found in the
           requested years.",
          rlang::set_names(hints, rep("i", length(hints))),
          "i" = "Use {.fun brfss_vars} to search available variables
                 and the years they appear in."
        ),
        missing_vars = unknown,
        class = "brfssdata_bad_var",
        call = call
      )
    }
    vars <- union(vars, "year")
    select_sql <- paste(quote_ident(vars), collapse = ", ")
  } else {
    select_sql <- "*"
  }

  check_type_consistency(con, paths, files_sql, vars, call = call)

  where_sql <- if (is.null(states)) {
    ""
  } else {
    sprintf(
      ' WHERE "_STATE" IN (%s)',
      paste(as.integer(states), collapse = ", ")
    )
  }
  out <- run(sprintf("SELECT %s FROM %s%s", select_sql, from_sql, where_sql))
  tibble::as_tibble(out)
}

# Refuse to combine files that store a selected column as a string in
# some years and a number in others. union_by_name would promote the
# numeric years to VARCHAR, so the double 1120 becomes "1120.0" in one
# year and "1120" in another -- two distinct values for the same code,
# splitting group_by()/filter() with no warning, and defeating the
# missing-code matcher ("9.0" never matches code 9). The hosted files
# are re-typed to one canonical type per variable at build time
# (data-raw/02_build_parquet.R), so this fires only when stale cached
# files from before that fix are mixed with current ones, or on an
# upstream pipeline regression. Numeric-width promotions (INT32 to
# DOUBLE) are value-preserving and pass. Footer-only, so the check is
# cheap; vars is NULL when every column was requested.
check_type_consistency <- function(con, paths, files_sql, vars, call) {
  if (length(paths) < 2) {
    return(invisible())
  }
  schema <- tryCatch(
    DBI::dbGetQuery(
      con,
      sprintf(
        "SELECT file_name, name, type FROM parquet_schema(%s)
         WHERE type IS NOT NULL",
        files_sql
      )
    ),
    error = function(e) NULL
  )
  if (is.null(schema)) {
    # A file the schema probe cannot read will fail the main query too,
    # where abort_corrupt_or_rethrow() names the culprit properly.
    return(invisible())
  }
  if (!is.null(vars)) {
    schema <- schema[schema$name %in% vars, , drop = FALSE]
  }
  schema$string <- schema$type %in% c("BYTE_ARRAY", "FIXED_LEN_BYTE_ARRAY")
  mixed <- vapply(
    split(schema$string, schema$name),
    function(s) any(s) && !all(s),
    logical(1)
  )
  bad <- names(mixed)[mixed]
  if (length(bad) == 0) {
    return(invisible())
  }
  years <- sort(cached_file_year(basename(paths)))
  years <- years[!is.na(years)]
  detail <- vapply(
    bad,
    function(v) {
      rows <- schema[schema$name == v, , drop = FALSE]
      yr <- cached_file_year(basename(rows$file_name))
      as_text <- sort(yr[rows$string])
      as_num <- sort(yr[!rows$string])
      sprintf(
        "%s: %s as text; %s as numeric",
        v,
        summarize_years(as_text),
        summarize_years(as_num)
      )
    },
    character(1)
  )
  names(detail) <- rep("x", length(detail))
  n_bad <- length(bad)
  cli::cli_abort(
    c(
      "{cli::qty(n_bad)}Column{?s} {.val {bad}} {?is/are} stored with
       different types across the requested years' files.",
      detail,
      "i" = "Combining them would silently corrupt values (a numeric
             year's 1120 becomes {.val 1120.0} next to a text year's
             {.val 1120}).",
      "i" = "This usually means stale cached files are mixed with
             current releases. Run {.code brfss_cache_clear(years =
             c({paste(years, collapse = ', ')}))} and retry; the files
             re-download with checksum verification."
    ),
    class = "brfssdata_type_conflict",
    call = call
  )
}

# A DuckDB failure over local parquet is usually a corrupted cached
# file. Probe each file individually to name the culprit; when none
# reproduces the failure (a genuine query error), rethrow the original
# untouched. Deliberately no auto-delete: an error over a multi-file
# union cannot always be attributed safely, and deleting user cache on a
# guess risks destroying good data.
abort_corrupt_or_rethrow <- function(e, paths, con, call) {
  readable <- vapply(
    paths,
    function(path) {
      tryCatch(
        {
          # The hash aggregate forces a full scan of every column inside
          # DuckDB (count(*) would read only the intact footer metadata
          # and miss corrupted data pages) without materializing the
          # file into R.
          DBI::dbGetQuery(
            con,
            sprintf(
              "SELECT sum(hash(t)) FROM read_parquet(%s) t",
              quote_literal(path)
            )
          )
          TRUE
        },
        error = function(...) FALSE
      )
    },
    logical(1)
  )
  bad <- basename(paths[!readable])
  if (length(bad) == 0) {
    stop(e)
  }
  bad_years <- cached_file_year(bad)
  bad_years <- bad_years[!is.na(bad_years)]
  why <- conditionMessage(e)
  remedy <- if (length(bad_years) > 0) {
    "Run {.code brfss_cache_clear(years = c({paste(bad_years,
     collapse = ', ')}))}; the next read re-downloads with checksum
     verification."
  } else {
    "Remove {.file {bad}} from {.path {brfss_cache_dir()}} and it will
     be re-fetched."
  }
  cli::cli_abort(
    c(
      "Cached file{?s} {.file {bad}} {?is/are} unreadable, likely a
       corrupted or truncated download.",
      "x" = "{why}",
      "i" = remedy
    ),
    class = "brfssdata_corrupt_cache",
    call = call
  )
}
