# Convert downloaded XPT zips into one zstd parquet per year.
# Run from the package root after 01_download.R.

raw_dir <- "data-raw/raw"
out_dir <- "data-raw/parquet"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# CDC changed these variables' storage type across years (numeric SAS
# variable in some files, character in others). One canonical type per
# variable, applied to every year, so that a multi-year
# read_parquet(union_by_name) never promotes DOUBLE to VARCHAR -- that
# promotion turns the double 1120 into "1120.0" next to a text year's
# "1120", two distinct values for one code, and defeats numeric
# missing-code matching ("9.0" never matches 9). The choice per
# variable follows the semantics: identifiers and codes with leading
# zeros or digit-string structure stay character; plain numeric codes
# stay double.
canonical_types <- c(
  SEQNO = "character", # record identifier; character in 1999 and 2016+
  `_RECORD` = "double", # numeric record code; double in 16 of 17 years
  MRACEORG = "character", # positional multi-race digit string ("15")
  # WINDDOWN must stay character: the 1990 and 1994 files carry stray
  # single-byte values ("]", "W", "\") CDC published as-is, which a
  # double cannot represent without recoding them away.
  WINDDOWN = "character",
  `_MSACODE` = "character", # MSA geographic code; character 1998 on
  RCVFVCH4 = "character" # MMYYYY with leading zeros ("092010")
)

# Coerce a column to its canonical type, refusing any value the
# round-trip could distort: a double becomes character only when every
# value is whole (rendered with sprintf, never scientific, never with a
# trailing ".0"), and a character becomes double only when every
# non-missing value is a plain decimal number.
canonicalize_column <- function(x, type, year, name) {
  if (type == "character" && is.numeric(x)) {
    ok <- is.na(x) | x == trunc(x)
    if (!all(ok)) {
      stop(sprintf(
        "%d: %s carries non-integer values; refusing character cast",
        year,
        name
      ))
    }
    return(ifelse(is.na(x), NA_character_, sprintf("%.0f", x)))
  }
  if (type == "double" && is.character(x)) {
    ok <- is.na(x) | grepl("^-?[0-9]+(\\.[0-9]+)?$", x)
    if (!all(ok)) {
      stop(sprintf(
        "%d: %s carries non-numeric text; refusing double cast",
        year,
        name
      ))
    }
    # A leading zero ("0012") would survive as.numeric() but lose its
    # zeros, silently changing the published representation; such a
    # variable belongs in the character column of canonical_types.
    if (any(grepl("^0[0-9]", x[!is.na(x)]))) {
      stop(sprintf(
        "%d: %s carries leading-zero values; refusing double cast",
        year,
        name
      ))
    }
    return(as.numeric(x))
  }
  x
}

# Known (records, variables) from CDC year pages, asserted when present.
cdc_targets <- list(
  `2013` = c(491773L, 359L),
  `2018` = c(437436L, 275L),
  `2022` = c(445132L, 326L),
  `2023` = c(433323L, 345L),
  `2024` = c(457670L, 345L)
)

# Regression pins for every year: row counts recorded from the published
# releases by site_year_stats.R. These catch a rebuild that silently
# gains or loses rows; cdc_targets above stays the independent
# ground-truth layer from CDC's own pages.
published_counts <- local({
  path <- file.path("vignettes", "articles", "brfss_year_stats.csv")
  if (!file.exists(path)) {
    message("no brfss_year_stats.csv; skipping published-count pins")
    return(list())
  }
  stats <- utils::read.csv(path)
  as.list(stats::setNames(as.integer(stats$respondents), stats$year))
})

build_year <- function(year, overwrite = FALSE) {
  out <- file.path(out_dir, sprintf("brfss_%d.parquet", year))
  if (file.exists(out) && !overwrite) {
    message(year, ": parquet exists")
    return(invisible(out))
  }
  zip <- file.path(raw_dir, sprintf("brfss_%d.zip", year))
  stopifnot(file.exists(zip))

  exdir <- file.path(tempdir(), paste0("brfss_xpt_", year))
  unlink(exdir, recursive = TRUE)
  utils::unzip(zip, exdir = exdir)
  xpt <- list.files(
    exdir,
    pattern = "(?i)\\.xpt[[:space:]]*$",
    full.names = TRUE
  )
  stopifnot(length(xpt) == 1)

  message(year, ": reading XPT")
  dat <- haven::read_xpt(xpt[[1]])
  # Strip haven attributes to plain vectors; labels are captured separately
  # by 03_catalog.R. Keep CDC variable names verbatim.
  dat <- as.data.frame(lapply(dat, haven::zap_label), check.names = FALSE)
  dat <- as.data.frame(
    lapply(dat, function(x) {
      attr(x, "format.sas") <- NULL
      if (is.character(x)) {
        # Legacy files carry Windows-1252 bytes that break UTF-8 parquet.
        x <- iconv(x, "CP1252", "UTF-8", sub = "byte")
        # A blank SAS character field is SAS's missing value for
        # character data; store it as a null, not as "". Done before
        # any canonical cast so a blank never blocks a double cast.
        x[!is.na(x) & trimws(x) == ""] <- NA_character_
      }
      x
    }),
    check.names = FALSE
  )
  for (nm in intersect(names(canonical_types), names(dat))) {
    dat[[nm]] <- canonicalize_column(
      dat[[nm]],
      canonical_types[[nm]],
      year,
      nm
    )
  }
  dat$year <- as.integer(year)

  target <- cdc_targets[[as.character(year)]]
  if (!is.null(target)) {
    # Row counts are the hard validation; CDC page variable counts are
    # unreliable (e.g. 2011 page says 450, the XPT has 454), so column
    # counts are logged, not asserted.
    stopifnot(nrow(dat) == target[1])
    if (ncol(dat) != target[2] + 1L) {
      message(
        year,
        ": note - XPT has ",
        ncol(dat) - 1L,
        " variables vs CDC page claim ",
        target[2]
      )
    }
  }
  published <- published_counts[[as.character(year)]]
  if (!is.null(published)) {
    stopifnot(nrow(dat) == published)
  }

  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  duckdb::duckdb_register(con, "dat", dat)
  DBI::dbExecute(
    con,
    sprintf(
      "COPY dat TO '%s' (FORMAT parquet, COMPRESSION zstd)",
      gsub("'", "''", out)
    )
  )

  unlink(exdir, recursive = TRUE)
  message(sprintf(
    "%d: %s rows, %s cols, %.1f MB parquet",
    year,
    format(nrow(dat), big.mark = ","),
    ncol(dat),
    file.size(out) / 1e6
  ))
  invisible(out)
}

# Usage:
# purrr::walk(2011:2024, build_year)
