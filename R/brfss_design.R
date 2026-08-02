#' Build a survey-design object for BRFSS analysis
#'
#' @description
#' Returns a [srvyr::as_survey_design()] `tbl_svy` with the complex sampling
#' design applied: primary sampling units (`_PSU`), strata (`_STSTR`), and
#' the year-appropriate final weight. Weight selection is automatic:
#' `_FINALWT` for years before 2011 (post-stratification era) and
#' `_LLCPWT` from 2011 on (raking era).
#'
#' CDC states that estimates from 2011 onward are not directly comparable
#' to earlier years, because 2011 added cell-phone-only respondents and
#' replaced post-stratification with raking. Requests that pool years from
#' both sides of that boundary therefore fail unless `allow_break = TRUE`
#' is set deliberately.
#'
#' That guard covers the one break CDC describes as disqualifying, and it
#' is not a general promise that any two years on the same side are
#' comparable. Raking margins, state participation, and collection
#' conditions all move within an era. CDC publishes a comparability
#' document with each annual release, and a year-over-year shift is worth
#' reading there before it is read as a change in the population.
#'
#' When several years are combined, weights are divided by the number of
#' years (`pool_weights = TRUE`, the default) so that pooled estimates
#' represent an average year rather than a sum of populations, and the
#' variance strata become the year-by-stratum interaction, treating each
#' annual survey as an independent sample.
#'
#' From 2001 on, `_PSU` is a record sequence number that restarts in
#' each state, so it repeats across the file but is unique within a
#' stratum: every stratum-by-PSU cell holds exactly one respondent.
#' Single-PSU strata are therefore common and would make variance
#' estimation fail. If `options(survey.lonely.psu)` is unset, this
#' function sets it to `"adjust"` (standard BRFSS practice) and says so
#' once per session; an option you set yourself is always respected.
#'
#' Because that clustering is nominal, the design for those years is
#' built without a cluster term, which gives the same estimates, standard
#' errors, and degrees of freedom far faster than carrying a cluster
#' factor with one level per respondent. Files through 2000 carry genuine
#' multi-respondent PSUs and keep the clustered estimator, nested within
#' stratum because the identifiers are reused. The choice is made from
#' the data, so it follows the file rather than the year.
#'
#' @inheritParams read_brfss
#' @param vars Optional character vector of analysis variables to carry
#'   into the design, matched case-insensitively like in [read_brfss()].
#'   Design variables are always included.
#' @param allow_break Set to `TRUE` to permit pooling years across the
#'   2011 methodology change. A warning is still issued.
#' @param pool_weights If `TRUE` and more than one year is requested,
#'   divide each weight by the number of years.
#'
#' @return A `tbl_svy` survey-design object. The underlying data carry
#'   three added syntactic columns the design is built on: `brfss_wt`
#'   (the selected, possibly pooled, weight), `brfss_psu`, and
#'   `brfss_strata` (the raw stratum for a single year; the
#'   year-by-stratum interaction when years are pooled). The original
#'   CDC columns are kept unchanged.
#'
#' @examplesIf interactive()
#' library(srvyr)
#' des <- brfss_design(2023, vars = "GENHLTH")
#' des |>
#'   group_by(GENHLTH) |>
#'   summarize(prop = survey_prop())
#' @export
brfss_design <- function(
  years,
  vars = NULL,
  allow_break = FALSE,
  pool_weights = TRUE,
  download = TRUE,
  quiet = FALSE,
  labels = FALSE
) {
  years <- validate_years(years, download = download)

  pre <- years[years < BREAK_YEAR]
  post <- years[years >= BREAK_YEAR]
  spans_break <- length(pre) > 0 && length(post) > 0

  if (spans_break && !allow_break) {
    cli::cli_abort(
      c(
        "Years {min(years)}-{max(years)} span the 2011 BRFSS redesign.",
        "x" = "CDC states post-2011 estimates are not directly comparable
               to earlier years (cell-phone frame and raking weights).",
        "i" = "Analyze the eras separately, or set
               {.code allow_break = TRUE} to pool anyway."
      ),
      class = "brfssdata_break_error"
    )
  }

  weight_vars <- c(
    if (length(pre) > 0) WEIGHT_PRE,
    if (length(post) > 0) WEIGHT_POST
  )
  design_vars <- c(weight_vars, DESIGN_STRATA, DESIGN_PSU)

  dat <- read_brfss(
    years,
    vars = if (is.null(vars)) NULL else union(vars, design_vars),
    download = download,
    quiet = quiet
  )

  missing_cols <- setdiff(design_vars, names(dat))
  if (length(missing_cols) > 0) {
    cli::cli_abort(
      c(
        "Design variable{?s} {.val {missing_cols}} {?is/are} missing from
         the requested year{?s}.",
        "i" = "Each year needs its era weight, {.val {DESIGN_STRATA}},
               and {.val {DESIGN_PSU}}."
      ),
      class = "brfssdata_bad_design_var"
    )
  }

  if (spans_break) {
    cli::cli_warn(
      "Pooling across the 2011 redesign: interpret trends with caution."
    )
    wt <- ifelse(
      dat$year >= BREAK_YEAR,
      dat[[WEIGHT_POST]],
      dat[[WEIGHT_PRE]]
    )
  } else {
    wt <- dat[[weight_vars]]
  }

  if (pool_weights && length(years) > 1) {
    wt <- wt / length(years)
  }

  bad_wt <- is.na(wt)
  if (any(bad_wt)) {
    bad_years <- sort(unique(dat$year[bad_wt]))
    cli::cli_abort(
      c(
        "{sum(bad_wt)} respondent{?s} in year{?s} {bad_years} {?has/have}
         a missing final weight.",
        "i" = "A survey design cannot be built over missing weights."
      ),
      class = "brfssdata_bad_design_var"
    )
  }

  # CDC's design variable names (_PSU, _STSTR) are not syntactic R names
  # and cannot enter survey's formula interface; the design is built on
  # syntactic copies, with the originals kept alongside. Pooled years are
  # independent annual samples, so multi-year strata are the year-by-
  # stratum interaction (with nest = TRUE this also isolates any PSU id
  # reuse across years).
  # Checked before the pooled stratum is built: paste() would turn a
  # missing stratum into the literal string "YYYY_NA" and quietly pool
  # every such respondent into one fabricated stratum, which the single
  # year path would have rejected outright.
  for (design_col in c(DESIGN_STRATA, DESIGN_PSU)) {
    bad <- is.na(dat[[design_col]])
    if (any(bad)) {
      bad_years <- sort(unique(dat$year[bad]))
      cli::cli_abort(
        c(
          "{sum(bad)} respondent{?s} in year{?s} {bad_years} {?has/have}
           a missing {.val {design_col}}.",
          "i" = "A survey design cannot be built over missing strata or
                 primary sampling units."
        ),
        class = "brfssdata_bad_design_var"
      )
    }
  }

  dat$brfss_wt <- wt
  dat$brfss_psu <- dat[[DESIGN_PSU]]
  dat$brfss_strata <- if (length(years) > 1) {
    paste(dat$year, dat[[DESIGN_STRATA]], sep = "_")
  } else {
    dat[[DESIGN_STRATA]]
  }

  if (isTRUE(labels)) {
    dat <- apply_labels(
      dat,
      years,
      quiet = quiet,
      download = download,
      exclude = c(
        design_vars,
        "brfss_wt",
        "brfss_psu",
        "brfss_strata",
        "year"
      )
    )
  }

  # From 2001 on, BRFSS public-use files make each respondent their own
  # PSU, so small strata (and most subgroup analyses) contain single-PSU
  # strata that make variance estimation fail. "adjust" is standard
  # BRFSS practice. The survey package sets "fail" in .onLoad, so that
  # value is treated as unset; any other user-chosen value is respected.
  # identical() rather than %in%: a malformed option of length != 1
  # would make `if` error with "the condition has length > 1".
  if (identical(getOption("survey.lonely.psu", "fail"), "fail")) {
    options(survey.lonely.psu = "adjust")
    cli::cli_inform(
      c(
        "i" = "Set {.code options(survey.lonely.psu = \"adjust\")} for
               single-PSU strata (standard BRFSS practice).",
        "i" = "Set that option yourself before calling
               {.fun brfss_design} to choose different handling."
      ),
      .frequency = "once",
      .frequency_id = "brfssdata_lonely_psu"
    )
  }

  # Whether _PSU is a real cluster identifier changed with the 2001
  # files. Through 2000 several respondents share one, and the clustered
  # estimator is the correct one. From 2001 on it is the record sequence
  # number, so each stratum-by-PSU cell holds one respondent, the
  # clustering is nominal, and dropping it gives the same estimate,
  # standard error, and degrees of freedom while sparing survey a
  # cluster factor with one level per respondent (a survey_mean() over a
  # single recent year drops from about 77 to 5 seconds). The test is on
  # the data actually loaded, not on the year, so a file that stops
  # behaving this way keeps its clusters.
  singleton_psus <- anyDuplicated(dat[c("brfss_strata", "brfss_psu")]) == 0

  if (singleton_psus) {
    # check_strata = FALSE skips survey's nested-clusters test, which
    # cross-tabulates clusters by strata. Each observation is its own
    # cluster here, so the test can only ever pass, and on pooled years
    # the table it would build overflows R's vector limit.
    srvyr::as_survey_design(
      dat,
      ids = NULL,
      strata = brfss_strata,
      weights = brfss_wt,
      check_strata = FALSE
    )
  } else {
    srvyr::as_survey_design(
      dat,
      ids = brfss_psu,
      strata = brfss_strata,
      weights = brfss_wt,
      nest = TRUE
    )
  }
}
