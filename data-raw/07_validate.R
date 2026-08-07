# Validate the built parquet files before anything is published.
# Run from the package root after 02_build_parquet.R (and after
# 05_labels.R when the label catalog changed). Stops on the first
# violated invariant; the missing-label audit at the end is a printed
# review list, not an assertion.

out_dir <- "data-raw/parquet"
paths <- list.files(out_dir, pattern = "^brfss_[0-9]{4}\\.parquet$", full.names = TRUE)
stopifnot(length(paths) > 0)

con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

files_sql <- paste0(
  "[",
  paste(sprintf("'%s'", gsub("'", "''", paths)), collapse = ", "),
  "]"
)

# --- 1. One stored type per variable across every year --------------------
# The exact invariant check_type_consistency() enforces at read time;
# violated here means canonical_types in 02_build_parquet.R needs a new
# entry (CDC changed a variable's type again).
schema <- DBI::dbGetQuery(
  con,
  sprintf(
    "SELECT file_name, name,
            type IN ('BYTE_ARRAY', 'FIXED_LEN_BYTE_ARRAY') AS is_string
     FROM parquet_schema(%s) WHERE type IS NOT NULL",
    files_sql
  )
)
mixed <- vapply(
  split(schema$is_string, schema$name),
  function(s) any(s) && !all(s),
  logical(1)
)
if (any(mixed)) {
  bad <- names(mixed)[mixed]
  detail <- vapply(bad, function(v) {
    rows <- schema[schema$name == v, , drop = FALSE]
    yr <- as.integer(sub("^brfss_([0-9]{4})\\.parquet$", "\\1", basename(rows$file_name)))
    sprintf(
      "%s: text in %s; numeric in %s",
      v,
      paste(sort(yr[rows$is_string]), collapse = ", "),
      paste(sort(yr[!rows$is_string]), collapse = ", ")
    )
  }, character(1))
  stop(
    "cross-year type conflict; add to canonical_types in 02_build_parquet.R:\n",
    paste(detail, collapse = "\n")
  )
}
message("type consistency: OK (", length(unique(schema$name)), " variables)")

# --- 2. No blank strings anywhere ------------------------------------------
# Blanks are SAS missing values and must have been stored as nulls.
for (path in paths) {
  cols <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT name FROM parquet_schema('%s')
       WHERE type IN ('BYTE_ARRAY', 'FIXED_LEN_BYTE_ARRAY')",
      gsub("'", "''", path)
    )
  )$name
  if (length(cols) == 0) {
    next
  }
  checks <- paste(
    sprintf(
      'count(*) FILTER (WHERE trim("%s") = \'\') AS "%s"',
      cols,
      cols
    ),
    collapse = ", "
  )
  blanks <- DBI::dbGetQuery(
    con,
    sprintf("SELECT %s FROM read_parquet('%s')", checks, gsub("'", "''", path))
  )
  bad <- names(blanks)[as.numeric(blanks[1, ]) > 0]
  if (length(bad) > 0) {
    stop(basename(path), ": blank strings remain in ", paste(bad, collapse = ", "))
  }
}
message("blank strings: none")

# --- 3. Row counts identical to the published pins -------------------------
stats_path <- file.path("vignettes", "articles", "brfss_year_stats.csv")
stopifnot(file.exists(stats_path))
pins <- utils::read.csv(stats_path)
counts <- DBI::dbGetQuery(
  con,
  sprintf(
    "SELECT year, count(*) AS n FROM read_parquet(%s, union_by_name = true)
     GROUP BY year ORDER BY year",
    files_sql
  )
)
merged <- merge(pins[c("year", "respondents")], counts, by = "year", all = TRUE)
off <- merged[is.na(merged$respondents) | is.na(merged$n) | merged$respondents != merged$n, ]
if (nrow(off) > 0) {
  print(off)
  stop("row counts differ from vignettes/articles/brfss_year_stats.csv pins")
}
message("row pins: OK (", nrow(merged), " years)")

# --- 4. Missing-label audit (review list, not an assertion) -----------------
# Labels that look missing-adjacent but that is_missing_label() does not
# flag. Review with each new survey year: a genuine new missing-bucket
# wording belongs in the matcher rules or MISSING_LABEL_ALLOWLIST
# (R/missing_codes.R); a substantive label (exclusion flags, "UNKNOWN"
# judgment calls, "Doctor refused when asked") stays here on purpose.
labels_path <- file.path(out_dir, "brfss_labels.parquet")
if (file.exists(labels_path)) {
  pkgload::load_all(quiet = TRUE)
  catalog <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT DISTINCT label FROM read_parquet('%s')
       WHERE regexp_matches(lower(label), 'miss|refus|know|not sure|blank|not asked|unknown')",
      gsub("'", "''", labels_path)
    )
  )
  unmatched <- catalog$label[!is_missing_label(catalog$label)]
  message(
    "missing-label audit: ",
    length(unmatched),
    " candidate label(s) not flagged as missing; review with each new year:"
  )
  print(sort(unmatched))
} else {
  message("no label catalog built; skipping the missing-label audit")
}
