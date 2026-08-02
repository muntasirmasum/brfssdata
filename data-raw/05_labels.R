# Build the value-label catalog (year, variable, code, label, complete)
# from CDC's SAS format libraries plus the Formas assignment files, staged
# in data-raw/raw/labels/ by the Chrome download step as:
#   labels_YYYY.sas  PROC FORMAT VALUE blocks (1990-2024 attempted)
#   assign_YYYY.sas  FORMAT variable-to-format assignments (1999-2024)
#
# Coverage reality: CDC no longer hosts label sources for 1985-1997
# (only generic stubs before 1998), and no assignment file exists for
# 1998, so 1998 falls back to exact name matching (VALUE blocks in the
# modern era are named after their variables). Net: labels ship for
# 1998-2024; 1985-1997 are documented as label-less.
#
# Run from the package root after data zips exist in data-raw/raw/.

raw_dir <- "data-raw/raw"
labels_dir <- "data-raw/raw/labels"
out_dir <- "data-raw/parquet"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

read_sas_text <- function(path) {
  text <- readLines(path, warn = FALSE)
  text <- iconv(text, "CP1252", "UTF-8", sub = "byte")
  text <- paste(text, collapse = "\n")
  gsub("/\\*.*?\\*/", " ", text, perl = TRUE) # strip block comments
}

