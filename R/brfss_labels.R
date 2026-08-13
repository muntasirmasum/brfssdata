#' Value labels for BRFSS variables
#'
#' @description
#' Returns the value-label catalog that accompanies the data releases:
#' one row per year, variable, and numeric code, with the label text from
#' CDC's SAS format libraries. Labels cover 1998 onward; CDC does not
#' distribute usable format libraries for earlier years.
#'
#' The `complete` column marks variables whose format for that year is a
#' pure code-to-label map (no numeric ranges such as `1-30` days). Only
#' those variables are eligible for automatic factor conversion via
#' `read_brfss(labels = TRUE)`; for the rest, the catalog still documents
#' the special codes (typically 77/88/99) so you can recode by hand.
#'
#' @param vars Optional character vector restricting to those variables,
#'   matched case-insensitively by exact name. (Contrast [brfss_vars()],
#'   whose `pattern` is a regular expression searched over names *and*
#'   label text: this function looks names up, that one searches.)
#' @param years Optional integer vector restricting to those years.
#' @param download If `FALSE`, only a cached catalog is used, and a
#'   missing catalog raises an error instead of being downloaded.
#' @param quiet If `TRUE`, suppress download progress output.
#'
#' @return A tibble with columns `year`, `variable`, `code`, `label`,
#'   and `complete`. A lookup that matches nothing returns zero rows and
#'   says so with a `brfssdata_empty_result` message (regardless of
#'   `quiet`, which governs download output only). When only some
#'   requested variables match, the matching rows are returned and a
#'   `brfssdata_partial_match_note` message names the ones with no
#'   entries, also regardless of `quiet`.
#'
#' @examples
#' # download = FALSE reads the cached catalog, or the snapshot bundled
#' # with the package, so this runs offline.
#' brfss_labels("GENHLTH", years = 2023, download = FALSE)
#' @export
brfss_labels <- function(
  vars = NULL,
  years = NULL,
  download = TRUE,
  quiet = TRUE
) {
  if (!is.null(vars) && (!is.character(vars) || anyNA(vars))) {
    year_like <- is.numeric(vars) &&
      all(vars >= 1984 & vars <= 2100, na.rm = TRUE)
    hint <- if (year_like) {
      c(
        "i" = "Did you mean {.code brfss_labels(years = ...)}? The first
               argument is variable names; survey years come second."
      )
    }
    cli::cli_abort(
      c("{.arg vars} must be a character vector of variable names.", hint),
      class = "brfssdata_bad_vars_arg"
    )
  }
  if (!is.null(years)) {
    years <- check_years_arg(years)
  }
  catalog <- labels_catalog(download = download, quiet = quiet)
  if (!is.null(years)) {
    catalog <- catalog[catalog$year %in% years, , drop = FALSE]
  }
  unmatched <- character(0)
  if (!is.null(vars)) {
    vars_u <- unique(vars)
    catalog_upper <- toupper(catalog$variable)
    unmatched <- vars_u[!toupper(vars_u) %in% catalog_upper]
    keep <- catalog_upper %in% toupper(vars_u)
    catalog <- catalog[keep, , drop = FALSE]
  }
  # A miss hiding inside a non-empty result is the dangerous silent
  # case: rows came back, so nothing looks wrong. Exactly one signal
  # per call; an all-miss lookup gets only the empty-result message
  # below. Quiet-independent, like that message.
  if (nrow(catalog) > 0 && length(unmatched) > 0) {
    n_matched <- length(vars_u) - length(unmatched)
    scope <- if (is.null(years)) "" else " in the requested years"
    cli::cli_inform(
      c(
        "No label entries for {.val {unmatched}}{scope};
         {cli::qty(n_matched)}the other requested variable{?s} matched.",
        "i" = "Absence can be legitimate: continuous variables have no
               label entries, and labels cover 1998 on. Search names
               with {.fun brfss_vars}."
      ),
      class = "brfssdata_partial_match_note"
    )
  }
  if (nrow(catalog) == 0 && (!is.null(vars) || !is.null(years))) {
    cli::cli_inform(
      c(
        if (is.null(vars)) {
          "No label entries for year{?s} {.val {as.character(years)}}."
        } else {
          "No label entries for {.val {vars}}."
        },
        "i" = "Labels cover 1998 on; search variable names with
               {.fun brfss_vars}."
      ),
      class = "brfssdata_empty_result"
    )
  }
  catalog
}

labels_catalog <- function(
  download = TRUE,
  quiet = TRUE,
  call = rlang::caller_env()
) {
  path <- ensure_catalog_cached(
    "brfss_labels.parquet",
    what = "label catalog",
    download = download,
    quiet = quiet,
    call = call
  )
  query_parquet(path)
}

