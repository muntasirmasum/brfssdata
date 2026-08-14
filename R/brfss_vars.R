#' Search BRFSS variables across survey years
#'
#' @description
#' BRFSS variable names and availability drift across years. This function
#' searches the variable catalog that accompanies the data releases and
#' reports, for each match, which years carry the variable. The catalog is
#' downloaded once and cached like the data itself.
#'
#' A search that matches nothing says so and suggests near misses:
#' variables whose name or label is a small edit away (a typo'd
#' pattern), variables matching every word of a multi-word pattern in
#' any order, and, when `years` is given, matches that exist only in
#' other years.
#'
#' @param pattern Optional single regular expression matched
#'   (case-insensitively) against variable names and labels. The default
#'   lists every variable.
#' @param years Optional integer vector restricting the search to
#'   particular survey years.
#' @param download If `FALSE`, only a cached catalog is used, and a
#'   missing catalog raises an error instead of being downloaded.
#' @param quiet If `TRUE`, suppress download progress output.
#'
#' @return A tibble with one row per variable: `variable`, `label` (the
#'   most recent non-missing label, since label text can drift across
#'   years), and `years` (a compact summary of the years the variable
#'   appears in, e.g. `"2011-2013, 2020"`). Searches that match nothing
#'   return a zero-row tibble and say so with a
#'   `brfssdata_empty_result` message carrying the suggestions
#'   described above.
#'
#' @examples
#' # download = FALSE reads the cached catalog, or the snapshot bundled
#' # with the package, so this runs offline.
#' brfss_vars("smok", download = FALSE)
#' @export
brfss_vars <- function(
  pattern = NULL,
  years = NULL,
  download = TRUE,
  quiet = TRUE
) {
  if (!is.null(years)) {
    years <- check_years_arg(years)
  }
  catalog_all <- variables_catalog(download = download, quiet = quiet)

  catalog <- catalog_all
  if (!is.null(years)) {
    catalog <- catalog[catalog$year %in% years, , drop = FALSE]
  }
  if (!is.null(pattern)) {
    if (!is.character(pattern) || length(pattern) != 1L || is.na(pattern)) {
      # grepl() would silently use only the first element of a longer
      # vector, and the suppressWarnings below would hide its warning.
      cli::cli_abort(
        "{.arg pattern} must be a single regular expression.",
        class = "brfssdata_bad_pattern"
      )
    }
    # suppressWarnings: an invalid regex emits a TRE warning before the
    # error; the abort below already carries the compiler's message.
    hit <- tryCatch(
      suppressWarnings(match_catalog_pattern(pattern, catalog)),
      error = function(e) {
        cli::cli_abort(
          c(
            "{.arg pattern} ({.val {pattern}}) is not a valid regular
             expression.",
            "x" = "{conditionMessage(e)}"
          ),
          class = "brfssdata_bad_pattern"
        )
      }
    )
    catalog <- catalog[hit, , drop = FALSE]
  }

  if (nrow(catalog) == 0) {
    if (!is.null(pattern) || !is.null(years)) {
      inform_vars_empty(pattern, years, catalog_all)
    }
    return(tibble::tibble(
      variable = character(),
      label = character(),
      years = character()
    ))
  }
  summarize_catalog(catalog)
}

# Case-insensitive pattern match against names and labels. Only called
# with a validated pattern (brfss_vars() vets it once, up front).
match_catalog_pattern <- function(pattern, catalog) {
  label_text <- ifelse(is.na(catalog$label), "", catalog$label)
  grepl(pattern, catalog$variable, ignore.case = TRUE) |
    grepl(pattern, label_text, ignore.case = TRUE)
}

# One row per variable: latest non-missing label, compact year summary.
# (A formula aggregate() would silently drop NA labels via na.omit and
# split label-drifting variables across rows.)
summarize_catalog <- function(catalog) {
  idx <- split(seq_len(nrow(catalog)), catalog$variable)
  out <- tibble::tibble(
    variable = names(idx),
    label = unname(vapply(
      idx,
      function(i) {
        lab <- catalog$label[i][order(catalog$year[i], decreasing = TRUE)]
        lab <- lab[!is.na(lab)]
        if (length(lab) > 0) lab[[1]] else NA_character_
      },
      character(1)
    )),
    years = unname(vapply(
      idx,
      function(i) summarize_years(sort(unique(catalog$year[i]))),
      character(1)
    ))
  )
  # radix ordering is locale-independent, so the catalog comes back in
  # the same order on every machine.
  out[order(out$variable, method = "radix"), ]
}

