#' Search BRFSS variables across survey years
#'
#' @description
#' BRFSS variable names and availability drift across years. This function
#' searches the variable catalog that accompanies the data releases and
#' reports, for each match, which years carry the variable. The catalog is
#' downloaded once and cached like the data itself.
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
#'   return a zero-row tibble.
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
  path <- ensure_catalog_cached(
    "brfss_variables.parquet",
    what = "variable catalog",
    download = download,
    quiet = quiet
  )

  catalog <- query_parquet(path)

  if (!is.null(years)) {
    if (!is.numeric(years) || anyNA(years)) {
      cli::cli_abort(
        "{.arg years} must be a numeric vector of survey years.",
        class = "brfssdata_bad_years_arg"
      )
    }
    catalog <- catalog[catalog$year %in% as.integer(years), , drop = FALSE]
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
    label_text <- ifelse(is.na(catalog$label), "", catalog$label)
    # suppressWarnings: an invalid regex emits a TRE warning before the
    # error; the abort below already carries the compiler's message.
    hit <- tryCatch(
      suppressWarnings(
        grepl(pattern, catalog$variable, ignore.case = TRUE) |
          grepl(pattern, label_text, ignore.case = TRUE)
      ),
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
    return(tibble::tibble(
      variable = character(),
      label = character(),
      years = character()
    ))
  }

  # One row per variable: latest non-missing label, compact year summary.
  # (A formula aggregate() would silently drop NA labels via na.omit and
  # split label-drifting variables across rows.)
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
