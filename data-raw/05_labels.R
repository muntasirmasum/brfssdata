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
  # (?s) so "." spans newlines: without it a multi-line /* */ comment
  # survived whole, and CDC's commented-out VALUE blocks (1998 EDUCA,
  # EMPLOY, INCOME, MARITAL among them) parsed as live definitions.
  # Today the last-definition-wins rule happens to hide that, but a
  # commented block holding a code the live one lacks would ship a
  # phantom label.
  gsub("(?s)/\\*.*?\\*/", " ", text, perl = TRUE) # strip block comments
}

# Split a VALUE block body into its `codes = "label"` entries. The
# labels are found first, as SAS quoted literals in either quote style
# with a doubled quote standing for one literal quote, so that an "="
# or a comma inside label text ("Missing (_BMI2 = 9999)") cannot be
# read as structure. Whatever sits between the previous label and this
# label's "=" is this entry's code list, however it is written.
value_entries <- function(body) {
  literal_re <- "'(?:[^']|'')*'|\"(?:[^\"]|\"\")*\""
  m <- gregexpr(literal_re, body, perl = TRUE)[[1]]
  if (m[[1]] < 0) {
    return(NULL)
  }
  starts <- as.integer(m)
  ends <- starts + attr(m, "match.length") - 1L
  codes <- character(0)
  labels <- character(0)
  from <- 1L
  for (i in seq_along(starts)) {
    lhs <- trimws(substr(body, from, starts[[i]] - 1L))
    from <- ends[[i]] + 1L
    # A literal with no "=" in front of it is not an entry label, so it
    # is skipped rather than guessed at: CDC's older libraries carry
    # stray apostrophes that split one label into two literals.
    if (!endsWith(lhs, "=")) {
      # A skipped literal that itself contains "=" is the dangerous
      # variant of that split: the stray apostrophe paired the label's
      # closing quote with the NEXT entry's opening quote, consuming
      # that entry's assignment as label text, so the entry after the
      # typo vanishes from the catalog. Zero live occurrences in the
      # 1998-2024 corpus; this refuses to let the next one pass
      # silently.
      skipped <- substr(body, starts[[i]] + 1L, ends[[i]] - 1L)
      if (grepl("=", skipped, fixed = TRUE)) {
        warning(
          "value_entries(): skipped a quoted segment containing '=' (",
          substr(skipped, 1L, 60L),
          "); a stray un-doubled apostrophe upstream may have swallowed ",
          "the entry after it.",
          call. = FALSE
        )
      }
      next
    }
    quote <- substr(body, starts[[i]], starts[[i]])
    text <- substr(body, starts[[i]] + 1L, ends[[i]] - 1L)
    codes <- c(codes, trimws(sub("=$", "", lhs)))
    labels <- c(labels, gsub(paste0(quote, quote), quote, text, fixed = TRUE))
  }
  if (length(codes) == 0) {
    return(NULL)
  }
  data.frame(codes = codes, label = labels, stringsAsFactors = FALSE)
}

# What one comma-separated token on the left of a VALUE entry is. Only
# "code" becomes a catalog row. "range" covers everything that is not a
# single integer (a range such as 1-30, 244-<777, or LOW-<0, and the
# LOW/HIGH/OTHER keywords) and marks the whole format ineligible for
# factor conversion, because the format then maps values the catalog
# cannot enumerate. A SAS missing value says nothing either way: R
# stores it as NA whatever its label.
token_kind <- function(x) {
  ifelse(
    grepl("^-?[0-9]+$", x),
    "code",
    ifelse(grepl("^\\.[A-Za-z_]?$", x), "missing", "range")
  )
}