# Parse every PROC FORMAT VALUE block. Returns one row per integer
# code = "label" entry plus a per-format `complete` flag: TRUE when the
# format is a pure integer-to-label map. Entries for SAS missing codes
# (".", ".A", ...) are dropped without affecting completeness (they map
# to NA in R anyway); ranges (1-30) and LOW/HIGH/OTHER mark the format
# incomplete because factor conversion would be unsafe.
parse_value_blocks <- function(path) {
  text <- read_sas_text(path)

  block_re <- "(?is)\\bvalue\\s+(\\$?[A-Za-z_][A-Za-z0-9_.]*)\\s+(.*?);"
  if (!grepl(block_re, text, perl = TRUE)) {
    return(NULL)
  }
  blocks <- regmatches(text, gregexpr(block_re, text, perl = TRUE))[[1]]

  entry_re <- paste0(
    "([A-Za-z0-9_.'\"-]+(?:\\s*-\\s*[A-Za-z0-9_.]+)?)",
    "\\s*=\\s*",
    "(\"[^\"]*\"|'[^']*')"
  )

  out <- lapply(blocks, function(b) {
    name <- sub(block_re, "\\1", b, perl = TRUE)
    if (startsWith(name, "$")) {
      return(NULL) # character formats: BRFSS data are numeric
    }
    body <- sub(block_re, "\\2", b, perl = TRUE)
    m <- regmatches(body, gregexpr(entry_re, body, perl = TRUE))[[1]]
    if (length(m) == 0) {
      return(NULL)
    }
    lhs <- trimws(sub(paste0(entry_re, ".*"), "\\1", m, perl = TRUE))
    lab <- sub(paste0(".*?=\\s*(\"[^\"]*\"|'[^']*')"), "\\1", m, perl = TRUE)
    lab <- substr(lab, 2, nchar(lab) - 1)

    is_int <- grepl("^-?[0-9]+$", lhs)
    is_missing <- grepl("^\\.[A-Za-z_]?$", lhs)
    complete <- all(is_int | is_missing)
    data.frame(
      format = toupper(sub("\\.$", "", name)),
      code = suppressWarnings(as.integer(lhs)),
      label = lab,
      complete = complete,
      keep = is_int,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, out)
  out <- out[out$keep, c("format", "code", "label", "complete")]
  # A format defined twice keeps its last definition (SAS semantics).
  out[!duplicated(out[c("format", "code")], fromLast = TRUE), ]
}

# Parse a Formas assignment file: FORMAT statements pairing variables
# with the format applied to them (a token ending in "."). Several
# variables may precede one format token.
parse_format_assignments <- function(path) {
  text <- read_sas_text(path)
  text <- gsub("(?i)\\bformat\\b", " ", text, perl = TRUE)
  tokens <- strsplit(gsub(";", " ", text), "\\s+")[[1]]
  tokens <- tokens[nzchar(tokens)]

  vars <- character(0)
  pending <- character(0)
  fmts <- character(0)
  for (tok in tokens) {
    if (grepl("^\\$?[A-Za-z_][A-Za-z0-9_]*\\.$", tok)) {
      fmt <- toupper(sub("\\.$", "", tok))
      if (length(pending) > 0) {
        vars <- c(vars, pending)
        fmts <- c(fmts, rep(fmt, length(pending)))
      }
      pending <- character(0)
    } else if (grepl("^[A-Za-z_][A-Za-z0-9_]*$", tok)) {
      pending <- c(pending, tok)
    } else {
      pending <- character(0) # anything else breaks the run
    }
  }
  if (length(vars) == 0) {
    return(NULL)
  }
  data.frame(
    variable = toupper(vars),
    format = fmts,
    stringsAsFactors = FALSE
  )
}

# Variable names actually present in a year's data file.
year_variables <- function(year) {
  zip <- file.path(raw_dir, sprintf("brfss_%d.zip", year))
  stopifnot(file.exists(zip))
  exdir <- file.path(tempdir(), paste0("brfss_lbl_", year))
  unlink(exdir, recursive = TRUE)
  utils::unzip(zip, exdir = exdir)
  on.exit(unlink(exdir, recursive = TRUE), add = TRUE)
  xpt <- list.files(
    exdir,
    pattern = "(?i)\\.xpt[[:space:]]*$",
    full.names = TRUE
  )
  stopifnot(length(xpt) == 1)
  names(haven::read_xpt(xpt[[1]], n_max = 1))
}

labels_year <- function(year) {
  src <- file.path(labels_dir, sprintf("labels_%d.sas", year))
  if (!file.exists(src)) {
    message(year, ": no label source; skipping")
    return(NULL)
  }
  formats <- parse_value_blocks(src)
  if (is.null(formats) || nrow(formats) == 0) {
    message(year, ": no VALUE blocks parsed; skipping")
    return(NULL)
  }

  vars <- year_variables(year)
  assign_path <- file.path(labels_dir, sprintf("assign_%d.sas", year))
  if (file.exists(assign_path)) {
    map <- parse_format_assignments(assign_path)
    map <- map[map$variable %in% toupper(vars), , drop = FALSE]
    source <- "assignments"
  } else {
    # Fallback: modern VALUE blocks are named after their variables.
    map <- data.frame(
      variable = toupper(vars)[toupper(vars) %in% unique(formats$format)],
      stringsAsFactors = FALSE
    )
    map$format <- map$variable
    source <- "name matching"
  }

  # Restore the data file's own case for the variable column.
  case_map <- stats::setNames(vars, toupper(vars))
  joined <- merge(map, formats, by = "format")
  if (nrow(joined) == 0) {
    message(year, ": no variables matched; skipping")
    return(NULL)
  }
  joined$variable <- unname(case_map[joined$variable])

  message(sprintf(
    "%d: %d formats, %d/%d variables labeled via %s, %s rows",
    year,
    length(unique(formats$format)),
    length(unique(joined$variable)),
    length(vars),
    source,
    format(nrow(joined), big.mark = ",")
  ))
  data.frame(
    year = as.integer(year),
    variable = joined$variable,
    code = joined$code,
    label = joined$label,
    complete = joined$complete,
    stringsAsFactors = FALSE
  )
}

build_labels <- function(years) {
  rows <- do.call(rbind, lapply(years, labels_year))
  out <- file.path(out_dir, "brfss_labels.parquet")
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  duckdb::duckdb_register(con, "labels", rows)
  DBI::dbExecute(
    con,
    sprintf(
      "COPY labels TO '%s' (FORMAT parquet, COMPRESSION zstd)",
      gsub("'", "''", out)
    )
  )
  message(sprintf(
    "labels catalog: %s rows across %d years",
    format(nrow(rows), big.mark = ","),
    length(unique(rows$year))
  ))
  invisible(out)
}

# Usage:
# build_labels(1998:2024)
