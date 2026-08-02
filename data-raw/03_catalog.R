# Build the variable catalog (variable, label, year) from downloaded XPT
# files. haven preserves SAS variable labels, which the parquet files
# deliberately drop; this catalog is what brfss_vars() searches.
# Run from the package root after 01_download.R.

raw_dir <- "data-raw/raw"
out_dir <- "data-raw/parquet"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

catalog_year <- function(year) {
  zip <- file.path(raw_dir, sprintf("brfss_%d.zip", year))
  stopifnot(file.exists(zip))
  exdir <- file.path(tempdir(), paste0("brfss_cat_", year))
  unlink(exdir, recursive = TRUE)
  utils::unzip(zip, exdir = exdir)
  on.exit(unlink(exdir, recursive = TRUE), add = TRUE)
  xpt <- list.files(
    exdir,
    pattern = "(?i)\\.xpt[[:space:]]*$",
    full.names = TRUE
  )
  stopifnot(length(xpt) == 1)

  dat <- haven::read_xpt(xpt[[1]], n_max = 1)
  labels <- vapply(
    dat,
    function(x) attr(x, "label") %||% NA_character_,
    character(1)
  )
  # SAS labels in older files are Windows-1252; parquet requires UTF-8.
  labels <- iconv(labels, "CP1252", "UTF-8", sub = "byte")
  data.frame(
    variable = names(dat),
    label = unname(labels),
    year = as.integer(year),
    check.names = FALSE
  )
}

`%||%` <- function(x, y) if (is.null(x)) y else x

build_catalog <- function(years) {
  catalog <- do.call(rbind, lapply(years, catalog_year))
  out <- file.path(out_dir, "brfss_variables.parquet")
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  duckdb::duckdb_register(con, "catalog", catalog)
  DBI::dbExecute(
    con,
    sprintf(
      "COPY catalog TO '%s' (FORMAT parquet, COMPRESSION zstd)",
      gsub("'", "''", out)
    )
  )
  message(sprintf(
    "catalog: %s variable-year rows across %d years",
    format(nrow(catalog), big.mark = ","),
    length(years)
  ))
  invisible(out)
}

# Usage:
# build_catalog(2011:2024)
