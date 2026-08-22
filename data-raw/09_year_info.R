# Build brfss_year_info.parquet, the year inventory behind
# brfss_year_info(): respondents, variables, reporting jurisdictions,
# hosted file size, the CDC documentation page per year, and the
# upstream source identity (CDC file name, format, sha256 as
# downloaded, download date) joined from data-raw/provenance.csv. Run
# from the package root AFTER the parquet files are final for the
# release (the size column must describe the bytes actually published)
# and after 01b_provenance.R has recorded every year's source, then
# publish with the other data-meta assets via 04_upload.R.

out_dir <- "data-raw/parquet"
paths <- list.files(
  out_dir,
  pattern = "^brfss_[0-9]{4}\\.parquet$",
  full.names = TRUE
)
stopifnot(length(paths) > 0)

con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

# URL rules per the datasets article: .html from 2012 on, .htm through
# 2011, CDC's web archive for 1984-1988.
codebook_url <- function(year) {
  ifelse(
    year >= 2012,
    sprintf("https://www.cdc.gov/brfss/annual_data/annual_%d.html", year),
    ifelse(
      year >= 1989,
      sprintf("https://www.cdc.gov/brfss/annual_data/annual_%d.htm", year),
      sprintf(
        "https://archive.cdc.gov/www_cdc_gov/brfss/annual_data/annual_%d.htm",
        year
      )
    )
  )
}

rows <- lapply(paths, function(path) {
  year <- as.integer(sub("^brfss_([0-9]{4})\\.parquet$", "\\1", basename(path)))
  q <- DBI::dbGetQuery(
    con,
    sprintf(
      'SELECT count(*) AS respondents,
              count(DISTINCT "_STATE") AS states
       FROM read_parquet(%s)',
      paste0("'", gsub("'", "''", path), "'")
    )
  )
  n_vars <- nrow(DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT name FROM parquet_schema('%s') WHERE type IS NOT NULL",
      gsub("'", "''", path)
    )
  ))
  data.frame(
    year = year,
    respondents = as.integer(q$respondents),
    # minus the added year column: report CDC's variables, not ours
    variables = n_vars - 1L,
    states = as.integer(q$states),
    size = as.numeric(file.size(path)),
    codebook_url = codebook_url(year)
  )
})
info <- do.call(rbind, rows)
info <- info[order(info$year), ]

# The source identity per year. Hard requirement: an inventory row
# without provenance would ship NA source columns for a year we in fact
# built from a recorded zip, so a gap here means 01b_provenance.R has
# not been run since that year's zip arrived.
prov <- utils::read.csv("data-raw/provenance.csv", colClasses = "character")
prov$year <- as.integer(prov$year)
absent <- setdiff(info$year, prov$year)
if (length(absent) > 0) {
  stop(
    "no provenance recorded for year(s) ",
    paste(absent, collapse = ", "),
    "; run data-raw/01b_provenance.R first",
    call. = FALSE
  )
}
at <- match(info$year, prov$year)
info$source_file <- prov$source_file[at]
info$source_format <- "SAS Transport (XPT), zip-compressed"
info$source_sha256 <- prov$source_sha256[at]
info$downloaded <- as.Date(prov$downloaded[at])

duckdb::duckdb_register(con, "info", info)
DBI::dbExecute(
  con,
  sprintf(
    "COPY (SELECT * FROM info ORDER BY year)
     TO '%s' (FORMAT parquet, COMPRESSION zstd)",
    file.path(out_dir, "brfss_year_info.parquet")
  )
)
message("wrote ", file.path(out_dir, "brfss_year_info.parquet"), ": ", nrow(info), " years")