# Parse every PROC FORMAT VALUE block. Returns one row per integer
# code = "label" entry plus a per-format `complete` flag: TRUE when the
# format is a pure integer-to-label map. One entry may name several
# codes ("77,99 = 'UNK/REF'" in the 1998-2001 libraries), and may mix
# codes with ranges ("5,401-411,555 = ..."), so each comma-separated
# token is classified on its own.
parse_value_blocks <- function(path) {
  text <- read_sas_text(path)

  block_re <- "(?is)\\bvalue\\s+(\\$?[A-Za-z_][A-Za-z0-9_.]*)\\s+(.*?);"
  if (!grepl(block_re, text, perl = TRUE)) {
    return(NULL)
  }
  blocks <- regmatches(text, gregexpr(block_re, text, perl = TRUE))[[1]]

  out <- lapply(blocks, function(b) {
    name <- sub(block_re, "\\1", b, perl = TRUE)
    if (startsWith(name, "$")) {
      # Character ($) formats are skipped for now: every year carries a
      # handful of character columns (MRACE 2001-2012, RCSRACE, ...),
      # but cataloging their labels needs character codes, i.e. a
      # catalog schema change (code is INTEGER today). Tracked in
      # data-raw/README.md.
      return(NULL)
    }
    body <- sub(block_re, "\\2", b, perl = TRUE)
    entries <- value_entries(body)
    if (is.null(entries)) {
      return(NULL)
    }
    tokens <- strsplit(entries$codes, ",", fixed = TRUE)
    lab <- rep(entries$label, lengths(tokens))
    tokens <- trimws(unlist(tokens))
    lab <- lab[nzchar(tokens)]
    tokens <- tokens[nzchar(tokens)]
    kind <- token_kind(tokens)
    if (!any(kind == "code")) {
      return(NULL)
    }
    data.frame(
      format = toupper(sub("\\.$", "", name)),
      code = as.integer(tokens[kind == "code"]),
      label = lab[kind == "code"],
      complete = !any(kind == "range"),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, out)
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
    map <- apply_assignment_corrections(map, year)
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

# Corrections to CDC's assignment files, applied before the join, for
# the case where CDC pointed a variable at a format that describes a
# different column. Correcting the assignment rather than the labels
# brings the whole format across, which relabelling row by row cannot:
# the wrong format is usually the shorter one, so the codes it never
# mentions would otherwise stay uncatalogued.
#
# `_AGEG_` 1999 and 2000: assign_1999.sas:123 and assign_2000.sas:100
# write `AGEGFMT.`, whose six codes stop at 65+ and read 7 and 9 as
# UNK/REF. The column holds 1 through 11, which is `_AGEGFMT.`, defined
# in both libraries (labels_1999.sas:1409, labels_2000.sas:1742) and
# assigned correctly from 2001 (assign_2001.sas:98). The data settles
# it: every one of the 1,512 respondents at code 7 in 2000 is aged 18
# to 34, which is what `_AGEGFMT` calls that code, and none carries a
# don't-know age. Under the wrong format `na = TRUE` deleted the age
# group of 2,956 respondents across the two years whose age is known.
assignment_corrections <- data.frame(
  year = c(1999L, 2000L),
  variable = c("_AGEG_", "_AGEG_"),
  format = c("_AGEGFMT", "_AGEGFMT"),
  stringsAsFactors = FALSE
)

apply_assignment_corrections <- function(map, year) {
  want <- assignment_corrections[
    assignment_corrections$year == year, ,
    drop = FALSE
  ]
  if (nrow(want) == 0) {
    return(map)
  }
  hit <- match(toupper(want$variable), toupper(map$variable))
  if (anyNA(hit)) {
    stop(
      "assignment corrections matched no assignment row: ",
      paste(want$variable[is.na(hit)], collapse = "; "),
      " (", year, ")"
    )
  }
  map$format[hit] <- want$format
  message(sprintf(
    "%d: %d format assignment%s corrected",
    year,
    nrow(want),
    if (nrow(want) == 1) "" else "s"
  ))
  map
}

# Corrections to CDC's own format libraries, applied after the join.
# Each row rewrites the label of exactly one (year, variable, code)
# whose format CDC shared with variables it does not describe, and
# names the CDC source that settles the wording. This is not a general
# rewrite layer: apply_label_corrections() stops the build when a row
# matches nothing, so the table cannot quietly go stale, and nothing is
# corrected without a source in the comment above it.
label_corrections <- rbind(
  # 2002 hands the generic UNK2DIG format to 17 variables (assign_2002.sas
  # names them all) and writes its code 88 as "Never smoked regularly"
  # (labels_2002.sas, Value UNK2DIG). That wording belongs to the two
  # smoking items, FIRSTSMK and REGSMK, which keep it here and which
  # labels_2003.sas still writes that way. The count items read 88 as
  # none on both sides of 2002: the 2001 edition of UNK2DIG writes
  # 88 = "NONE" (labels_2001.sas) and assign_2001.sas gives it to the
  # twelve of them that 2001 asked, and labels_2003.sas writes
  # 88 = "None" per variable for CASTHDX, CASTHNOW, DOCTDIAB, DRNK2GE5
  # (VALUE DRNK25GE), FEETCHK, MENTHLTH, PHYSHLTH and POORHLTH, with
  # labels_2004.sas adding DRINKDRI. CASTHDX, CASTHNOW and DRINKDRI are
  # the three with no 2001 label, so 2003 and 2004 settle those.
  data.frame(
    year = 2002L,
    variable = c(
      "AVEDRNK", "CASTHDX", "CASTHNOW", "DOCTDIAB", "DRINKDRI",
      "DRNK2GE5", "FEETCHK", "MENTHLTH", "PAINACT2", "PHYSHLTH",
      "POORHLTH", "QLHLTH2", "QLMENTL2", "QLREST2", "QLSTRES2"
    ),
    code = 88L,
    label = "None",
    stringsAsFactors = FALSE
  ),
  # 1999 writes DISPCODE's disposition category 2 as the bare word
  # "REFUSED", which reads as a refused answer rather than as one of
  # eleven call outcomes, so the missing-code matcher counts a
  # substantive category as missing. CDC's 2000 library (labels_2000.sas,
  # VALUE DISPFMT) numbers the identical eleven-category list and writes
  # this one "02-REFUSED".
  data.frame(
    year = 1999L,
    variable = "DISPCODE",
    code = 2L,
    label = "02-REFUSED",
    stringsAsFactors = FALSE
  ),
  # 2002 is the one year that labels the imputed phone count _IMPNPH
  # with NUMPHONS, the format of the raw question, whose code 7 is
  # "Do not know/Not Sure". An imputed count cannot carry a don't-know
  # answer, and CDC's own VALUE _IMPNPH counts phones at 7: "7" in
  # labels_2001.sas, a rung below "8 or more" in labels_2003.sas and
  # labels_2004.sas.
  data.frame(
    year = 2002L,
    variable = "_IMPNPH",
    code = 7L,
    label = "7",
    stringsAsFactors = FALSE
  )
)

# Variables are matched case-insensitively because the catalog keeps
# each data file's own spelling of the name.
apply_label_corrections <- function(rows) {
  key <- paste(rows$year, toupper(rows$variable), rows$code)
  want <- paste(
    label_corrections$year,
    toupper(label_corrections$variable),
    label_corrections$code
  )
  missed <- want[!want %in% key]
  if (length(missed) > 0) {
    stop(
      "label corrections matched no catalog row: ",
      paste(missed, collapse = "; ")
    )
  }
  hit <- match(key, want)
  rows$label[!is.na(hit)] <- label_corrections$label[hit[!is.na(hit)]]
  message(sprintf(
    "label corrections: %d rows rewritten from %d table entries",
    sum(!is.na(hit)),
    nrow(label_corrections)
  ))
  rows
}

# Build-time guard against the contamination this catalog has already
# shipped: a (variable, code) whose label reads as a missing answer in
# one year and as a substantive one in the year next door. Printed for
# review rather than acted on, because either side can be the wrong one
# (CDC's 2002 UNK2DIG was) and a genuine recode between years does
# happen. Review each entry against the CDC codebooks for both years,
# and correct through label_corrections above.
report_year_flips <- function(rows) {
  pkgload::load_all(quiet = TRUE)
  rows <- rows[
    !duplicated(paste(toupper(rows$variable), rows$code, rows$year)),
    ,
    drop = FALSE
  ]
  rows$missing <- is_missing_label(rows$label)
  flips <- lapply(
    split(rows, paste(toupper(rows$variable), rows$code)),
    function(d) {
      d <- d[order(d$year), , drop = FALSE]
      if (nrow(d) < 2) {
        return(NULL)
      }
      i <- which(diff(d$year) == 1L & d$missing[-1] != d$missing[-nrow(d)])
      if (length(i) == 0) {
        return(NULL)
      }
      data.frame(
        variable = d$variable[i],
        code = d$code[i],
        year = d$year[i],
        label = d$label[i],
        next_label = d$label[i + 1],
        stringsAsFactors = FALSE
      )
    }
  )
  flips <- do.call(rbind, flips)
  n <- if (is.null(flips)) 0L else nrow(flips)
  message(sprintf(
    "missing-status year flips: %d (variable, code, year) rows whose %s",
    n,
    "label flips missing/substantive in the next year; review each:"
  ))
  if (n > 0) {
    flips <- flips[order(flips$variable, flips$code, flips$year), ]
    print(flips, row.names = FALSE)
  }
  invisible(flips)
}

build_labels <- function(years) {
  rows <- do.call(rbind, lapply(years, labels_year))
  rows <- apply_label_corrections(rows)
  report_year_flips(rows)
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
