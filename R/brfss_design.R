#' Build a survey-design object for BRFSS analysis
#'
#' @description
#' Returns a [srvyr::as_survey_design()] `tbl_svy` with the complex sampling
#' design applied: primary sampling units (`_PSU`), strata (`_STSTR`), and
#' the year-appropriate final weight. Weight selection is automatic:
#' `_FINALWT` for years before 2011 (post-stratification era) and
#' `_LLCPWT` from 2011 on (raking era). Pass `weight` to override it
#' (see *Choosing a weight*).
#'
#' By default the codes CDC uses for don't know / refused / missing
#' answers are set to `NA` (`na = TRUE`), so means and proportions are
#' computed over substantive answers; see [brfss_missing_codes()] for
#' the exact codes and the `na` entry under Arguments for details.
#'
#' @section Choosing a weight:
#' `weight` accepts CDC's final analysis weights: the full-sample
#' weights `_FINALWT` (1985-2010) and `_LLCPWT` (2011 on), the domain
#' weights `_CLLCPWT` (2011 on) and, for 2006-2010, `_CHILDWT` and
#' `_HOUSEWT`, and the 2007 questionnaire-version weights `_FINALQ1`,
#' `_FINALQ2`, `_CHILDQ1`, and `_CHILDQ2`. `_LLCPWT` is correct for
#' core-questionnaire analyses of the combined landline-and-cell
#' sample; `_FINALWT` is its pre-2011 counterpart. A final weight
#' requested for years outside its published span fails before
#' anything is downloaded, with the span named.
#'
#' The files also carry the intermediate stages of CDC's weighting
#' pipeline, such as `_STRWT`, `_WT2RAKE`, and `_LLCPWT2` (the
#' truncated design weight, computed before raking). None of those is
#' an analysis weight, and estimates computed with one are not
#' calibrated to CDC's population totals, so requesting one, or any
#' other column that is not a final weight, is a classed error
#' (`brfssdata_unrecognized_weight`) unless `unsafe_weight = TRUE`
#' says you mean it. The override still warns with a pointed class,
#' and the weight values must be positive and finite either way.
#'
#' Optional modules asked in states that fielded several questionnaire
#' versions are published by CDC as separate version datasets
#' (`LLCPyyV1` to `LLCPyyV3`) with their own final weights (`_LCPWTV1`
#' to `_LCPWTV3`). Those datasets are not part of this package's hosted
#' annual files, so version-specific module analyses need CDC's own
#' downloads. The year's CDC module-analysis documentation ("Complex
#' Sampling Weights and Preparing Module Data for Analysis") says which
#' modules belong to the combined dataset, where the default `_LLCPWT`
#' is correct. A user-supplied domain weight defines its analytic
#' domain: a module weight exists only for the records its module
#' applies to (completed child interviews for `_CLLCPWT`, so most rows
#' carry `NA` there), and the design subsets to the rows the weight
#' covers, reporting the drop with a `brfssdata_weight_subset_note`
#' message, which matches CDC's module-analysis guidance. An explicitly
#' named full-sample weight (`_FINALWT`, `_LLCPWT`) gets the same
#' treatment as the automatic era weight instead: it must cover every
#' respondent, and a missing value there means a damaged file and stops
#' the build. A user-supplied weight is used for every requested year
#' and still divides by the year count under `pool_weights`.
#'
#' The reverse mistake, a module variable analyzed under a full-sample
#' weight, is caught by a confinement check: when a requested variable
#' has data almost only where a module weight is non-missing (2023
#' child asthma `CASTHDX2` sits inside `_CLLCPWT`'s records for 99.7%
#' of its answers), a `brfssdata_module_weight_warning` names the
#' module weight to consider. It warns rather than fails because
#' state-optional modules that CDC assigns to the core weight produce
#' the same shape; the year's module-analysis documentation settles
#' those. The check runs only when `vars` is given and can be disabled
#' with `options(brfssdata.module_weight_check = FALSE)`.
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
#' annual survey as an independent sample. The pooled estimate averages
#' over the states participating each year; when participation differs
#' across the pooled years, totals mix coverage, and a warning says so.
#'
#' From 2001 on, `_PSU` is a record sequence number that restarts in
#' each state, so it repeats across the file but is unique within a
#' stratum: every stratum-by-PSU cell holds exactly one respondent.
#' Single-PSU strata are therefore common and would make variance
#' estimation fail. If `options(survey.lonely.psu)` is unset, this
#' function sets it to `"adjust"` (standard BRFSS practice) and says so
#' once per session. Any value you set other than `"fail"` is respected;
#' `"fail"` is what the survey package itself installs on load, so it
#' cannot be told apart from "never set" and is treated as unset. To
#' insist on `"fail"`, or to pin any handling, set
#' `options(brfssdata.lonely_psu = ...)`, which is copied into
#' `survey.lonely.psu` unconditionally. The option stays set for the
#' session because survey consults it at estimation time, not design
#' time.
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
#'   Design variables are always included. The default loads every
#'   column (455 columns by 506,467 rows for 2011 alone) and says so;
#'   passing only the variables you analyze is much faster and smaller.
#' @param states Optional vector of reporting jurisdictions (FIPS,
#'   postal abbreviations, or names; see [brfss_states]), filtered
#'   inside the query like in [read_brfss()]. Filtering by state
#'   *before* the design is built is variance-exact here: BRFSS strata
#'   (`_STSTR`) nest within state, so a state subset keeps whole strata
#'   and yields the same estimates, standard errors, and degrees of
#'   freedom as subsetting the full design afterwards. That property is
#'   specific to whole-stratum subsets; any other domain (an age group,
#'   one sex) must be analyzed by filtering the returned design object,
#'   never the data (see the *Survey design in BRFSS* article).
#' @param weight Optional name of the weight column to use instead of
#'   the automatic era weight, e.g. `"_CLLCPWT"` for the child-level
#'   modules; matched case-insensitively. Must be one of CDC's final
#'   analysis weights unless `unsafe_weight = TRUE`. See *Choosing a
#'   weight*.
#' @param unsafe_weight Set to `TRUE` to allow a `weight` that is not
#'   one of CDC's final analysis weights (an intermediate pipeline
#'   stage, or any other numeric column). The design still warns with
#'   a pointed class, and the values must be positive and finite. Has
#'   no effect when `weight` names a final weight.
#' @param allow_break Set to `TRUE` to permit pooling years across the
#'   2011 methodology change. A warning is still issued.
#' @param pool_weights If `TRUE` and more than one year is requested,
#'   divide each weight by the number of years.
#' @param na If `TRUE` (the default here), set the codes CDC uses for
#'   missing-type answers (don't know / not sure, refused, not asked) to
#'   `NA` before the design is built, so estimates cover substantive
#'   answers; see [brfss_missing_codes()] for exactly which codes, and
#'   the same argument in [read_brfss()] (where the default is `FALSE`)
#'   for the full details.
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
  states = NULL,
  weight = NULL,
  unsafe_weight = FALSE,
  allow_break = FALSE,
  pool_weights = TRUE,
  download = TRUE,
  quiet = FALSE,
  labels = FALSE,
  na = TRUE
) {
  years <- validate_years(years, download = download)
  if (
    !is.null(weight) &&
      (!is.character(weight) ||
        length(weight) != 1L ||
        is.na(weight) ||
        !nzchar(weight))
  ) {
    cli::cli_abort(
      "{.arg weight} must be a single column name, e.g. {.val _CLLCPWT}.",
      class = "brfssdata_bad_weight"
    )
  }
  if (!isTRUE(unsafe_weight) && !isFALSE(unsafe_weight)) {
    cli::cli_abort(
      "{.arg unsafe_weight} must be TRUE or FALSE.",
      class = "brfssdata_bad_unsafe_weight_arg"
    )
  }
  if (!isTRUE(na) && !isFALSE(na)) {
    cli::cli_abort(
      "{.arg na} must be TRUE or FALSE.",
      class = "brfssdata_bad_na_arg"
    )
  }
  # Validated eagerly: passed lazily, an invalid labels value would only
  # surface if some variable actually converted.
  labels_mode <- if (isFALSE(labels)) NULL else labels_how(labels)

  # The gate runs before anything is downloaded or read. A weight that
  # is not one of CDC's final analysis weights is refused unless
  # unsafe_weight = TRUE says the caller knows; an allowlisted weight
  # requested outside its published span fails here too, with the span
  # named, instead of surfacing later as a missing column.
  if (!is.null(weight)) {
    final_idx <- match(toupper(weight), toupper(FINAL_WEIGHTS$weight))
    if (is.na(final_idx) && !unsafe_weight) {
      cli::cli_abort(
        c(
          "{.val {weight}} is not one of CDC's final analysis weights.",
          "x" = "brfss_design() accepts the full-sample weights
                 {.val _FINALWT} (1985-2010) and {.val _LLCPWT} (2011
                 on), the domain weights {.val _CLLCPWT},
                 {.val _CHILDWT}, and {.val _HOUSEWT}, and the 2007
                 questionnaire-version weights {.val _FINALQ1},
                 {.val _FINALQ2}, {.val _CHILDQ1}, and
                 {.val _CHILDQ2}.",
          if (toupper(weight) %in% toupper(INTERMEDIATE_WEIGHTS)) {
            c(
              "i" = "{.val {weight}} is an intermediate stage of CDC's
                     weighting pipeline; estimates weighted by it are
                     not calibrated to CDC's population totals."
            )
          },
          "i" = "Set {.code unsafe_weight = TRUE} to use it anyway, at
                 your own risk; the era default needs no {.arg weight}
                 at all."
        ),
        class = c("brfssdata_unrecognized_weight", "brfssdata_bad_weight")
      )
    }
    if (!is.na(final_idx)) {
      # Canonical CDC casing for everything downstream.
      weight <- FINAL_WEIGHTS$weight[[final_idx]]
      span_first <- FINAL_WEIGHTS$first_year[[final_idx]]
      span_last <- FINAL_WEIGHTS$last_year[[final_idx]]
      outside <- years[
        years < span_first | (!is.na(span_last) & years > span_last)
      ]
      if (length(outside) > 0) {
        span_txt <- if (is.na(span_last)) {
          sprintf("%d on", span_first)
        } else if (span_first == span_last) {
          sprintf("%d only", span_first)
        } else {
          sprintf("%d to %d", span_first, span_last)
        }
        cli::cli_abort(
          c(
            "Weight {.val {weight}} is published for {span_txt};
             requested year{?s} {.val {as.character(outside)}}
             {?falls/fall} outside that.",
            "i" = "Use {.fun brfss_vars} to check availability, or
                   request only the years that carry it."
          ),
          class = "brfssdata_bad_weight"
        )
      }
    }
  }

  pre <- years[years < BREAK_YEAR]
  post <- years[years >= BREAK_YEAR]
  spans_break <- length(pre) > 0 && length(post) > 0

  if (spans_break && !allow_break) {
    cli::cli_abort(
      c(
        "Years {summarize_years(years)} span the 2011 BRFSS redesign.",
        "x" = "CDC states post-2011 estimates are not directly comparable
               to earlier years (cell-phone frame and raking weights).",
        "i" = "Analyze the eras separately, or set
               {.code allow_break = TRUE} to pool anyway."
      ),
      class = "brfssdata_break_error"
    )
  }

  auto_weights <- c(
    if (length(pre) > 0) WEIGHT_PRE,
    if (length(post) > 0) WEIGHT_POST
  )

  # The full-width load note lives in read_brfss(), which vars = NULL is
  # passed straight through to, so both entry points signal it once.

  dat <- read_brfss(
    years,
    vars = if (is.null(vars)) {
      NULL
    } else {
      union(vars, c(weight %||% auto_weights, DESIGN_STRATA, DESIGN_PSU))
    },
    states = states,
    download = download,
    quiet = quiet
  )

  requested_weight <- weight
  if (!is.null(weight)) {
    weight <- match_vars_ci(weight, names(dat))
    if (!weight %in% names(dat)) {
      cli::cli_abort(
        c(
          "Weight {.val {requested_weight}} was not found in the
           requested year{?s}.",
          "i" = "Use {.fun brfss_vars} to check which years carry it."
        ),
        class = "brfssdata_bad_weight"
      )
    }
    if (weight %in% INTERMEDIATE_WEIGHTS) {
      # Reachable only under unsafe_weight = TRUE; the gate above
      # refuses intermediates otherwise.
      cli::cli_warn(
        c(
          "{.val {weight}} is an intermediate stage of CDC's weighting
           pipeline, not a final analysis weight.",
          "x" = "Estimates weighted by it are not calibrated to CDC's
                 population totals.",
          "i" = "Module analyses that need a questionnaire-version
                 weight ({.val _LCPWTV1} to {.val _LCPWTV3}) require
                 CDC's separate version datasets, which this package
                 does not provide; see the {.emph Choosing a weight}
                 section of {.help brfssdata::brfss_design}."
        ),
        class = "brfssdata_intermediate_weight_warning"
      )
    } else if (!toupper(weight) %in% toupper(FINAL_WEIGHTS$weight)) {
      # Also unsafe_weight-only: a column that is neither a final
      # analysis weight nor a known pipeline stage.
      cli::cli_warn(
        c(
          "Weighting by {.val {weight}}, which is not a CDC final
           analysis weight.",
          "x" = "Estimates are calibrated to nothing; treat them as
                 exploratory."
        ),
        class = "brfssdata_unsafe_weight_warning"
      )
    }
    weight_vars <- weight
  } else {
    weight_vars <- auto_weights
  }
  design_vars <- c(weight_vars, DESIGN_STRATA, DESIGN_PSU)

  # Requested analysis variables, canonical case, minus everything that
  # is a design column or a weight: what the confinement check judges.
  if (!is.null(vars)) {
    warn_module_weight_confinement(
      years,
      setdiff(
        match_vars_ci(vars, names(dat)),
        c(design_vars, LABEL_EXCLUDE)
      ),
      effective_weights = weight_vars
    )
  }

  missing_cols <- setdiff(design_vars, names(dat))
  if (length(missing_cols) > 0) {
    # union_by_name keeps a column present in any year, so reaching here
    # means the column exists in none of them.
    cli::cli_abort(
      c(
        "Design variable{?s} {.val {missing_cols}} {?is/are} missing from
         every requested year.",
        "x" = "Years requested: {summarize_years(years)}.",
        "i" = "Each year needs its era weight, {.val {DESIGN_STRATA}},
               and {.val {DESIGN_PSU}}; this points at a damaged file or
               an upstream data problem worth reporting."
      ),
      class = "brfssdata_bad_design_var"
    )
  }

  if (!is.null(weight)) {
    # A year that lacks the column entirely comes back all-NA under
    # union_by_name; that means the weight does not exist in that year
    # (e.g. _LLCPWT2 is absent from 2015).
    na_by_year <- vapply(
      split(is.na(dat[[weight]]), dat$year),
      all,
      logical(1)
    )
    absent_years <- as.integer(names(na_by_year))[na_by_year]
    if (length(absent_years) > 0) {
      cli::cli_abort(
        c(
          "Weight {.val {requested_weight}} is not present in every
           requested year.",
          "x" = "Missing from year{?s}:
                 {.val {as.character(absent_years)}}.",
          "i" = "Use {.fun brfss_vars} to check availability, or request
                 only the years that carry it."
        ),
        class = "brfssdata_bad_weight"
      )
    }
    # A user-supplied DOMAIN weight defines its analytic domain: a
    # module weight such as _CLLCPWT exists only for the records its
    # module applies to (completed child interviews there), so in the
    # real files most rows carry NA. Those rows cannot enter this
    # design and are dropped, which is CDC's own module-analysis
    # guidance (subset to the module's records). An explicitly named
    # FULL-SAMPLE weight (_FINALWT, _LLCPWT) gets the same treatment as
    # the automatic era weight instead: it must cover every respondent,
    # so a missing value means a damaged file and falls through to the
    # missing-final-weight abort further down, identically to the
    # automatic path. Unsafe weights subset like domain weights.
    full_sample <- isTRUE(
      FINAL_WEIGHTS$full_sample[match(weight, FINAL_WEIGHTS$weight)]
    )
    drop <- if (full_sample) FALSE else is.na(dat[[weight]])
    if (any(drop)) {
      # Not gated on quiet: the design now estimates a different
      # population, which is an analytical signal, not progress output.
      # Silence it by class.
      n_total <- nrow(dat)
      n_drop <- sum(drop)
      by_year <- table(dat$year[drop])
      drop_txt <- paste(
        sprintf("%s: %s", names(by_year), unname(by_year)),
        collapse = "; "
      )
      cli::cli_inform(
        c(
          "i" = "{.val {weight}} covers {n_total - n_drop} of {n_total}
                 rows; dropping the {n_drop} row{?s} where it is
                 missing ({drop_txt}).",
          "i" = "A module weight exists only for the records its
                 module applies to; subsetting to them matches CDC's
                 module-analysis guidance. Omit {.arg weight} for the
                 full-sample era weight."
        ),
        class = "brfssdata_weight_subset_note"
      )
      dat <- dat[!drop, , drop = FALSE]
    }
    wt <- dat[[weight]]
    # A survey weight must be a positive, finite number. Checked on the
    # explicit path only, after the domain subset so only in-domain
    # rows are judged; the automatic era weight keeps its NA-only abort
    # below, because a hosted year with a legitimate edge value must
    # not start failing on a guess (spot checks found none, but 10 of
    # 40 years is not proof).
    bad_vals <- !is.na(wt) & (!is.finite(wt) | wt <= 0)
    if (any(bad_vals)) {
      n_bad <- sum(bad_vals)
      bad_years <- sort(unique(dat$year[bad_vals]))
      if (toupper(weight) %in% toupper(FINAL_WEIGHTS$weight)) {
        cli::cli_abort(
          c(
            "Weight {.val {weight}} has {n_bad} value{?s} that
             {?is/are} zero, negative, or not finite.",
            "x" = "Affected year{?s}: {.val {as.character(bad_years)}}.",
            "i" = "A final analysis weight is strictly positive; this
                   points at a damaged file. Clear and re-download it
                   with {.fun brfss_cache_clear}."
          ),
          class = "brfssdata_bad_design_var"
        )
      }
      cli::cli_abort(
        c(
          "Weight {.val {weight}} has {n_bad} value{?s} that
           {?is/are} zero, negative, or not finite.",
          "x" = "Affected year{?s}: {.val {as.character(bad_years)}}.",
          "i" = "A survey weight must be a positive, finite number;
                 {.val {weight}} cannot weight a design."
        ),
        class = "brfssdata_bad_weight"
      )
    }
  } else if (spans_break) {
    wt <- ifelse(
      dat$year >= BREAK_YEAR,
      dat[[WEIGHT_POST]],
      dat[[WEIGHT_PRE]]
    )
  } else {
    wt <- dat[[weight_vars]]
  }

  # First point where the row count is final: both the states filter
  # (read_brfss() returns zero rows when no requested jurisdiction
  # reported in any requested year) and the weight-domain subset above
  # have run. Every guard below is an any() over a logical vector, and
  # any(logical(0)) is FALSE, so none of them fires on an empty frame;
  # survey would then die inside split.default() with the bare
  # "group length is 0 but data length > 0". A zero-row tibble is a
  # usable answer, which is why read_brfss() still returns one, but a
  # zero-row survey design is not constructible at all.
  if (nrow(dat) == 0) {
    cli::cli_abort(
      c(
        "No rows are left to build a survey design for
         {summarize_years(years)}.",
        if (!is.null(states)) {
          c(
            "x" = "Requested jurisdiction{?s} {.val {as.character(states)}}
                   {?has/have} no records there."
          )
        },
        if (!is.null(weight)) {
          c(
            "x" = "The design is confined to the rows {.val {weight}}
                   covers."
          )
        },
        "i" = "A survey design needs at least one weighted record. Call
               {.fun read_brfss} with the same arguments to see what the
               filters left."
      ),
      class = "brfssdata_no_eligible_rows"
    )
  }

  if (spans_break) {
    cli::cli_warn(
      c(
        "Pooling across the 2011 redesign: the two eras' weights are not
         on a common basis (post-stratified landline vs raked
         dual-frame).",
        "i" = "Interpret any trend across 2010/2011 with caution."
      ),
      class = "brfssdata_break_warning"
    )
  }

  if (pool_weights && length(years) > 1) {
    wt <- wt / length(years)
    warn_unequal_state_participation(
      years,
      states = resolve_states(states),
      weight = weight
    )
  }

  bad_wt <- is.na(wt)
  if (any(bad_wt)) {
    bad_years <- sort(unique(dat$year[bad_wt]))
    cli::cli_abort(
      c(
        "{sum(bad_wt)} respondent{?s} {?has/have} a missing final
         weight.",
        "x" = "Affected year{?s}: {.val {as.character(bad_years)}}.",
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
          "{sum(bad)} respondent{?s} {?has/have} a missing
           {.val {design_col}}.",
          "x" = "Affected year{?s}: {.val {as.character(bad_years)}}.",
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

  exclude_cols <- union(
    LABEL_EXCLUDE,
    c(design_vars, "brfss_wt", "brfss_psu", "brfss_strata", "year")
  )
  if (isTRUE(na)) {
    dat <- apply_missing_codes(
      dat,
      years,
      quiet = quiet,
      download = download,
      exclude = exclude_cols
    )
  }
  if (!is.null(labels_mode)) {
    dat <- apply_labels(
      dat,
      years,
      quiet = quiet,
      download = download,
      exclude = exclude_cols,
      how = labels_mode,
      na = isTRUE(na)
    )
  }

  # From 2001 on, BRFSS public-use files make each respondent their own
  # PSU, so small strata (and most subgroup analyses) contain single-PSU
  # strata that make variance estimation fail. "adjust" is standard
  # BRFSS practice. The survey package sets "fail" in .onLoad, so that
  # value cannot be told apart from "never set" and is treated as unset;
  # any other user-chosen value is respected, and the package option
  # brfssdata.lonely_psu wins over everything (it is the only way to
  # deliberately choose "fail"). identical() rather than %in%: a
  # malformed option of length != 1 would make `if` error with "the
  # condition has length > 1".
  pkg_lonely <- getOption("brfssdata.lonely_psu")
  if (!is.null(pkg_lonely)) {
    if (
      !is.character(pkg_lonely) ||
        length(pkg_lonely) != 1L ||
        is.na(pkg_lonely)
    ) {
      cli::cli_abort(
        "{.code options(brfssdata.lonely_psu)} must be a single string,
         e.g. \"adjust\", \"fail\", \"certainty\", \"remove\", or
         \"average\".",
        class = "brfssdata_bad_option"
      )
    }
    options(survey.lonely.psu = pkg_lonely)
  } else if (identical(getOption("survey.lonely.psu", "fail"), "fail")) {
    options(survey.lonely.psu = "adjust")
    cli::cli_inform(
      c(
        "i" = "Set {.code options(survey.lonely.psu = \"adjust\")} for
               single-PSU strata (standard BRFSS practice).",
        "i" = "Set that option yourself, or set
               {.code options(brfssdata.lonely_psu = ...)}, before
               calling {.fun brfss_design} to choose different handling."
      ),
      .frequency = "once",
      .frequency_id = "brfssdata_lonely_psu",
      class = "brfssdata_lonely_psu_note"
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

# Cached parquet paths for the requested years, existing files only.
# Shared by the two best-effort diagnostics below.
cached_year_paths <- function(years) {
  paths <- cache_path(year_asset(years))
  paths[file.exists(paths)]
}

# One aggregate query over cached year files, degrading to NULL on any
# error. Both diagnostics built on this are best-effort: a query
# failure must never turn a working design call into an error. The
# format string receives the bracketed file list as its only %s.
try_parquet_aggregate <- function(paths, sql_fmt) {
  tryCatch(
    {
      con <- duckdb_connect()
      on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
      files_sql <- paste0(
        "[",
        paste(quote_literal(paths), collapse = ", "),
        "]"
      )
      DBI::dbGetQuery(con, sprintf(sql_fmt, files_sql))
    },
    error = function(e) NULL
  )
}

# Dividing pooled weights by the year count treats every year as
# covering the same states. When participation differs, totals mix
# coverage; say so. One cheap columnar query over the already-cached
# files rather than the loaded frame, because the design usually
# carries only the requested analysis variables, not _STATE. Skipped
# silently when any file lacks _STATE (never true of real BRFSS years).
# With a states filter, only the requested states are compared: a state
# outside the filter cannot affect the pooled estimate.
# The query must see the same population the design does. A
# user-supplied weight subsets the design to that weight's domain
# above, so the same restriction is pushed into the query here; over
# the whole file instead, the diagnostic names states the design never
# contained and, worse, goes silent when the full-file state sets match
# while the domain sets differ (2022 plus 2023 under _CLLCPWT is
# exactly that shape). union_by_name yields NULL for a year that lacks
# the weight column, which correctly contributes no states; the
# absent-from-a-requested-year case already aborted further up.
warn_unequal_state_participation <- function(
  years,
  states = NULL,
  weight = NULL
) {
  paths <- cached_year_paths(years)
  if (length(paths) < 2) {
    return(invisible())
  }
  where_sql <- if (is.null(weight)) {
    ""
  } else {
    sprintf(" WHERE %s IS NOT NULL", quote_ident(weight))
  }
  q <- try_parquet_aggregate(
    paths,
    paste0(
      'SELECT year, "_STATE" AS state
       FROM read_parquet(%s, union_by_name = true)',
      where_sql,
      " GROUP BY 1, 2"
    )
  )
  sets <- if (is.null(q) || anyNA(q$state)) {
    NULL
  } else {
    if (!is.null(states)) {
      q <- q[q$state %in% states, , drop = FALSE]
    }
    lapply(split(q$state, q$year), function(s) sort(unique(s)))
  }
  if (is.null(sets) || length(sets) < 2) {
    return(invisible())
  }
  everywhere <- Reduce(intersect, sets)
  anywhere <- Reduce(union, sets)
  uneven <- sort(setdiff(anywhere, everywhere))
  if (length(uneven) == 0) {
    return(invisible())
  }
  cli::cli_warn(
    c(
      "State participation differs across the pooled years: state
       FIPS code{?s} {.val {as.character(uneven)}} {?does/do} not appear
       in every year.",
      if (!is.null(weight)) {
        c(
          "i" = "Counted over the rows {.val {weight}} covers, the
                 population this design estimates, not the whole file."
        )
      },
      "i" = "Pooled totals average over changing state coverage; filter
             to the common states, or set {.code pool_weights = FALSE}
             and estimate per year, if that matters for your analysis."
    ),
    class = "brfssdata_pooled_states_warning"
  )
}

# A requested variable answered almost only where a domain weight is
# non-missing is very likely a module analysis running under the wrong
# weight: 2023 child asthma (CASTHDX2) sits 99.7% inside _CLLCPWT's
# domain, while a core variable sits at the domain's 11.4% base rate.
# The review measured the cost of missing this at half a point of
# prevalence with no signal. One aggregate over the cached files,
# because when vars is supplied the candidate weight columns are not in
# the loaded frame. Warns, never errors: state-optional modules that
# CDC assigns to the core weight produce the same confinement shape,
# and only CDC's annual module documentation settles those. Thresholds:
# flagged when every requested year with any data is >= 95% confined
# (99.7% observed against an 11.4% base rate leaves a wide corridor);
# skipped when the candidate's domain covers > 95% of any year's file,
# because a degenerate domain separates nothing. A year predating the
# candidate weight contributes zero confinement, so cross-era pools
# never warn. State-free rather than once-per-session, so tests stay
# order-independent; degrades silently on any query failure, like the
# participation diagnostic above.
warn_module_weight_confinement <- function(years, vars, effective_weights) {
  check <- getOption("brfssdata.module_weight_check")
  if (!is.null(check)) {
    if (!isTRUE(check) && !isFALSE(check)) {
      cli::cli_abort(
        "{.code options(brfssdata.module_weight_check)} must be TRUE or
         FALSE; see {.help brfssdata::brfss_design}.",
        class = "brfssdata_bad_option"
      )
    }
    if (isFALSE(check)) {
      return(invisible())
    }
  }
  if (length(vars) == 0) {
    return(invisible())
  }
  domain <- FINAL_WEIGHTS[!FINAL_WEIGHTS$full_sample, , drop = FALSE]
  active <- vapply(
    seq_len(nrow(domain)),
    function(i) {
      hi <- domain$last_year[[i]]
      any(years >= domain$first_year[[i]] & (is.na(hi) | years <= hi))
    },
    logical(1)
  )
  candidates <- setdiff(domain$weight[active], toupper(effective_weights))
  if (length(candidates) == 0) {
    return(invisible())
  }
  paths <- cached_year_paths(years)
  if (length(paths) == 0) {
    return(invisible())
  }
  sel <- c("year", "count(*) AS n_total")
  for (i in seq_along(candidates)) {
    sel <- c(
      sel,
      sprintf("count(%s) AS w_%d", quote_ident(candidates[[i]]), i)
    )
  }
  for (j in seq_along(vars)) {
    sel <- c(sel, sprintf("count(%s) AS v_%d", quote_ident(vars[[j]]), j))
    for (i in seq_along(candidates)) {
      sel <- c(
        sel,
        sprintf(
          "count(*) FILTER (%s IS NOT NULL AND %s IS NOT NULL) AS vw_%d_%d",
          quote_ident(vars[[j]]),
          quote_ident(candidates[[i]]),
          j,
          i
        )
      )
    }
  }
  q <- try_parquet_aggregate(
    paths,
    paste0(
      "SELECT ",
      paste(sel, collapse = ", "),
      " FROM read_parquet(%s, union_by_name = true) GROUP BY year"
    )
  )
  if (is.null(q) || nrow(q) == 0) {
    return(invisible())
  }
  for (i in seq_along(candidates)) {
    n_w <- q[[sprintf("w_%d", i)]]
    if (any(n_w / q$n_total > 0.95)) {
      next
    }
    flagged <- character(0)
    min_pct <- 100
    for (j in seq_along(vars)) {
      n_v <- q[[sprintf("v_%d", j)]]
      if (all(n_v == 0)) {
        next
      }
      n_vw <- q[[sprintf("vw_%d_%d", j, i)]]
      ratio <- n_vw[n_v > 0] / n_v[n_v > 0]
      if (all(ratio >= 0.95)) {
        flagged <- c(flagged, vars[[j]])
        min_pct <- min(min_pct, floor(100 * min(ratio)))
      }
    }
    if (length(flagged) == 0) {
      next
    }
    w <- candidates[[i]]
    n_flag <- length(flagged)
    cli::cli_warn(
      c(
        "{cli::qty(n_flag)}Variable{?s} {.val {flagged}}
         {cli::qty(n_flag)}{?has/have} data almost only where the
         {.val {w}} module weight does (at least {min_pct}% of
         nonmissing responses in every requested year).",
        "x" = "This design uses {.val {effective_weights}}, which
               covers the full sample, not the module's records.",
        "i" = "If this is a {.val {w}} module analysis, pass
               {.code weight = \"{w}\"}. State-optional modules that
               CDC assigns to the core weight are the exception, which
               is why this warns instead of failing.",
        "i" = "Disable the check with
               {.code options(brfssdata.module_weight_check = FALSE)}."
      ),
      class = "brfssdata_module_weight_warning"
    )
  }
  invisible()
}
