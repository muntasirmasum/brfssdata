#' Codebook card: everything the catalogs know about a variable
#'
#' @description
#' One row per requested variable, joining the three metadata catalogs:
#' the variable catalog (label wording and year availability), the
#' value-label catalog (codes and their meanings, with the missing-type
#' codes flagged), and the rename crosswalk (the variable's concept
#' family, if it belongs to one). It answers "what is this variable" in
#' one call; use [brfss_vars()] to *find* variables first.
#'
#' Printing renders a card per variable. The returned object is still a
#' regular tibble; the `values` and `missing_codes` columns are
#' list-columns of tibbles, `related` a list-column of sibling
#' variable names.
#'
#' @param vars Character vector of variable names, matched
#'   case-insensitively by exact name (required -- for browsing the
#'   whole catalog use [brfss_vars()]).
#' @param years Optional integer vector: restrict the value-label and
#'   availability detail to those years.
#' @inheritParams brfss_labels
#'
#' @return A tibble of class `brfss_codebook` with columns `variable`,
#'   `label` (most recent wording), `years` (compact range string),
#'   `values` (list-column: `year`, `code`, `label`, `complete`,
#'   `missing` per row), `missing_codes` (list-column, the `missing`
#'   subset), `concept`, and `related` (list-column of sibling
#'   generations from the crosswalk).
#'
#' @examples
#' brfss_codebook("GENHLTH", years = 2023, download = FALSE)
#' @seealso [brfss_vars()], [brfss_labels()], [brfss_missing_codes()],
#'   [brfss_crosswalk()].
#' @export
brfss_codebook <- function(
  vars,
  years = NULL,
  download = TRUE,
  quiet = TRUE
) {
  if (missing(vars) || !is.character(vars) || anyNA(vars) || length(vars) == 0) {
    cli::cli_abort(
      c(
        "{.arg vars} must be a character vector of variable names.",
        "i" = "To browse or search the whole catalog, use
               {.fun brfss_vars}."
      ),
      class = "brfssdata_bad_vars_arg"
    )
  }
  if (
    !is.null(years) &&
      (!is.numeric(years) || anyNA(years) || any(years != trunc(years)))
  ) {
    cli::cli_abort(
      "{.arg years} must be a numeric vector of survey years.",
      class = "brfssdata_bad_years_arg"
    )
  }

  path <- ensure_catalog_cached(
    "brfss_variables.parquet",
    what = "variable catalog",
    download = download,
    quiet = quiet
  )
  catalog <- query_parquet(path)
  labels <- labels_catalog(download = download, quiet = quiet)
  xwalk <- tryCatch(
    crosswalk_catalog(download = download, quiet = quiet),
    error = function(e) NULL
  )
  if (!is.null(years)) {
    catalog <- catalog[catalog$year %in% as.integer(years), , drop = FALSE]
    labels <- labels[labels$year %in% as.integer(years), , drop = FALSE]
  }

  requested <- unique(vars)
  canonical <- unique(catalog$variable)
  idx <- match(toupper(requested), toupper(canonical))
  unknown <- requested[is.na(idx)]
  if (length(unknown) > 0) {
    scope <- if (is.null(years)) {
      "in the variable catalog"
    } else {
      "in the variable catalog for the requested years"
    }
    n_unknown <- length(unknown)
    cli::cli_abort(
      c(
        "{cli::qty(n_unknown)}Variable{?s} {.val {unknown}}
         {cli::qty(n_unknown)}{?was/were} not found {scope}.",
        "i" = "Search names and labels with {.fun brfss_vars}."
      ),
      class = "brfssdata_bad_var"
    )
  }
  # Deduplicated on the canonical name, so case-variant duplicates in
  # the request ("GENHLTH", "genhlth") yield one card, not two.
  found <- unique(canonical[idx])

  rows <- lapply(found, function(v) {
    v_cat <- catalog[catalog$variable == v, , drop = FALSE]
    v_lab <- labels[labels$variable == v, , drop = FALSE]
    v_lab <- v_lab[order(v_lab$year, v_lab$code), , drop = FALSE]
    values <- tibble::tibble(
      year = v_lab$year,
      code = v_lab$code,
      label = v_lab$label,
      complete = v_lab$complete,
      missing = is_missing_label(v_lab$label)
    )
    concept <- NA_character_
    related <- character(0)
    if (!is.null(xwalk) && v %in% xwalk$variable) {
      concept <- xwalk$concept[xwalk$variable == v][[1]]
      related <- setdiff(
        unique(xwalk$variable[xwalk$concept == concept]),
        v
      )
    }
    newest <- v_cat$label[order(v_cat$year, decreasing = TRUE)]
    newest <- newest[!is.na(newest)]
    # Precomputed: tibble() evaluates arguments sequentially, so after
    # `values = list(values)` the name `values` would already refer to
    # the new list-column.
    missing_rows <- values[values$missing, , drop = FALSE]
    tibble::tibble(
      variable = v,
      label = if (length(newest) > 0) newest[[1]] else NA_character_,
      years = summarize_years(sort(unique(v_cat$year))),
      values = list(values),
      missing_codes = list(missing_rows),
      concept = concept,
      related = list(related)
    )
  })
  out <- do.call(rbind, rows)
  class(out) <- c("brfss_codebook", class(out))
  out
}

#' @export
print.brfss_codebook <- function(x, ...) {
  # Catalog label text is data, not a cli template; a literal brace in
  # a CDC label must never reach cli's interpolator.
  esc <- function(s) gsub("}", "}}", gsub("{", "{{", s, fixed = TRUE), fixed = TRUE)
  for (i in seq_len(nrow(x))) {
    cli::cli_rule(left = "{.strong {x$variable[[i]]}}")
    label <- x$label[[i]]
    if (is.na(label)) {
      label <- "(no label recorded)"
    }
    cli::cli_text(esc(label))
    cli::cli_text("Years: {x$years[[i]]}")
    if (!is.na(x$concept[[i]]) && length(x$related[[i]]) > 0) {
      cli::cli_text(
        "Family {.val {x$concept[[i]]}}: see also
         {.val {x$related[[i]]}} ({.fun brfss_crosswalk} for
         comparability)."
      )
    }
    values <- x$values[[i]]
    if (nrow(values) == 0) {
      cli::cli_text(
        "No value labels in the catalog here (labels cover 1998 on)."
      )
    } else {
      latest <- values[values$year == max(values$year), , drop = FALSE]
      cli::cli_text("Values ({max(values$year)}):")
      for (j in seq_len(nrow(latest))) {
        flag <- if (latest$missing[[j]]) " [missing-type]" else ""
        # The escaped label must BE the template, not an interpolated
        # value (interpolated values are inserted verbatim, so escaping
        # them would print literal doubled braces). The indent is
        # non-breaking spaces, escaped so the source stays ASCII,
        # because cli collapses ordinary leading whitespace.
        cli::cli_text(paste0(
          "\u00a0\u00a0",
          latest$code[[j]],
          ": ",
          esc(latest$label[[j]]),
          flag
        ))
      }
    }
    cli::cli_text("")
  }
  invisible(x)
}
