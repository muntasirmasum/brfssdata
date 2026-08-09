#' Citations for the package and the survey years an analysis used
#'
#' @description
#' Returns ready-to-use [utils::bibentry()] citations: CDC's
#' recommended citation for each requested survey year's data, plus
#' the package citation. Print the result for formatted text, or use
#' `toBibtex()` on it for a `.bib` file. Entirely offline; the years
#' are validated against the cached or bundled manifest.
#'
#' @param years Optional integer vector of one or more survey years to
#'   cite. `NULL` cites the collection's span as a single entry.
#'
#' @return A [utils::bibentry()] vector: one entry per requested year
#'   (or one spanning entry when `years = NULL`), then the package
#'   entry. Every entry carries a BibTeX key, `brfssdata` for the
#'   package, `brfss` for the spanning data entry, and `brfss2023` and
#'   the like for each requested year, so `toBibtex()` output drops
#'   into a `.bib` file unedited.
#'
#' @examples
#' brfss_citation(2023)
#' toBibtex(brfss_citation(2022:2023))
#' @export
brfss_citation <- function(years = NULL) {
  if (!is.null(years)) {
    if (
      !is.numeric(years) ||
        length(years) == 0 ||
        anyNA(years) ||
        any(years != trunc(years))
    ) {
      cli::cli_abort(
        "{.arg years} must be a numeric vector of one or more survey years.",
        class = "brfssdata_bad_years_arg"
      )
    }
    years <- sort(unique(as.integer(years)))
    published <- sort(as.integer(read_manifest_cached()$years))
    unknown <- setdiff(years, published)
    if (length(published) > 0 && length(unknown) > 0) {
      cli::cli_abort(
        c(
          "Year{?s} {.val {as.character(unknown)}} {?is/are} not among
           the published releases.",
          "i" = "See {.fun brfss_years}."
        ),
        class = "brfssdata_bad_year"
      )
    }
  }

  # A stable BibTeX key per entry, so toBibtex() output compiles
  # without hand-editing. "brfss2023" rather than "brfssdata2023" keeps
  # the data citations distinct from the package's own "brfssdata" key.
  cdc <- function(year_text, key) {
    utils::bibentry(
      bibtype = "Misc",
      key = key,
      title = paste(
        "Behavioral Risk Factor Surveillance System Survey Data,",
        year_text
      ),
      author = utils::person(
        "Centers for Disease Control and Prevention (CDC)"
      ),
      year = year_text,
      publisher = paste(
        "U.S. Department of Health and Human Services,",
        "Centers for Disease Control and Prevention"
      ),
      address = "Atlanta, Georgia",
      url = "https://www.cdc.gov/brfss/"
    )
  }
  data_entries <- if (is.null(years)) {
    published <- sort(as.integer(read_manifest_cached()$years))
    cdc(
      if (length(published) == 0) {
        "[year]"
      } else {
        paste(range(published), collapse = "-")
      },
      key = "brfss"
    )
  } else {
    # years is sorted and deduplicated above, so the keys are unique.
    do.call(
      c,
      lapply(years, function(y) cdc(as.character(y), paste0("brfss", y)))
    )
  }
  # Only the package's own entry from inst/CITATION: its generic CDC
  # data entry spans the whole collection, and the per-year entries
  # above replace it here.
  pkg <- utils::citation("brfssdata")
  is_pkg <- vapply(
    unclass(pkg),
    function(e) identical(attr(e, "bibtype"), "Manual"),
    logical(1)
  )
  c(data_entries, pkg[is_pkg])
}
