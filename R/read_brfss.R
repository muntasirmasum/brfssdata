#' Read BRFSS survey microdata
#'
#' @description
#' Returns respondent-level BRFSS data for one or more survey years as a
#' tibble. Each requested year is downloaded once into the local cache
#' (see [brfss_cache_dir()]) and read from there afterwards; the query
#' itself runs through DuckDB, so selecting a handful of variables from a
#' 300-plus column survey stays fast. Cached files are re-verified
#' against the manifest's checksums at most once a day per session; a
#' file that no longer matches is announced and re-downloaded verified.
#' With `download = FALSE` no file is checked, downloaded, or deleted.
#'
#' Different survey years carry different variable sets. When years are
#' combined, variables absent from a year are filled with `NA`. A `year`
#' column always identifies the survey year of each row.
#'
#' @param years Integer vector of survey years, e.g. `2023` or
#'   `2019:2023`. See [brfss_years()] for what is available.
#' @param vars Optional character vector of variable names to return.
#'   The default returns every variable. Names are matched
#'   case-insensitively (`"genhlth"` finds `GENHLTH`), and returned
#'   columns always carry CDC's canonical spelling. Use [brfss_vars()]
#'   to search names across years.
#' @param states Optional vector restricting rows to those reporting
#'   jurisdictions: state FIPS codes, postal abbreviations, or names,
#'   mixed freely and matched case-insensitively (`c(48, "CA",
#'   "maine")`). See [brfss_states] for the full list. The filter is
#'   pushed into the DuckDB query, so other states' rows never reach R,
#'   and the `_STATE` column is always returned so the filter stays
#'   visible. A requested state absent from a requested year's file
#'   (states do occasionally miss a year) raises a classed warning
#'   rather than returning silently fewer rows.
#' @param download If `FALSE`, only cached years are used and missing
#'   years raise an error instead of being downloaded.
#' @param quiet If `TRUE`, suppress progress and housekeeping output:
#'   download progress, cache notes, the full-load hint, and the
#'   `na = TRUE` recode tally. Notes and warnings about what the data
#'   mean (renames, missing-code coverage, weight-domain subsetting)
#'   signal regardless of `quiet`; silence a specific one by its class,
#'   e.g. `suppressMessages(..., classes = "brfssdata_rename_note")`.
#'   See [brfssdata-conditions] for every class.
#' @param labels Controls value-label conversion via CDC's format
#'   libraries (available from 1998 on). `FALSE` (the default) keeps
#'   every numeric code. `TRUE` converts variables with safe maps to
#'   factors; note the conversion is lossy: the CDC codes are gone, and
#'   `as.numeric()` on the result returns factor level positions, not
#'   codes (most CDC code sets are non-contiguous, so the two disagree).
#'   `"both"` keeps the code in the level text (`"[1] Excellent"`) so it
#'   stays recoverable. A variable converts only when its format is a
#'   pure code-to-label map, its code set agrees across the requested
#'   years, every observed value is covered, and its label wording did
#'   not change meaning across those years; everything else keeps its
#'   numeric codes. Wording that did change (CDC reused `COLNTES1`
#'   codes 3 to 5 for different screening intervals from 2022 on) keeps
#'   its codes too, with a `brfssdata_label_drift_warning` naming the
#'   variables; read those years separately if you want each year's own
#'   wording. Levels come from the newest requested year, so purely
#'   cosmetic rewording is shown in CDC's most recent phrasing.
#'   Identifier and design columns (`_STATE`, the
#'   weights, strata, and PSU) always keep numeric codes so filters like
#'   `_STATE == 6` keep working. See [brfss_labels()] for the catalog.
#' @param na If `TRUE`, set the codes CDC uses for missing-type answers
#'   (don't know / not sure, refused, not asked) to `NA`, using the
#'   value-label catalog; see [brfss_missing_codes()] for exactly which
#'   codes. The default here is `FALSE`: `read_brfss()` returns the file
#'   as CDC published it. ([brfss_design()] defaults to `TRUE`, because
#'   estimates over raw codes are almost never what an analyst wants.)
#'   Code 88/888 ("None") means zero, is never touched, and needs
#'   recoding to 0 by hand before averaging count variables. Labels
#'   cover 1998 on, so earlier years pass through unchanged and say so
#'   with a `brfssdata_na_coverage_warning` warning; a request touching
#'   a year the catalog covers only partially (like 1998) raises a
#'   `brfssdata_na_coverage_note` message rather than staying silent.
#'
#' @return A tibble with one row per respondent and a `year` column.
#'
#' @examplesIf interactive()
#' # General health and design variables for two years
#' dat <- read_brfss(2022:2023, vars = c("GENHLTH", "_LLCPWT"))
#' @seealso [brfss_design()] to get a survey-design object instead of a
#'   plain tibble; [brfssdata-conditions] for the classes of every error,
#'   warning, and message this package signals.
#' @export
read_brfss <- function(
  years,
  vars = NULL,
  states = NULL,
  download = TRUE,
  quiet = FALSE,
  labels = FALSE,
  na = FALSE
) {
  years <- validate_years(years, download = download)
  if (
    !is.null(vars) &&
      (!is.character(vars) || anyNA(vars) || length(vars) == 0)
  ) {
    cli::cli_abort(
      c(
        "{.arg vars} must be a character vector of variable names.",
        "x" = "Got {.obj_type_friendly {vars}}."
      ),
      class = "brfssdata_bad_vars_arg"
    )
  }
  if (!isTRUE(na) && !isFALSE(na)) {
    cli::cli_abort(
      "{.arg na} must be TRUE or FALSE.",
      class = "brfssdata_bad_na_arg"
    )
  }
  states <- resolve_states(states)
  # Validated eagerly: passed lazily, an invalid labels value would only
  # surface if some variable actually converted.
  labels_mode <- if (isFALSE(labels)) NULL else labels_how(labels)
  # Modern years are 350-plus columns wide, so the default selection
  # materializes about 1.1 GB for 2023 alone. Said before anything is
  # downloaded or read, while narrowing the request still helps.
  if (is.null(vars) && !quiet) {
    cli::cli_inform(
      c(
        "i" = "Loading every column for {summarize_years(years)}; pass
               {.code vars = c(...)} to carry only analysis variables
               (faster, much smaller)."
      ),
      class = "brfssdata_full_load_note"
    )
  }
  # A typo'd variable should not cost a year download (a modern year is
  # 20-30 MB). Only when a download would actually happen: under
  # download = FALSE a missing year must keep its brfssdata_not_cached
  # error, and for fully cached requests query_parquet() stays the sole
  # authority on which columns exist.
  if (
    !is.null(vars) &&
      download &&
      !all(file.exists(cache_path(year_asset(years))))
  ) {
    check_vars_before_download(vars, years)
  }
  paths <- ensure_years_cached(years, download = download, quiet = quiet)
  dat <- query_parquet(
    paths,
    # The filter column always rides along so the subset stays visible.
    vars = if (is.null(vars) || is.null(states)) vars else union(vars, "_STATE"),
    states = states
  )
  warn_state_coverage(dat, years, states)
  # No rename note under a states filter: a module a filtered state
  # did not field would look identical to a rename (all-NA in a year a
  # sibling covers), and a confidently wrong note is worse than none.
  if (is.null(states)) {
    note_renames(dat, vars, years)
  }
  if (isTRUE(na)) {
    dat <- apply_missing_codes(
      dat,
      years,
      quiet = quiet,
      download = download,
      exclude = LABEL_EXCLUDE
    )
  }
  if (!is.null(labels_mode)) {
    dat <- apply_labels(
      dat,
      years,
      quiet = quiet,
      download = download,
      exclude = LABEL_EXCLUDE,
      how = labels_mode,
      na = isTRUE(na)
    )
  }
  dat
}

