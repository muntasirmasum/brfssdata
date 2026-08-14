#' Codes CDC uses for missing-type answers
#'
#' @description
#' Returns the rows of the value-label catalog whose label marks a
#' missing-type answer: don't know / not sure, refused, or a
#' not-asked/missing placeholder. These are exactly the codes that
#' `na = TRUE` in [read_brfss()] and [brfss_design()] sets to `NA`, so
#' this function is the audit trail for that behavior, and the join
#' table for recoding by hand.
#'
#' Matching is deliberately conservative. A label counts as missing when
#' every part of it (split on `/`, `,`, and the word "or") is a known
#' missing-answer phrase, or when the only parts beyond those phrases
#' start with the word "missing" and at least one part names the answer
#' itself (don't know / not sure / refused), the shape of CDC's
#' calculated-variable buckets such as "Don't know, refused or missing
#' values" on `_FRTLT1A`. The abbreviations CDC's 1998 to 2001 format
#' libraries use ("UNK/REF", "UNK", "REF", "UNKNOWN") count as those
#' phrases, as do the bare "N/A" and "N/A,REF" placeholders from the
#' same years. A short audited allowlist covers CDC's
#' "component question" wordings on the `RACE2` family. Substantive
#' answers that merely contain one of the words, such as "Doctor refused
#' when asked" or a bare "Missing Fruit Responses" exclusion flag, never
#' match. Code 88/888 ("None") is an answer of zero, not missing, and is
#' never matched; recode it to 0 yourself before averaging a count
#' variable such as `PHYSHLTH`.
#'
#' @inheritParams brfss_labels
#'
#' @return A tibble with columns `year`, `variable`, `code`, and
#'   `label`, one row per code the missing-value rules match. Labels
#'   cover 1998 on, so earlier years never appear.
#'
#' @examples
#' brfss_missing_codes("GENHLTH", years = 2023, download = FALSE)
#' @seealso [brfss_labels()] for the full catalog.
#' @export
brfss_missing_codes <- function(
  vars = NULL,
  years = NULL,
  download = TRUE,
  quiet = TRUE
) {
  # Validated here, not just in the delegation, so a malformed vars or
  # years error names this function rather than brfss_labels().
  if (!is.null(vars) && (!is.character(vars) || anyNA(vars))) {
    cli::cli_abort(
      c(
        "{.arg vars} must be a character vector of variable names.",
        vars_arg_year_hint(vars, "brfss_missing_codes")
      ),
      class = "brfssdata_bad_vars_arg"
    )
  }
  if (!is.null(years)) {
    years <- check_years_arg(years)
  }
  catalog <- brfss_labels(
    vars = vars,
    years = years,
    download = download,
    quiet = quiet
  )
  out <- catalog[
    is_missing_label(catalog$label),
    c("year", "variable", "code", "label"),
    drop = FALSE
  ]
  tibble::as_tibble(out)
}

# Normalize a label for missing-code matching: lower case, apostrophe
# variants stripped (CDC files carry straight, curly, and acute
# apostrophes, plus the A-circumflex mojibake from double-encoded
# CP1252), and whitespace collapsed.
normalize_label <- function(x) {
  x <- tolower(x)
  # \u00c2 is the mojibake byte; tolower() has already turned it into
  # \u00e2, so both forms are stripped.
  x <- gsub("[\u00c2\u00e2]", "", x)
  x <- gsub("[\u2019\u00b4'`]", "", x)
  x <- gsub("[[:space:]]+", " ", x)
  trimws(x)
}

# The phrase whitelist, after normalize_label(). Every token of a label
# must be here for the label to count as missing.
MISSING_LABEL_TOKENS <- c(
  "dont know",
  "do not know",
  "dk",
  "not sure",
  "ns",
  "refused",
  # CDC's 1998-2001 format libraries abbreviate the same answers:
  # "UNK/REF" on 351 variables, plus bare "UNK", "REF", and "UNKNOWN".
  "unk",
  "ref",
  "unknown",
  "missing",
  "blank",
  "not asked"
)

# Tokens that name the respondent-side missing answer itself. Rule B
# below requires at least one, so a label made only of "missing ..."
# flags (the _FRUITEX-style exclusion indicators) never matches on its
# own.
MISSING_CORE_TOKENS <- c(
  "dont know",
  "do not know",
  "dk",
  "not sure",
  "ns",
  "refused",
  "unk",
  "ref",
  "unknown"
)

