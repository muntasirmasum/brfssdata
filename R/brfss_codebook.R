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
#' @details
#' The card documents codes and labels only. It carries no units, no
#' scale factor, and no valid range, so a calculated variable CDC
#' stores scaled (`_BMI5` and `_DRNKWK2` carry two implied decimals)
#' looks no different here from an unscaled one, and a range format
#' lists its special codes without the ordinary values around them.
#' Read magnitudes against CDC's codebook for the year, whose address
#' is `brfss_year_info()$codebook_url`.
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
  if (!is.null(years)) {
    years <- check_years_arg(years)
  }

  catalog <- variables_catalog(download = download, quiet = quiet)
  labels <- labels_catalog(download = download, quiet = quiet)
  # The years the value-label catalog covers at all, read before the
  # year filter narrows it: an empty value set means something
  # different inside that span (the CDC format carries no code list)
  # than outside it (no format library to read).
  label_years <- sort(unique(labels$year))
  # A checksum mismatch or an unreadable cached file is the package's
  # headline integrity signal and must reach the user, not be swallowed
  # into a card with the rename family silently dropped; R/cache.R
  # makes the same exception. One handler that re-raises, rather than a
  # class-specific handler ahead of a generic one, because re-raising
  # from an earlier handler is caught by a later handler of the same
  # tryCatch(). Anything else costs only the family, so it degrades to
  # a note.
  xwalk <- tryCatch(
    crosswalk_catalog(download = download, quiet = quiet),
    error = function(e) {
      if (
        inherits(e, c("brfssdata_checksum_error", "brfssdata_corrupt_cache"))
      ) {
        stop(e)
      }
      cli::cli_inform(
        c(
          "!" = "Could not read the rename crosswalk; these cards omit
                 concept family and related variables."
        ),
        class = "brfssdata_manifest_note"
      )
      NULL
    }
  )
  if (!is.null(years)) {
    catalog <- catalog[catalog$year %in% years, , drop = FALSE]
    labels <- labels[labels$year %in% years, , drop = FALSE]
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
    # Rides along on the row's own values tibble so it survives
    # subsetting; the print method needs it only when there is nothing
    # to print.
    attr(values, "coverage") <- list(
      in_coverage = any(v_cat$year %in% label_years),
      start = if (length(label_years) > 0) min(label_years) else NA_integer_
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
      coverage <- attr(values, "coverage")
      if (isTRUE(coverage$in_coverage)) {
        # Inside the catalog's span an empty value set is a statement
        # about the CDC format, not about coverage: continuous and
        # range-only formats reach the catalog with their special
        # codes only, and some carry none.
        cli::cli_text(
          "No coded values here: this variable's CDC format is
           continuous or range-only, so only special codes would be
           cataloged and it has none."
        )
        cli::cli_text(
          "The valid range and any implied decimals are in CDC's
           codebook for the year ({.fun brfss_year_info} gives the
           URL)."
        )
      } else if (!is.null(coverage) && !is.na(coverage$start)) {
        cli::cli_text(
          "No value labels in the catalog here (labels cover
           {coverage$start} on)."
        )
      } else {
        cli::cli_text("No value labels in the catalog here.")
      }
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
      # A range format reaches the catalog as its special codes alone
      # (data-raw/05_labels.R keeps integer left-hand sides), so the
      # list above is not the variable's value set.
      if (any(!latest$complete, na.rm = TRUE)) {
        cli::cli_text(
          "Range format: only the special codes above are cataloged.
           Ordinary in-range values are valid and are not listed, and
           some calculated variables are stored scaled ({.code _BMI5}
           and {.code _DRNKWK2} carry two implied decimals). See CDC's
           codebook for the year ({.fun brfss_year_info} gives the
           URL)."
        )
      }
    }
    cli::cli_text("")
  }
  invisible(x)
}