# A requested state can be genuinely absent from a year (Kentucky and
# Pennsylvania collected no 2023 data), and a states filter that
# silently returns fewer rows than the request implies would be read as
# "smaller sample", not "missing state". Warn, naming year and state.
warn_state_coverage <- function(dat, years, states) {
  if (is.null(states) || !"_STATE" %in% names(dat)) {
    return(invisible())
  }
  gaps <- character(0)
  for (y in years) {
    present <- unique(dat[["_STATE"]][dat$year == y])
    absent <- setdiff(states, present)
    if (length(absent) > 0) {
      labels <- brfss_states$abbr[match(absent, brfss_states$fips)]
      labels[is.na(labels)] <- as.character(absent[is.na(labels)])
      gaps <- c(gaps, sprintf("%d: %s", y, paste(labels, collapse = ", ")))
    }
  }
  if (length(gaps) == 0) {
    return(invisible())
  }
  gaps_txt <- paste(gaps, collapse = "; ")
  cli::cli_warn(
    c(
      "Requested states are absent from some requested years:
       {gaps_txt}.",
      "i" = "States occasionally collect no data in a year (Kentucky
             and Pennsylvania in 2023, for example); estimates for
             affected years cover the remaining requested states only."
    ),
    class = "brfssdata_state_coverage_warning"
  )
}