# Convert eligible variables to factors. A variable qualifies when, for
# the requested years, its format is `complete` everywhere, the code set
# is identical across those years, every observed value is covered, and
# the wording of each code did not change meaning across those years.
# Labels come from the most recent requested year, so cosmetic rewording
# is presented in CDC's latest phrasing. Anything else is left untouched.
#
# how = "label" gives plain label levels; "both" prefixes each level
# with its CDC code ("[1] Excellent", the haven convention), keeping
# codes recoverable after conversion. na = TRUE drops missing-type rows
# (don't know / refused) from the map, so the factor carries substantive
# levels only; the values themselves were already set to NA upstream by
# apply_missing_codes().
apply_labels <- function(
  dat,
  years,
  quiet = TRUE,
  exclude = character(0),
  download = TRUE,
  how = "label",
  na = FALSE
) {
  catalog <- labels_catalog(download = download, quiet = quiet)
  catalog <- catalog[
    catalog$year %in% years & catalog$complete,
    ,
    drop = FALSE
  ]
  if (isTRUE(na)) {
    catalog <- catalog[!is_missing_label(catalog$label), , drop = FALSE]
  }

  candidates <- setdiff(
    intersect(unique(catalog$variable), names(dat)),
    exclude
  )
  drifted <- character(0)
  for (v in candidates) {
    sub <- catalog[catalog$variable == v, , drop = FALSE]

    # Present (with a complete format) in every requested year it
    # appears in the data for; conservative when years differ.
    data_years <- unique(dat$year[!is.na(dat[[v]])])
    if (!all(data_years %in% sub$year)) {
      next
    }

    code_sets <- vapply(
      split(sub$code, sub$year),
      function(s) paste(sort(s), collapse = ","),
      character(1)
    )
    if (length(unique(code_sets)) != 1) {
      next
    }

    latest <- sub[sub$year == max(sub$year), , drop = FALSE]
    latest <- latest[order(latest$code), , drop = FALSE]

    # Only an unambiguous one-to-one code-to-label map is safe to hand
    # to factor(). CDC's format libraries sometimes give one code two
    # labels in a year, which factor() resolves silently by row order,
    # and sometimes reuse one label across several codes (NUMPHON2 in
    # 2003 labels eight codes with four strings, and _IMPNPH labels six
    # with a blank), which factor() silently merges into one level.
    # Either way the result looks plausible and is wrong, so anything
    # short of a clean bijection keeps its numeric codes.
    if (
      anyDuplicated(latest$code) > 0L ||
        anyDuplicated(latest$label) > 0L ||
        anyNA(latest$label) ||
        !all(nzchar(trimws(latest$label)))
    ) {
      next
    }

    vals <- dat[[v]]
    observed <- unique(vals[!is.na(vals)])
    if (!all(observed %in% latest$code)) {
      next
    }

    # Most wording differences in CDC's catalogs are cosmetic (case,
    # apostrophes, punctuation, the "<" house abbreviation); normalize
    # those away. What survives is a real change of meaning, and a
    # factor carries one level set for every row, so applying the
    # newest wording to earlier years would silently restate what those
    # respondents answered: COLNTES1 code 4 is "within the past 5
    # years" in 2021 and "within the past 10 years" from 2022. Refuse,
    # exactly as the duplicate-label and uncovered-value gates above do.
    if (length(unique(sub$year)) > 1) {
      per_year <- vapply(
        split(sub, sub$year),
        function(d) {
          ord <- order(d$code)
          paste(
            d$code[ord],
            normalize_semantic(d$label[ord]),
            collapse = "|"
          )
        },
        character(1)
      )
      if (length(unique(per_year)) != 1) {
        drifted <- c(drifted, v)
        next
      }
    }

    level_labels <- switch(
      how,
      label = latest$label,
      both = sprintf("[%s] %s", as.character(latest$code), latest$label)
    )
    # Levels are cast to the data's own type before factor() runs both
    # sides through as.character(): the parquet data column is double
    # ("1e+05" for 100000) while the catalog code is integer ("100000"),
    # so integer levels would silently turn any round code at or above
    # 1e5 into NA.
    dat[[v]] <- factor(
      vals,
      levels = as.numeric(latest$code),
      labels = level_labels
    )
  }
  if (length(drifted) > 0) {
    cli::cli_warn(
      c(
        "Label wording for {.val {drifted}} changed meaning across the
         requested years, so {?it/they} kept CDC's numeric codes.",
        "i" = "Compare the wording year by year with
               {.code brfss_labels(c({paste0('\"', drifted, '\"',
               collapse = ', ')}))}.",
        "i" = "Read the years separately if you want each year's own
               wording: one factor carries one level set for every row."
      ),
      class = "brfssdata_label_drift_warning"
    )
  }
  dat
}

# Case, apostrophes, punctuation, and spacing are presentation, not
# meaning; strip them before comparing label wording across years.
# "<" and ">" are folded to words first, because stripping punctuation
# would delete them outright and make CDC's house abbreviation ("anytime
# < 12 months ago" against "anytime less than 12 months ago") read as a
# change of meaning. "less that" is CDC's own typo for "less than"
# (EMPLOY1 in 2013).
normalize_semantic <- function(x) {
  x <- gsub("<", " less than ", x, fixed = TRUE)
  x <- gsub(">", " more than ", x, fixed = TRUE)
  x <- normalize_label(x)
  x <- gsub("\\bless that\\b", "less than", x)
  x <- gsub("[^a-z0-9 ]", "", x)
  gsub("[[:space:]]+", " ", trimws(x))
}

# Shared validation for the labels argument of read_brfss() and
# brfss_design(): FALSE is handled by the callers, so this sees only
# TRUE or "both" (or something to reject).
labels_how <- function(labels, call = rlang::caller_env()) {
  if (isTRUE(labels)) {
    return("label")
  }
  if (identical(labels, "both")) {
    return("both")
  }
  cli::cli_abort(
    '{.arg labels} must be `TRUE`, `FALSE`, or `"both"`.',
    class = "brfssdata_bad_labels_arg",
    call = call
  )
}