# Exact normalized labels that are genuine don't-know/refused buckets
# but fit neither token rule: CDC's "component question" footnotes on
# RACE2, _RACEG2, and _RACEGR2 code 9 (2002-2004 era), and the 1998-2001
# "N/A" placeholder, whose slash the token split would otherwise cut in
# half. Audited by hand against the CDC codebooks before being added.
#
# The "N/A" entries are deliberately exact rather than a token: they name
# code 8 on 100 yes/no variables (1998, 1999, 2001) and code 9 on the
# 2000 calculated risk factors _RFDRDRI, _RFSMOK2, and _RFTOBAC, all of
# them CDC's not-asked placeholder. A general "not applicable" token
# would instead reach spelled-out answer categories that are ordinal
# scale positions, such as GETHIV code 5 next to "NONE", so it is not
# one.
MISSING_LABEL_ALLOWLIST <- c(
  "do not know/not sure/refused component question",
  "do not know/not sure/refused missing component question",
  "n/a",
  "n/a,ref"
)

# A label marks a missing-type answer iff one of:
#
# Rule A: it has at least one "/"-, ","-, or " or "-separated token and
# every token is on the whitelist. Whole-token matching keeps
# substantive answers safe: "Doctor refused when asked", "No, I've
# refused treatment", and "zero or missing" all carry a token outside
# the whitelist and never match.
#
# Rule B: CDC's calculated-variable formats append a trailing noun to
# the missing bucket ("Don't know, refused or missing values",
# "... or missing insurance response", "... Missing (_BMI2 = 9999)").
# A token starting with the word "missing" is accepted when every other
# token is whitelisted AND at least one token names the answer itself
# (MISSING_CORE_TOKENS), so a bare "Missing Fruit Responses" exclusion
# flag never matches on its own.
#
# Allowlist: the exact normalized label is one of the audited
# MISSING_LABEL_ALLOWLIST strings.
#
# The rule extension was validated against all 2,502 distinct catalog
# labels (1998-2024): relative to Rule A alone it adds exactly 9 label
# strings covering 18 variable/code combinations (all code 9: _BMI2CAT,
# _FRTLT1, _FRTLT1A, _VEGLT1, _VEGLT1A, _HLTHPLN, _HLTHPL1, _HLTHPL2,
# _LMTACT1-3, _LMTSCL1, _LMTWRK1-3, RACE2, _RACEG2, _RACEGR2) and
# removes none.
#
# The 1998-2001 abbreviations were validated the same way against the
# shipped catalog: "unk", "ref", and "unknown" plus the two "n/a"
# allowlist entries match 786 more rows (651 "UNK/REF", 108 "N/A", 13
# "UNKNOWN", 9 "REF", 3 "N/A,REF", 2 "UNK") over 370 variables, all of
# them in 1998-2001, and cost none. Spelled-out "not applicable" is
# deliberately not a token: it names ordinal scale positions in later
# years, such as GETHIV code 5 sitting beside "NONE".
is_missing_label <- function(labels) {
  normalized <- normalize_label(labels)
  out <- vapply(
    strsplit(normalized, "\\s*(/|,|\\bor\\b)\\s*"),
    function(tokens) {
      tokens <- trimws(tokens)
      tokens <- tokens[!is.na(tokens) & nzchar(tokens)]
      if (length(tokens) == 0) {
        return(FALSE)
      }
      known <- tokens %in% MISSING_LABEL_TOKENS
      if (all(known)) {
        return(TRUE)
      }
      all(known | grepl("^missing\\b", tokens)) &&
        any(tokens %in% MISSING_CORE_TOKENS)
    },
    logical(1)
  )
  out <- out | (!is.na(normalized) & normalized %in% MISSING_LABEL_ALLOWLIST)
  out[is.na(labels)] <- FALSE
  out
}

