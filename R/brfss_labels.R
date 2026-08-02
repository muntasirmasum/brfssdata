#' Value labels for BRFSS variables
#'
#' @description
#' Returns the value-label catalog that accompanies the data releases:
#' one row per year, variable, and numeric code, with the label text from
#' CDC's SAS format libraries. Labels cover 1990 onward; CDC no longer
#' distributes label files for 1985-1989.
#'
#' The `complete` column marks variables whose format for that year is a
#' pure code-to-label map (no numeric ranges such as `1-30` days). Only
#' those variables are eligible for automatic factor conversion via
#' `read_brfss(labels = TRUE)`; for the rest, the catalog still documents
#' the special codes (typically 77/88/99) so you can recode by hand.
#'
#' @param vars Optional character vector restricting to those variables.
#' @param years Optional integer vector restricting to those years.
#' @inheritParams read_brfss
#'
#' @return A tibble with columns `year`, `variable`, `code`, `label`,
#'   and `complete`.
#'
#' @examplesIf interactive()
#' brfss_labels("GENHLTH", years = 2023)
#' @export
brfss_labels <- function(
  vars = NULL,
  years = NULL,
  download = TRUE,
  quiet = TRUE
) {
  catalog <- labels_catalog(download = download, quiet = quiet)
  if (!is.null(years)) {
    catalog <- catalog[catalog$year %in% as.integer(years), , drop = FALSE]
  }
  if (!is.null(vars)) {
    catalog <- catalog[catalog$variable %in% vars, , drop = FALSE]
  }
  catalog
}

labels_catalog <- function(
  download = TRUE,
  quiet = TRUE,
  call = rlang::caller_env()
) {
  path <- cache_path("brfss_labels.parquet")
  if (!file.exists(path)) {
    if (!download) {
      cli::cli_abort(
        "The label catalog is not cached and {.code download = FALSE}
         was set.",
        class = "brfssdata_not_cached",
        call = call
      )
    }
    download_to_cache(
      release_url("data-meta", "brfss_labels.parquet"),
      path,
      quiet = quiet,
      call = call
    )
  }
  query_parquet(path)
}

# Convert eligible variables to factors. A variable qualifies when, for
# the requested years, its format is `complete` everywhere, the code set
# is identical across those years, and every observed value is covered.
# Labels come from the most recent requested year (wording drifts).
# Anything else is left untouched.
apply_labels <- function(dat, years, quiet = TRUE, exclude = character(0)) {
  catalog <- labels_catalog(download = TRUE, quiet = quiet)
  catalog <- catalog[
    catalog$year %in% years & catalog$complete,
    ,
    drop = FALSE
  ]

  candidates <- setdiff(
    intersect(unique(catalog$variable), names(dat)),
    exclude
  )
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

    vals <- dat[[v]]
    observed <- unique(vals[!is.na(vals)])
    if (!all(observed %in% latest$code)) {
      next
    }

    dat[[v]] <- factor(vals, levels = latest$code, labels = latest$label)
  }
  dat
}
