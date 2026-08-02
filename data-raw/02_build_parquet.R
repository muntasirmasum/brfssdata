# Convert downloaded XPT zips into one zstd parquet per year.
# Run from the package root after 01_download.R.

raw_dir <- "data-raw/raw"
out_dir <- "data-raw/parquet"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Known (records, variables) from CDC year pages, asserted when present.
cdc_targets <- list(
  `2013` = c(491773L, 359L),
  `2018` = c(437436L, 275L),
  `2022` = c(445132L, 326L),
  `2023` = c(433323L, 345L),
  `2024` = c(457670L, 345L)
)

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
      }
      x
    }),
    check.names = FALSE
  )
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