# Set catalog-identified missing-type codes to NA. Applied per year: a
# code is cleared only in rows of years where its label matched, so a
# code that means something substantive in one year and "refused" in
# another is handled year by year. Values the catalog does not cover
# (including everything before 1998) pass through untouched.
apply_missing_codes <- function(
  dat,
  years,
  quiet = TRUE,
  download = TRUE,
  exclude = character(0),
  call = rlang::caller_env()
) {
  catalog <- labels_catalog(download = download, quiet = quiet, call = call)
  # Captured before the missing-label filter: coverage is about whether
  # the catalog knows a year and its variables at all, not about how
  # many of its labels are missing-type.
  catalog_years <- unique(catalog$year)
  covered_years <- intersect(years, catalog_years)
  # Requested years only from here on: the label matcher below is the
  # expensive step, and rows outside `years` can never contribute to
  # either the coverage map or the recode.
  catalog <- catalog[catalog$year %in% years, , drop = FALSE]
  covered_vars_by_year <- lapply(covered_years, function(y) {
    unique(catalog$variable[catalog$year == y])
  })
  names(covered_vars_by_year) <- as.character(covered_years)
  catalog <- catalog[is_missing_label(catalog$label), , drop = FALSE]

  vars <- setdiff(intersect(unique(catalog$variable), names(dat)), exclude)
  cleared <- 0L
  touched <- character(0)
  for (v in vars) {
    sub <- catalog[catalog$variable == v, , drop = FALSE]
    # Matched with %in% per year, never through paste()/as.character():
    # a double 100000 renders as "1e+05" while the integer catalog code
    # renders as "100000", so string matching would silently skip any
    # round code at or above 1e5.
    hit <- rep(FALSE, nrow(dat))
    for (y in unique(sub$year)) {
      codes <- sub$code[sub$year == y]
      hit <- hit | (dat$year == y & !is.na(dat[[v]]) & dat[[v]] %in% codes)
    }
    if (any(hit)) {
      dat[[v]][hit] <- NA
      cleared <- cleared + sum(hit)
      touched <- c(touched, v)
    }
  }
  if (cleared > 0 && !quiet) {
    cli::cli_inform(
      c(
        "i" = "Set {cleared} response{?s} across {length(touched)}
               variable{?s} to NA (don't know / refused / missing codes).",
        "i" = "See {.fun brfss_missing_codes} for the affected codes;
               disable with {.code na = FALSE}."
      ),
      class = "brfssdata_na_note"
    )
  }
  # The coverage signals are analytical, not progress output, so they
  # are deliberately not gated on quiet; silence them by class.
  note_na_coverage(dat, years, catalog_years, covered_vars_by_year, exclude)
  dat
}

# na = TRUE is only as good as the catalog behind it. The catalog has no
# entries before 1998, and 1998 itself covers under a quarter of that
# file's variables, so a request touching those years would otherwise be
# a silent no-op: the user asked for missing codes to be cleared and
# nothing says they were not. Computed over the columns actually loaded,
# so a selection of fully covered variables stays quiet.
note_na_coverage <- function(
  dat,
  years,
  catalog_years,
  covered_vars_by_year,
  exclude
) {
  data_cols <- setdiff(names(dat), union(exclude, "year"))
  # With no eligible column loaded (a design-variables-only read), the
  # catalog's coverage is moot: na = TRUE could not have touched
  # anything either way, so there is nothing to announce.
  if (length(data_cols) == 0) {
    return(invisible())
  }
  uncovered <- setdiff(years, catalog_years)
  partial <- character(0)
  if (length(data_cols) > 0) {
    for (y in intersect(years, catalog_years)) {
      n_covered <- sum(data_cols %in% covered_vars_by_year[[as.character(y)]])
      # Below half is a coverage cliff worth a note (1998 sits at ~23%
      # over a full file); modern years land well above 0.8 and stay
      # quiet.
      if (n_covered / length(data_cols) < 0.5) {
        partial <- c(
          partial,
          sprintf("%d (%d of %d)", y, n_covered, length(data_cols))
        )
      }
    }
  }
  if (length(uncovered) == 0 && length(partial) == 0) {
    return(invisible())
  }
  uncovered_txt <- summarize_years(uncovered)
  partial_txt <- paste(partial, collapse = "; ")
  n_uncovered <- length(uncovered)
  n_partial <- length(partial)
  # Two severities: no catalog at all means na = TRUE was a complete
  # no-op for those years, which is warning-grade (a 1993 PHYSHLTH mean
  # with 77/99 left in is off by a third); partial coverage still
  # cleared something and stays a note. Both arms can co-fire (a
  # 1993 + 1998 request) and each is self-contained, because either
  # class can be suppressed independently.
  if (n_uncovered > 0) {
    cli::cli_warn(
      c(
        "{.code na = TRUE} had no value-label catalog to consult for
         {cli::qty(n_uncovered)}year{?s} {uncovered_txt}; codes there
         pass through unchanged (labels cover 1998 on).",
        "x" = "Estimates over those years still contain CDC's don't
               know and refused codes (77/99 and kin).",
        "i" = "See {.fun brfss_labels} for coverage and
               {.fun brfss_missing_codes} for what was cleared."
      ),
      class = "brfssdata_na_coverage_warning"
    )
  }
  if (n_partial > 0) {
    cli::cli_inform(
      c(
        "!" = "The catalog only partially covers the loaded variables
               in {cli::qty(n_partial)}year{?s} {partial_txt}; codes in
               the uncatalogued variables pass through unchanged.",
        "i" = "See {.fun brfss_labels} for coverage and
               {.fun brfss_missing_codes} for what was cleared."
      ),
      class = "brfssdata_na_coverage_note"
    )
  }
}
