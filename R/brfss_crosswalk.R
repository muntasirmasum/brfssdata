#' Rename crosswalk: which variables are generations of one measure
#'
#' @description
#' CDC renames a variable when its definition or its questionnaire
#' context changes, usually by bumping a trailing digit: `_DRNKWK1`
#' becomes `_DRNKWK2` becomes `_DRNKWK3`. A multi-year analysis that
#' requests only one of those names silently loses the other years.
#' This function returns the crosswalk that accompanies the data
#' releases: variables grouped into concept families, one row per
#' variable and year, so the whole family is visible at once.
#'
#' Families are proposed mechanically (same stem, non-overlapping year
#' ranges) and reviewed by hand against CDC's codebooks over time.
#' `status` records how far that review has gone for each family:
#' `"verified"` means a person checked it,
#' `"candidate"` means the rules proposed it and review is pending, so
#' treat a candidate family as a strong hint, not a fact. A rename is
#' *never* a promise of comparability (CDC renamed the variable for a
#' reason), so combining generations is always your decision;
#' [read_brfss()] points here (a `brfssdata_rename_note` message) when
#' a requested variable is empty in years a sibling generation covers.
#'
#' @section Reading the crosswalk:
#' `generation` is the variable's position in the rename chain, in
#' order of first appearance: `ACEHURT` (2009-2012) is generation 1 of
#' the concept `acehurt`, its successor `ACEHURT1` (2019-2024) is
#' generation 2.
#'
#' `comparable` always sits on the *later* generation's rows and
#' answers one question: does this generation still measure the same
#' thing as the generation immediately before it, closely enough to
#' pool across the rename? `TRUE` means yes (the `note` gives the
#' basis); `FALSE` means the definition changed (the `note` says what
#' moved). On a family's first generation `comparable` is `NA` by
#' construction (there is nothing earlier to compare against), while
#' `NA` on a later generation of a candidate family means unreviewed.
#'
#' Verdicts are per link and do not chain through a `FALSE`. In the
#' falls-injury family, `FALLINJ2 -> FALLINJ3` is `FALSE` (the injury
#' definition in the question changed) while `FALLINJ3 -> FALLINJ4` is
#' `TRUE`: the later two generations pool, all three do not.
#'
#' When every link you span is `TRUE`, the pooling pattern is to
#' coalesce the generations into one analysis column and keep the
#' originals:
#'
#' ```r
#' dat <- read_brfss(2009:2024, vars = c("ACEHURT", "ACEHURT1"))
#' dat$acehurt <- dplyr::coalesce(dat$ACEHURT, dat$ACEHURT1)
#' ```
#'
#' `comparable` describes the *question's definition*, not the survey's
#' weighting: a family spanning 2010/2011 can be `TRUE` as a measure
#' while estimates across that boundary remain non-comparable because
#' of the weighting redesign, which is why [brfss_design()] keeps its
#' separate `allow_break` guard.
#'
#' Notes are complete sentences, and tibble printing truncates them to
#' the console width. To read them in full, pull the column or open the
#' viewer:
#'
#' ```r
#' brfss_crosswalk("_DRNKWK1") |>
#'   dplyr::pull(note) |>
#'   unique() |>
#'   writeLines()
#' ```
#'
#' @param vars Optional character vector of variable names, matched
#'   case-insensitively by exact name like in [brfss_labels()]. A match
#'   on *any* member of a family returns the whole family; that is
#'   the point of the lookup.
#' @param years Optional integer vector restricting the `year` rows.
#'   The family membership shown is unaffected; only rows are filtered.
#' @inheritParams brfss_labels
#'
#' @return A tibble with columns `concept` (family identifier),
#'   `variable`, `year`, `generation` (1, 2, ... in order of first
#'   appearance), `status`, `comparable`, and `note`, one row per
#'   variable-year. A lookup that matches nothing returns zero rows
#'   with a `brfssdata_empty_result` message. When only some requested
#'   variables belong to a family, the matching families are returned
#'   and a `brfssdata_partial_match_note` message names the ones with
#'   no entry.
#'
#' @examples
#' # The whole family, from any member's name. download = FALSE reads
#' # the cached copy, or the snapshot bundled with the package, so this
#' # runs offline.
#' brfss_crosswalk("_DRNKWK1", download = FALSE)
#' @seealso [brfss_vars()] to search variables; [brfss_codebook()] for
#'   a per-variable summary that includes the family.
#' @export
brfss_crosswalk <- function(
  vars = NULL,
  years = NULL,
  download = TRUE,
  quiet = TRUE
) {
  if (!is.null(vars) && (!is.character(vars) || anyNA(vars))) {
    cli::cli_abort(
      c(
        "{.arg vars} must be a character vector of variable names.",
        vars_arg_year_hint(vars, "brfss_crosswalk")
      ),
      class = "brfssdata_bad_vars_arg"
    )
  }
  if (!is.null(years)) {
    years <- check_years_arg(years)
  }
  xwalk <- crosswalk_catalog(download = download, quiet = quiet)
  unmatched <- character(0)
  if (!is.null(vars)) {
    # Membership judged against the whole catalog, before the years
    # filter: a family exists or it does not, regardless of which rows
    # the years filter keeps.
    vars_u <- unique(vars)
    unmatched <- vars_u[!toupper(vars_u) %in% toupper(xwalk$variable)]
    concepts <- unique(
      xwalk$concept[toupper(xwalk$variable) %in% toupper(vars)]
    )
    xwalk <- xwalk[xwalk$concept %in% concepts, , drop = FALSE]
  }
  if (!is.null(years)) {
    xwalk <- xwalk[xwalk$year %in% years, , drop = FALSE]
  }
  # A miss hiding inside a non-empty result is indistinguishable from a
  # typo without a signal. Exactly one signal per call; an all-miss
  # lookup gets only the empty-result message below. Quiet-independent,
  # like that message.
  if (nrow(xwalk) > 0 && length(unmatched) > 0) {
    n_miss <- length(unmatched)
    n_matched <- length(vars_u) - n_miss
    cli::cli_inform(
      c(
        "{cli::qty(n_miss)}Variable{?s} {.val {unmatched}}
         {cli::qty(n_miss)}{?belongs/belong} to no rename family;
         {cli::qty(n_matched)}the other requested variable{?s} matched.",
        "i" = "Most variables were never renamed, so no entry is the
               common case; the crosswalk lists a variable only when
               CDC renamed it. Search names with {.fun brfss_vars}."
      ),
      class = "brfssdata_partial_match_note"
    )
  }
  if (nrow(xwalk) == 0 && (!is.null(vars) || !is.null(years))) {
    cli::cli_inform(
      c(
        if (is.null(vars)) {
          "No crosswalk entries for year{?s} {.val {as.character(years)}}."
        } else {
          "No crosswalk entries for {.val {vars}}."
        },
        "i" = "The crosswalk lists a variable only once a rename family
               has been curated for it, so no entry means no family is
               recorded, not that the name was never changed. Check the
               years a name actually covers with {.fun brfss_vars}."
      ),
      class = "brfssdata_empty_result"
    )
  }
  xwalk
}

crosswalk_catalog <- function(
  download = TRUE,
  quiet = TRUE,
  call = rlang::caller_env()
) {
  read_catalog(
    "brfss_crosswalk.parquet",
    what = "rename crosswalk",
    download = download,
    quiet = quiet,
    call = call
  )
}

# The read path's rename note must never touch the network: cached copy
# if present, bundled snapshot otherwise, NULL (skip the note) when
# neither is readable. Served from the session memo after the first
# read, since this runs on every read_brfss(vars = ...) call.
crosswalk_catalog_offline <- function() {
  path <- cache_path("brfss_crosswalk.parquet")
  if (!file.exists(path)) {
    path <- bundled_asset_path("brfss_crosswalk.parquet")
  }
  if (is.null(path)) {
    return(NULL)
  }
  tryCatch(catalog_memo_get(path), error = function(e) NULL)
}
