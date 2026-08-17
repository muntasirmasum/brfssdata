#' Build a survey-design object for BRFSS analysis
#'
#' @description
#' Returns a [srvyr::as_survey_design()] `tbl_svy` with the complex sampling
#' design applied: the year-appropriate final weight, strata (`_STSTR`),
#' and the primary sampling units (`_PSU`) in the years where those
#' identify a real cluster. From 2001 on they do not, and the design says
#' so when it is built; see *Why some years have no PSU term*, which also
#' shows that the standard errors are unchanged either way.
#' Weight selection is automatic:
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
#' the build. A user-supplied weight is used for every requested year,
#' and pooling divides by the contributing-year count described below.
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
#' document with each annual release; check a year-over-year shift
#' there before reading it as a change in the population.
#'
#' When several years are combined, weights are divided by the number of
#' years (`pool_weights = TRUE`, the default) so that pooled estimates
#' represent an average year rather than a sum of populations, and the
#' variance strata become the year-by-stratum interaction, treating each
#' annual survey as an independent sample. The divisor counts the years
#' that actually contribute rows, not the years requested: a `states` or
#' `weight` filter can empty a year (Kentucky collected no 2023 data, so
#' `states = "KY"` over `2022:2023` is a 2022-only design), and dividing
#' that by the requested count would halve every total while leaving
#' means and proportions untouched, since the constant cancels there. A
#' `brfssdata_empty_year_warning` names any year that contributed
#' nothing, so an average over fewer years is not read as covering all
#' of them. The pooled estimate averages over the states participating
#' each year; when participation differs across the pooled years, totals
#' mix coverage, and a warning says so.
#'
#' @section Why some years have no PSU term:
#' A design built for 2001 or later prints `ids: 1`, which reads as if
#' the primary sampling units had been dropped. They have not been
#' ignored; from 2001 on there is nothing for them to say.
#'
#' From 2001 on, `_PSU` is a record sequence number that restarts in
#' each state, so it repeats across the file but is unique within a
#' stratum: every stratum-by-PSU cell holds exactly one respondent.
#' Single-PSU strata are therefore common and would make variance
#' estimation fail. When the design just built carries at least one of
#' them and `options(survey.lonely.psu)` is unset, this function sets it
#' to `"adjust"` (standard BRFSS practice) and says so once per session.
#' A design with no such stratum (1995 and 2003 have none, 2023 has 101)
#' leaves the option alone, so an unrelated survey analysis later in the
#' session keeps survey's own fail-fast default. Any value you set other
#' than `"fail"` is respected; `"fail"` is what the survey package
#' itself installs on load, so it cannot be told apart from "never set"
#' and is treated as unset. To insist on `"fail"`, or to pin any
#' handling, set `options(brfssdata.lonely_psu = ...)`, which is copied
#' into `survey.lonely.psu` unconditionally. The option stays set for
#' the session because survey consults it at estimation time, not design
#' time.
#'
#' Because that clustering is nominal, the design for those years is
#' built without a cluster term, which gives the same estimates, standard
#' errors, and degrees of freedom far faster than carrying a cluster
#' factor with one level per respondent. On the 2023 file, fair-or-poor
#' `GENHLTH` returns 0.193696115777860 with a standard error of
#' 0.001389477801364 whether the cluster term is supplied or not, to the
#' last bit of a double, and both designs report 431,177 degrees of
#' freedom. Files through 2000 carry genuine multi-respondent PSUs and
#' keep the clustered estimator, nested within stratum because the
#' identifiers are reused, and there the two specifications do differ:
#' the same estimate on 1995 has a standard error of 0.001830302439388
#' with the cluster term against 0.001826985014850 without it, on 61,230
#' degrees of freedom rather than 113,870. The choice is from the data, so it
#' follows the file rather than the year.
#'
#' The design object itself prints only srvyr's syntactic column names,
#' which say nothing about which CDC weight was chosen. The build
#' therefore states the specification in `svyset` terms, naming the
#' weight, the stratum column, and whether a cluster term applies
#' (`brfssdata_design_spec_note`, suppressed by `quiet = TRUE`).
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
#'   divide each weight by the number of years that contributed rows,
#'   which a `states` filter or the domain of a user-supplied `weight`
#'   can make smaller than the number requested (see Details).
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
#' @seealso [read_brfss()] for the underlying data;
#'   [brfssdata-options] for the session options
#'   (`brfssdata.lonely_psu`, `brfssdata.module_weight_check`) this
#'   function consults.
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
  # Every TRUE/FALSE formal is checked before anything is downloaded or
  # read. Left to the branches that consume them, allow_break and
  # pool_weights die inside base R's `&&` with "invalid argument type"
  # and no argument name, and a pool_weights of NA is accepted outright.
  # download is checked first because validate_years() consumes it.
  check_bool_arg(download, "download")
  check_bool_arg(quiet, "quiet")
  check_bool_arg(unsafe_weight, "unsafe_weight")
  check_bool_arg(allow_break, "allow_break")
  check_bool_arg(pool_weights, "pool_weights")
  check_bool_arg(na, "na")
  # Both session options are readable here too, so a mistyped one in a
  # .Rprofile fails now rather than after a multi-year download, read,
  # and missing-code recode.
  pkg_lonely <- validate_lonely_psu_option()
  validate_module_weight_check_option()
  years <- validate_years(years, download = download, quiet = quiet)
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

  # The design columns are injected into vars, and the read path reports
  # any column it cannot find as brfssdata_bad_var, whose remedy is the
  # variable search. That is the wrong advice for an injected column:
  # its absence means a damaged or foreign cached file, which is what
  # brfssdata_bad_design_var is documented for. The condition does not
  # carry which column was missing, so the handler asks the files.
  injected <- c(weight %||% auto_weights, DESIGN_STRATA, DESIGN_PSU)
  # A weight the caller named is not an injected column for this
  # purpose, whatever it is called. `_LLCPWT2` exists in 2014 and 2016
  # but not 2015, and calling that year's pristine file damaged sends
  # the user to delete 33 MB and download an identical copy. Only the
  # columns brfss_design() adds on its own can indict the file.
  design_only <- if (is.null(weight)) {
    injected
  } else {
    setdiff(injected, weight)
  }
  design_call <- rlang::current_env()
  dat <- tryCatch(
    read_brfss(
      years,
      vars = if (is.null(vars)) NULL else union(vars, injected),
      states = states,
      download = download,
      quiet = quiet
    ),
    brfssdata_bad_var = function(cnd) {
      rethrow_missing_design_var(cnd, years, design_only, call = design_call)
    }
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
    # A year that comes back all-NA under union_by_name has two
    # explanations with opposite remedies: the year's file lacks the
    # column entirely (the weight does not exist in that year, e.g.
    # _LLCPWT2 is absent from 2015), or the file carries it and the
    # request's filters emptied its domain (states opt in and out of
    # modules by year, so a states filter can leave a module weight
    # with nothing). The frame cannot tell the two apart; the year's
    # own file schema can. Only the first is an error. The second is
    # the documented empty-domain route: the subset below drops the
    # rows, and the contributing-years machinery names the year.
    na_by_year <- vapply(
      split(is.na(dat[[weight]]), dat$year),
      all,
      logical(1)
    )
    absent_years <- as.integer(names(na_by_year))[na_by_year]
    if (length(absent_years) > 0) {
      in_file <- vapply(
        absent_years,
        function(y) {
          schema <- try_parquet_aggregate(
            cache_path(year_asset(y)),
            "DESCRIBE SELECT * FROM read_parquet(%s)"
          )
          # A failed probe keeps the abort: refusing a request is
          # recoverable, silently serving a design the caller was told
          # is impossible is not.
          !is.null(schema) &&
            toupper(weight) %in% toupper(schema$column_name)
        },
        logical(1)
      )
      file_absent <- absent_years[!in_file]
      if (length(file_absent) > 0) {
        cli::cli_abort(
          c(
            "Weight {.val {requested_weight}} is not present in every
             requested year.",
            "x" = "Missing from year{?s}:
                   {.val {as.character(file_absent)}}.",
            "i" = "Use {.fun brfss_vars} to check availability, or
                   request only the years that carry it."
          ),
          class = "brfssdata_bad_weight"
        )
      }
    }
    check_weight_numeric(dat, weight)
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
      # CDC's module-analysis guidance is about CDC's own domain
      # weights, so it is cited only for one of those. An unsafe weight
      # gets the same subset with no borrowed authority behind it.
      recognized <- toupper(weight) %in% toupper(FINAL_WEIGHTS$weight)
      cli::cli_inform(
        c(
          "i" = "{.val {weight}} covers {n_total - n_drop} of {n_total}
                 rows; dropping the {n_drop} row{?s} where it is
                 missing ({drop_txt}).",
          "i" = if (recognized) {
            "A module weight exists only for the records its module
             applies to; subsetting to them matches CDC's
             module-analysis guidance. Omit {.arg weight} for the
             full-sample era weight."
          } else {
            "A row with no weight cannot enter a design; the estimate
             covers the rows {.val {weight}} does cover. Omit
             {.arg weight} for the full-sample era weight."
          }
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
  } else {
    # The automatic path reaches the same trap the explicit one guards
    # against, and reaches it more often: a damaged file whose era
    # weight was cast to text is read by the default call, with no
    # weight argument at all, and used to die inside survey with a bare
    # "non-numeric argument to binary operator".
    for (col in weight_vars) {
      check_weight_numeric(dat, col)
    }
    wt <- if (spans_break) {
      ifelse(dat$year >= BREAK_YEAR, dat[[WEIGHT_POST]], dat[[WEIGHT_PRE]])
    } else {
      dat[[weight_vars]]
    }
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

  pool_divisor <- 1
  if (pool_weights && length(years) > 1) {
    # The divisor counts the years that contribute rows, not the years
    # requested. A requested year can contribute none (Kentucky
    # collected no 2023 data, so states = "KY" over 2022:2023 is a
    # 2022-only design), and dividing that by the requested count halves
    # every total while leaving means and proportions untouched, because
    # the constant cancels there: a total that estimates no population
    # at all. Dividing by the contributing count keeps the documented
    # meaning, an average contributing year, and the warning says which
    # years are absent so that average is not read as covering them.
    # Both halves are needed: the rescaling makes the number honest, the
    # warning makes the coverage visible.
    contributing <- sort(unique(dat$year))
    pool_divisor <- length(contributing)
    wt <- wt / pool_divisor
    empty_years <- setdiff(years, contributing)
    if (length(empty_years) > 0) {
      cli::cli_warn(
        c(
          "Requested year{?s} {.val {as.character(empty_years)}}
           contributed no rows to this pooled design.",
          "x" = "Pooled weights were divided by the
                 {cli::qty(pool_divisor)}{pool_divisor} contributing
                 year{?s} rather than the {length(years)} requested, so
                 totals estimate an average contributing year.",
          "i" = "A {.arg states} request a year has no records for, or a
                 {.arg weight} whose domain is empty there, is the usual
                 cause; request only the years that carry data to say so
                 explicitly."
        ),
        class = "brfssdata_empty_year_warning"
      )
    }
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
      exclude = exclude_cols,
      requested = if (is.null(vars)) {
        NULL
      } else {
        names(dat)[toupper(names(dat)) %in% toupper(vars)]
      }
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

  # From 2001 on, BRFSS public-use files make each respondent their own
  # PSU, so small strata contain single-PSU strata that make variance
  # estimation fail, and "adjust" is standard BRFSS practice. survey
  # reads survey.lonely.psu at estimation time, not design time, so the
  # value has to outlive this call: it is global state every later
  # analysis in the session inherits, and the package's own default is
  # therefore written only when the design just built actually carries
  # such a stratum (2023 has 101 of 2146; 1995 and 2003 have none).
  # Domain estimation cannot add one, because survey estimates a
  # subpopulation over the design's own PSUs. A pinned
  # brfssdata.lonely_psu is still copied unconditionally: pinning it is
  # the documented way to choose the handling for the session, and the
  # only way to choose "fail" deliberately. The survey package sets
  # "fail" in .onLoad, so that value cannot be told apart from "never
  # set" and is treated as unset; any other user-chosen value is
  # respected. identical() rather than %in%: a malformed option of
  # length != 1 would make `if` error with "the condition has length
  # > 1".
  if (!is.null(pkg_lonely)) {
    options(survey.lonely.psu = pkg_lonely)
  } else if (identical(getOption("survey.lonely.psu", "fail"), "fail")) {
    # The per-stratum tabulation walks every row and costs most of a
    # second on a pooled design, so it runs only while the option is
    # still unset and its answer can matter: a pinned option, or an
    # earlier call in the session having set "adjust", skips it.
    psu_per_stratum <- if (singleton_psus) {
      table(dat$brfss_strata)
    } else {
      tapply(dat$brfss_psu, dat$brfss_strata, function(p) length(unique(p)))
    }
    if (any(psu_per_stratum == 1)) {
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
  }

  # A design object prints srvyr's syntactic column names only ("ids: 1,
  # strata: brfss_strata, weights: brfss_wt"), so nothing in it says
  # which CDC weight was selected, that brfss_strata is _STSTR, or why
  # there is no PSU term. State the specification the way a Stata log
  # states it, so it can be cross-checked against a coauthor's svyset.
  if (!quiet) {
    strata_txt <- if (length(years) > 1) {
      paste0("year by ", DESIGN_STRATA)
    } else {
      DESIGN_STRATA
    }
    # One svyset line per weight: a single line naming two pweight
    # columns is not a specification Stata can state, and a cross-era
    # design weights each row by its own era's column.
    svyset_txt <- function(wt) {
      if (singleton_psus) {
        paste0("svyset [pw=", wt, "], strata(", strata_txt, ")")
      } else {
        paste0(
          "svyset ", DESIGN_PSU, " [pw=", wt, "], strata(", strata_txt, ")"
        )
      }
    }
    spec_lines <- if (length(weight_vars) > 1L) {
      c(
        "i" = paste0(
          "Design: {.code ", svyset_txt(weight_vars[[1L]]),
          "} for years before ", BREAK_YEAR, "."
        ),
        "i" = paste0(
          "Design: {.code ", svyset_txt(weight_vars[[2L]]),
          "} for ", BREAK_YEAR, " on."
        )
      )
    } else {
      c("i" = paste0("Design: {.code ", svyset_txt(weight_vars), "}."))
    }
    cli::cli_inform(
      c(
        spec_lines,
        if (singleton_psus) {
          c(
            "i" = "Each {DESIGN_STRATA}-by-{DESIGN_PSU} cell holds one
                   respondent, so the cluster term is omitted; standard
                   errors are identical."
          )
        },
        if (pool_divisor > 1) {
          c(
            "i" = "Pooled: each weight divided by {pool_divisor}, the
                   number of contributing years."
          )
        }
      ),
      class = "brfssdata_design_spec_note"
    )
  }

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

# Cached parquet paths for the requested years, existing files only,
# named by year. Shared by the two best-effort diagnostics below; the
# participation one needs the years its query could have seen, so that a
# year contributing nothing is an empty set rather than an absent one.
cached_year_paths <- function(years) {
  paths <- cache_path(year_asset(years))
  keep <- file.exists(paths)
  paths <- paths[keep]
  names(paths) <- years[keep]
  paths
}

# Several hosted columns are text (SEQNO is VARCHAR), and a text column
# reaches the positivity test as values that are none of zero, negative,
# or finite, which reports the wrong reason for a correct refusal. Named
# here instead, for the automatic era weight as well as a weight the
# caller chose: the default call is how a damaged file is usually met.
check_weight_numeric <- function(dat, weight, call = rlang::caller_env()) {
  if (is.numeric(dat[[weight]])) {
    return(invisible())
  }
  is_final <- toupper(weight) %in% toupper(FINAL_WEIGHTS$weight)
  cli::cli_abort(
    c(
      "Weight {.val {weight}} is {.obj_type_friendly {dat[[weight]]}},
       not a numeric column.",
      "i" = if (is_final) {
        "A final analysis weight is stored as a number; this points
         at a damaged file. Clear and re-download it with
         {.fun brfss_cache_clear}."
      } else {
        "A survey weight must be a positive, finite number;
         {.val {weight}} cannot weight a design."
      }
    ),
    class = if (is_final) "brfssdata_bad_design_var" else "brfssdata_bad_weight",
    call = call
  )
}

# The two session options this function honors, validated on demand so
# the eager block at the top of brfss_design() can fail on a mistyped
# .Rprofile value before anything is downloaded. Each returns the value
# so its consumer re-reads nothing.
validate_lonely_psu_option <- function(call = rlang::caller_env()) {
  value <- getOption("brfssdata.lonely_psu")
  if (is.null(value)) {
    return(NULL)
  }
  if (!is.character(value) || length(value) != 1L || is.na(value)) {
    cli::cli_abort(
      "{.code options(brfssdata.lonely_psu)} must be a single string,
       e.g. \"adjust\", \"fail\", \"certainty\", \"remove\", or
       \"average\".",
      class = "brfssdata_bad_option",
      call = call
    )
  }
  value
}

validate_module_weight_check_option <- function(call = rlang::caller_env()) {
  value <- getOption("brfssdata.module_weight_check")
  if (is.null(value)) {
    return(NULL)
  }
  if (!isTRUE(value) && !isFALSE(value)) {
    cli::cli_abort(
      "{.code options(brfssdata.module_weight_check)} must be TRUE or
       FALSE; see {.help brfssdata::brfss_design}.",
      class = "brfssdata_bad_option",
      call = call
    )
  }
  value
}

# Decide whether a brfssdata_bad_var raised by the read path was about
# a design column brfss_design() injected or about a variable the user
# asked for. The read path names its missing variables on the
# condition, and that answer is authoritative: a set containing any
# user-requested variable re-signals unchanged, typo hints intact,
# because fixing the request comes before any verdict on the files.
# The old probe of whatever files happened to be cached stays only as
# the fallback for a nameless condition (not signaled by this
# package's read path), and rewrites only when the schema confirms a
# design column is really gone; it cannot tell a pristine
# one-era-cached file from a damaged one, which is why the names win.
rethrow_missing_design_var <- function(
  cnd,
  years,
  design_cols,
  call = rlang::caller_env()
) {
  named <- cnd$missing_vars
  if (!is.null(named)) {
    if (any(!toupper(named) %in% toupper(design_cols))) {
      stop(cnd)
    }
    absent <- named
  } else {
    paths <- cached_year_paths(years)
    schema <- if (length(paths) == 0) {
      NULL
    } else {
      try_parquet_aggregate(
        paths,
        "DESCRIBE SELECT * FROM read_parquet(%s, union_by_name = true)"
      )
    }
    absent <- if (is.null(schema)) {
      character(0)
    } else {
      design_cols[!toupper(design_cols) %in% toupper(schema$column_name)]
    }
    if (length(absent) == 0) {
      stop(cnd)
    }
  }
  cli::cli_abort(
    c(
      "Design variable{?s} {.val {absent}} {?is/are} missing from the
       cached files.",
      "x" = "Years requested: {summarize_years(years)}.",
      "x" = "Each year needs its era weight, {.val {DESIGN_STRATA}}, and
             {.val {DESIGN_PSU}}.",
      "i" = "A cached file without one was not built by this package, or
             was damaged after it was. Clear the year with
             {.fun brfss_cache_clear} and read it again."
    ),
    class = "brfssdata_bad_design_var",
    call = call
  )
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
  # Split over every year the query could see, not over the years it
  # returned rows for: a year where no requested state reported
  # (Kentucky collected no 2023 data) otherwise yields a single year-set
  # and returns silently below, which is exactly the case that most
  # needs saying.
  sets <- if (is.null(q) || anyNA(q$state)) {
    NULL
  } else {
    if (!is.null(states)) {
      q <- q[q$state %in% states, , drop = FALSE]
    }
    lapply(
      split(q$state, factor(q$year, levels = names(paths))),
      function(s) sort(unique(s))
    )
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
  # Postal abbreviations, like the state-coverage warning read_brfss()
  # raises, with the code kept for the jurisdictions that have no
  # abbreviation in brfss_states.
  abbr <- brfss_states$abbr[match(uneven, brfss_states$fips)]
  named <- ifelse(
    is.na(abbr),
    sprintf("FIPS %s", uneven),
    sprintf("%s (FIPS %s)", abbr, uneven)
  )
  cli::cli_warn(
    c(
      "State participation differs across the pooled years:
       {.val {named}} {?does/do} not appear in every year.",
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
  if (isFALSE(validate_module_weight_check_option())) {
    return(invisible())
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