# The zero-match message, classed brfssdata_empty_result like the other
# metadata lookups and quiet-independent like theirs. Suggestions come
# in tiers: the pattern matches in years outside the filter, every word
# of a multi-word pattern matches somewhere, or a name or label sits
# within a small edit distance. The fuzzy tiers are skipped when the
# pattern carries regex metacharacters, because edits to a deliberate
# regex are meaningless.
inform_vars_empty <- function(pattern, years, catalog_all) {
  if (is.null(pattern)) {
    cli::cli_inform(
      c(
        "No catalog entries for year{?s} {.val {as.character(years)}}.",
        "i" = "The catalog covers {summarize_years(catalog_all$year)}."
      ),
      class = "brfssdata_empty_result"
    )
    return(invisible())
  }

  header <- if (is.null(years)) {
    "No variables match {.val {pattern}}."
  } else {
    "No variables match {.val {pattern}} in the requested years."
  }

  # Requested years the catalog has never seen: the year is the
  # problem, not the pattern.
  coverage <- if (!is.null(years) && !any(years %in% catalog_all$year)) {
    cli::format_inline(
      "None of the requested years are in the catalog, which covers
       {summarize_years(catalog_all$year)}."
    )
  } else {
    character(0)
  }

  # Suggestions carry each variable's years whenever a years filter is
  # on, so a match that lives outside the filter says where it lives.
  detail <- function(s) {
    if (is.null(years)) {
      s$label
    } else {
      ifelse(is.na(s$label), s$years, paste0(s$label, "; ", s$years))
    }
  }
  hints <- character(0)

  # The pattern works, just not in these years.
  if (!is.null(years)) {
    other <- catalog_all[!catalog_all$year %in% years, , drop = FALSE]
    if (nrow(other) > 0) {
      other <- other[match_catalog_pattern(pattern, other), , drop = FALSE]
    }
    if (nrow(other) > 0) {
      s <- utils::head(summarize_catalog(other), 5L)
      hints <- c(
        hints,
        paste0(
          "It matches in other years: ",
          paste0(s$variable, " (", s$years, ")", collapse = ", "),
          "."
        )
      )
    }
  }

  plain <- !grepl("[][\\\\^$.|?*+(){}]", pattern)
  tokens <- strsplit(trimws(pattern), "[[:space:]]+")[[1]]

  # Multi-word patterns fail as regexes whenever the words sit in a
  # different order in the label; every-word matching is order-blind.
  # Scanned over the whole catalog so a match confined to other years
  # still surfaces; the years annotation says where it lives.
  if (plain && length(tokens) > 1 && nrow(catalog_all) > 0) {
    hit <- Reduce(
      `&`,
      lapply(tokens, function(t) match_catalog_pattern(t, catalog_all))
    )
    if (any(hit)) {
      s <- utils::head(summarize_catalog(catalog_all[hit, , drop = FALSE]), 5L)
      hints <- c(
        hints,
        paste0(
          "Every word matches on: ",
          format_var_labels(s$variable, detail(s)),
          "."
        )
      )
    }
  }

  # Typos: best partial edit distance against names and labels, over
  # the whole catalog for the same reason. Patterns under four
  # characters skip this tier: at distance one, a partial match against
  # some label is nearly guaranteed, so the suggestions would be noise.
  if (plain && length(hints) == 0 && nchar(pattern) >= 4L &&
      nrow(catalog_all) > 0) {
    d_name <- utils::adist(
      pattern,
      catalog_all$variable,
      ignore.case = TRUE,
      partial = TRUE
    )
    d_label <- utils::adist(
      pattern,
      ifelse(is.na(catalog_all$label), "", catalog_all$label),
      ignore.case = TRUE,
      partial = TRUE
    )
    d <- pmin(drop(d_name), drop(d_label))
    keep <- which(d <= edit_distance_limit(pattern))
    if (length(keep) > 0) {
      dmin <- tapply(d[keep], catalog_all$variable[keep], min)
      # radix ordering on the tie-break, per the package's
      # locale-independence policy (cf. summarize_catalog()).
      nm <- names(dmin)[order(unname(dmin), names(dmin), method = "radix")]
      s <- summarize_catalog(
        catalog_all[catalog_all$variable %in% nm, , drop = FALSE]
      )
      s <- utils::head(s[match(nm, s$variable), , drop = FALSE], 5L)
      hints <- c(
        hints,
        paste0("Close matches: ", format_var_labels(s$variable, detail(s)), ".")
      )
    }
  }

  if (length(hints) == 0 && length(coverage) == 0) {
    hints <- cli::format_inline(
      "Try a shorter substring or a single word; names and labels are
       both searched, and alternation like {.val smoke|cigarette} works
       too."
    )
  }
  bullets <- c(coverage, hints)
  cli::cli_inform(
    c(
      header,
      rlang::set_names(escape_cli_braces(bullets), rep("i", length(bullets)))
    ),
    class = "brfssdata_empty_result"
  )
}

# "VAR (label), VAR (label)" for suggestion bullets; NA labels drop
# their parentheses.
format_var_labels <- function(vars, labels) {
  paste0(
    ifelse(is.na(labels), vars, paste0(vars, " (", labels, ")")),
    collapse = ", "
  )
}

variables_catalog <- function(
  download = TRUE,
  quiet = TRUE,
  call = rlang::caller_env()
) {
  read_catalog(
    "brfss_variables.parquet",
    what = "variable catalog",
    download = download,
    quiet = quiet,
    call = call
  )
}
