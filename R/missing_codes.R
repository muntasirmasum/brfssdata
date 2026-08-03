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
#' Matching is deliberately conservative: a label counts as missing only
#' when every part of it (split on `/`, `,`, and the word "or") is a
#' known missing-answer phrase. Substantive answers that merely contain
#' one of the words, such as "Doctor refused when asked", never match.
#' Code 88/888 ("None") is an answer of zero, not missing, and is never
#' matched; recode it to 0 yourself before averaging a count variable
#' such as `PHYSHLTH`.
#'
#' @inheritParams brfss_labels
#'
#' @return A tibble with columns `year`, `variable`, `code`, and
#'   `label`, one row per code the missing-value rules match. Labels
#'   cover 1998 on, so earlier years never appear.
#'
#' @examplesIf interactive()
#' brfss_missing_codes("GENHLTH", years = 2023)
#' @seealso [brfss_labels()] for the full catalog.
#' @export
brfss_missing_codes <- function(
  vars = NULL,
  years = NULL,
  download = TRUE,
  quiet = TRUE
) {
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
  "missing",
  "blank",
  "not asked"
)

# A label marks a missing-type answer iff it has at least one token and
# every "/"-, ","-, or " or "-separated token is on the whitelist.
# Whole-token matching keeps substantive answers safe: "Doctor refused
# when asked", "No, I've refused treatment", and "zero or missing" all
# carry a token outside the whitelist and never match.
is_missing_label <- function(labels) {
  out <- vapply(
    strsplit(normalize_label(labels), "\\s*(/|,|\\bor\\b)\\s*"),
    function(tokens) {
      tokens <- trimws(tokens)
      tokens <- tokens[!is.na(tokens) & nzchar(tokens)]
      length(tokens) > 0 && all(tokens %in% MISSING_LABEL_TOKENS)
    },
    logical(1)
  )
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
  catalog <- catalog[
    catalog$year %in% years & is_missing_label(catalog$label),
    ,
    drop = FALSE
  ]

  vars <- setdiff(intersect(unique(catalog$variable), names(dat)), exclude)
  cleared <- 0L
  touched <- character(0)
  for (v in vars) {
    sub <- catalog[catalog$variable == v, , drop = FALSE]
    hit <- !is.na(dat[[v]]) &
      paste(dat$year, dat[[v]]) %in% paste(sub$year, sub$code)
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
  dat
}
