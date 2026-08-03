# Internal constants and helpers

# First survey year of the combined landline-and-cell-phone (LLCP) design.
# Weighting changed from post-stratification (_FINALWT) to raking (_LLCPWT);
# CDC states estimates are not directly comparable across this boundary.
BREAK_YEAR <- 2011L

DESIGN_PSU <- "_PSU"
DESIGN_STRATA <- "_STSTR"
WEIGHT_PRE <- "_FINALWT"
WEIGHT_POST <- "_LLCPWT"

# Columns that keep their numeric codes on every labeling and
# missing-code path, on both the read and the design routes: a factor
# _STATE would make `_STATE == 6` silently match nothing, and a labeled
# weight or design variable would corrupt the survey design.
LABEL_EXCLUDE <- c(
  "_STATE",
  DESIGN_PSU,
  DESIGN_STRATA,
  WEIGHT_PRE,
  WEIGHT_POST,
  "_LLCPWT2",
  "_CLLCPWT",
  "_WT2RAKE",
  "_STRWT",
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

validate_years <- function(years, download = TRUE, call = rlang::caller_env()) {
  if (
    !is.numeric(years) ||
      length(years) == 0 ||
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
  years <- sort(unique(as.integer(years)))

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

  available <- brfss_years()
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
        "Year{?s} {missing} {?is/are} not available.",
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

# Quote a DuckDB identifier (double quotes, doubled internal quotes).
quote_ident <- function(x) {
  paste0('"', gsub('"', '""', x, fixed = TRUE), '"')
}

# Quote a DuckDB string literal (single quotes, doubled internal quotes).
quote_literal <- function(x) {
  paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
}

duckdb_connect <- function() {
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

# Query one or more local parquet files, optionally selecting columns.
# union_by_name handles the fact that different survey years carry
# different variable sets: absent columns come back as NA.
query_parquet <- function(paths, vars = NULL, call = rlang::caller_env()) {
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
      cli::cli_abort(
        c(
          "Variable{?s} {.val {unknown}} {?was/were} not found in the
           requested years.",
          "i" = "Use {.fun brfss_vars} to search available variables
                 and the years they appear in."
        ),
        class = "brfssdata_bad_var",
        call = call
      )
    }
    vars <- union(vars, "year")
    select_sql <- paste(quote_ident(vars), collapse = ", ")
  } else {
    select_sql <- "*"
  }

  out <- run(sprintf("SELECT %s FROM %s", select_sql, from_sql))
  tibble::as_tibble(out)
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