# When a requested variable is entirely NA in a requested year AND a
# sibling generation from the rename crosswalk covers that year, the
# user is almost certainly stepping into CDC's trailing-digit rename
# (_DRNKWK1 -> _DRNKWK2 -> _DRNKWK3). Say so. Consults only a cached or
# bundled crosswalk -- never the network -- because the read path's
# offline contract must hold. Deliberately not gated on quiet: this is
# an analytical signal, not progress output; silence it by class.
note_renames <- function(dat, vars, years) {
  if (is.null(vars)) {
    return(invisible())
  }
  xwalk <- crosswalk_catalog_offline()
  if (is.null(xwalk) || nrow(xwalk) == 0) {
    return(invisible())
  }
  requested <- setdiff(intersect(names(dat), xwalk$variable), "year")
  bullets <- character(0)
  for (v in requested) {
    concept <- xwalk$concept[xwalk$variable == v][[1]]
    fam <- xwalk[xwalk$concept == concept, , drop = FALSE]
    empty_years <- integer(0)
    for (y in years) {
      rows <- dat$year == y
      if (any(rows) && all(is.na(dat[[v]][rows]))) {
        empty_years <- c(empty_years, y)
      }
    }
    if (length(empty_years) == 0) {
      next
    }
    sib <- fam[fam$variable != v & fam$year %in% empty_years, , drop = FALSE]
    if (nrow(sib) == 0) {
      next
    }
    sib_txt <- vapply(
      split(sib$year, sib$variable),
      summarize_years,
      character(1)
    )
    bullets <- c(
      bullets,
      sprintf(
        "%s has no data for %s; the rename crosswalk pairs it with %s.
         See brfss_crosswalk(\"%s\") for the family, its review status,
         and any comparability notes; combining generations is your
         decision.",
        v,
        summarize_years(empty_years),
        paste(
          sprintf("%s (covers %s)", names(sib_txt), sib_txt),
          collapse = "; "
        ),
        v
      )
    )
  }
  if (length(bullets) == 0) {
    return(invisible())
  }
  names(bullets) <- rep("!", length(bullets))
  cli::cli_inform(bullets, class = "brfssdata_rename_note")
}

# Catch a typo'd vars before any year parquet downloads. Consulted: the
# variable catalog, cached-or-bundled only (download = FALSE), so the
# gate itself never fetches anything and never delays the year download.
# Its coverage is exact for the years it knows: data-raw/03_catalog.R
# builds it from the same files. Fail open on everything else: a read
# must never be blocked by missing or unreadable metadata, so an
# unavailable catalog, or any requested year the catalog does not cover
# (a new release read through an older snapshot), skips the gate and
# leaves query_parquet() to give the authoritative answer after
# download. The bundled-fallback note stays suppressed here: it flags
# stale metadata served as results, and this catalog read is an
# internal validity check, not a result.
check_vars_before_download <- function(
  vars,
  years,
  call = rlang::caller_env()
) {
  catalog <- tryCatch(
    suppressMessages(
      variables_catalog(download = FALSE, quiet = TRUE),
      classes = "brfssdata_bundled_fallback_note"
    ),
    error = function(e) NULL
  )
  if (is.null(catalog) || nrow(catalog) == 0) {
    return(invisible())
  }
  if (!all(years %in% catalog$year)) {
    return(invisible())
  }
  known <- unique(toupper(catalog$variable[catalog$year %in% years]))
  # `year` is real in every hosted file but absent from the catalog,
  # which is built from the upstream XPT column lists that predate it.
  requested <- unique(vars[toupper(vars) != "YEAR"])
  unknown <- requested[!toupper(requested) %in% known]
  if (length(unknown) == 0) {
    return(invisible())
  }
  hints <- var_not_found_hints(
    unknown,
    catalog_vars = catalog$variable,
    catalog_years = catalog$year,
    scope_vars = catalog$variable[catalog$year %in% years]
  )
  cli::cli_abort(
    c(
      "Variable{?s} {.val {unknown}} {?was/were} not found in the
       requested years.",
      "i" = "Checked against the variable catalog before downloading;
             no data were fetched.",
      rlang::set_names(hints, rep("i", length(hints))),
      "i" = "Use {.fun brfss_vars} to search available variables
             and the years they appear in."
    ),
    class = "brfssdata_bad_var",
    call = call
  )
}

ensure_years_cached <- function(
  years,
  download = TRUE,
  quiet = FALSE,
  call = rlang::caller_env()
) {
  assets <- year_asset(years)
  paths <- cache_path(assets)
  present <- file.exists(paths)

  # On the download path the manifest itself may refresh on its daily
  # cadence: read_manifest() checks the cached copy's age, attempts one
  # refresh when stale, and degrades to the cached copy with a
  # brfssdata_manifest_note when offline (its last_failure memo stops
  # retry storms). That is what tells a user who cached a year before a
  # corrected republish, within a day, via the recheck below. With
  # download = FALSE nothing ever touches the network, so fully cached
  # offline requests behave exactly as before.
  manifest <- if (download) read_manifest() else read_manifest_cached()

  # Self-heal: a cached file whose size disagrees with the manifest is a
  # truncated download from before checksum verification existed, or a
  # damaged cache restore. Treat it as missing so it re-downloads
  # verified. Only sizes are compared here; hashing every cached year on
  # every read would be slow, and full verification happens at download
  # time. Skipped under download = FALSE, which must not delete files it
  # cannot replace. The old file is deliberately NOT deleted here:
  # download_to_cache() renames a verified temp file over it on success,
  # and if the download fails (offline after a manifest refresh, say)
  # the user still has whatever was readable before.
  if (download && any(present)) {
    expected <- vapply(assets, manifest_size, numeric(1), manifest = manifest)
    damaged <- present & !is.na(expected) & file.size(paths) != expected
    if (any(damaged)) {
      if (!quiet) {
        cli::cli_inform(
          "Cached file{?s} {.file {assets[damaged]}} {?has/have} an
           unexpected size; re-downloading.",
          class = "brfssdata_cache_note"
        )
      }
      present[damaged] <- FALSE
    }
  }

  # Daily checksum recheck, on the same cadence as the metadata
  # catalogs: at most once per day per session, a present file's hash
  # is compared with the manifest entry, and a mismatch is treated
  # exactly like a damaged file above, announced and re-downloaded
  # verified. No manifest entry, no verdict. Skipped entirely under
  # download = FALSE, which must not delete what it cannot replace;
  # the never-delete rule holds here too, because download_to_cache()
  # only renames a verified temp file over the old one.
  if (download && any(present)) {
    due <- present & vapply(assets, asset_check_due, logical(1))
    if (any(due)) {
      failed <- vapply(
        which(due),
        function(i) {
          want <- manifest_sha256(assets[[i]], manifest)
          !is.null(want) &&
            !identical(cli::hash_file_sha256(paths[[i]]), want)
        },
        logical(1)
      )
      bad <- which(due)[failed]
      if (length(bad) > 0) {
        if (!quiet) {
          cli::cli_inform(
            "Cached file{?s} {.file {assets[bad]}} no longer
             {?matches/match} the data manifest's checksum;
             re-downloading.",
            class = "brfssdata_cache_note"
          )
        }
        present[bad] <- FALSE
      }
      for (a in assets[due]) {
        asset_checked(a)
      }
    }
  }

  missing <- years[!present]

  if (length(missing) > 0 && !download) {
    cli::cli_abort(
      c(
        "Year{?s} {.val {as.character(missing)}} {?is/are} not in the
         local cache and {.code download = FALSE} was set.",
        "i" = "Cached years: see {.fun brfss_cache_info}.",
        "i" = "Prefetch on a connected machine with
               {.code brfss_download(c({paste(missing, collapse = ', ')}))}."
      ),
      class = "brfssdata_not_cached",
      call = call
    )
  }

  if (length(missing) > 0) {
    shas <- lapply(year_asset(missing), manifest_sha256, manifest = manifest)
    unverified <- vapply(shas, is.null, logical(1))
    note_unverified(year_asset(missing)[unverified], quiet)
    for (i in seq_along(missing)) {
      year <- missing[[i]]
      if (!quiet) {
        cli::cli_inform(
          "Downloading BRFSS {year} (one-time, then cached).",
          class = "brfssdata_download_note"
        )
      }
      download_to_cache(
        year_url(year),
        cache_path(year_asset(year)),
        quiet = quiet,
        expected_sha256 = shas[[i]],
        call = call
      )
      # A just-verified download needs no recheck the same day.
      asset_checked(year_asset(year))
    }
  }
  paths
}
