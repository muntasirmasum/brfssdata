# Internal constants and helpers

# First survey year of the combined landline-and-cell-phone (LLCP) design.
# Weighting changed from post-stratification (_FINALWT) to raking (_LLCPWT);
# CDC states estimates are not directly comparable across this boundary.
BREAK_YEAR <- 2011L

DESIGN_PSU <- "_PSU"
DESIGN_STRATA <- "_STSTR"
WEIGHT_PRE <- "_FINALWT"
WEIGHT_POST <- "_LLCPWT"

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
      any(years != trunc(years))
  ) {
    cli::cli_abort(
      "{.arg years} must be one or more whole survey years, e.g. {.code 2019:2023}.",
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
        "i" = "Published years: {min(available)}-{max(available)}
               ({length(available)} year{?s})."
      ),
      class = "brfssdata_bad_year",
      call = call
    )
  }
  years
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

# Query one or more local parquet files, optionally selecting columns.
# union_by_name handles the fact that different survey years carry
# different variable sets: absent columns come back as NA.
query_parquet <- function(paths, vars = NULL, call = rlang::caller_env()) {
  con <- duckdb_connect()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  files_sql <- paste0(
    "[",
    paste(quote_literal(paths), collapse = ", "),
    "]"
  )
  from_sql <- sprintf("read_parquet(%s, union_by_name = true)", files_sql)

  if (!is.null(vars)) {
    schema <- DBI::dbGetQuery(
      con,
      sprintf("DESCRIBE SELECT * FROM %s", from_sql)
    )
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

  out <- DBI::dbGetQuery(
    con,
    sprintf("SELECT %s FROM %s", select_sql, from_sql)
  )
  tibble::as_tibble(out)
}
