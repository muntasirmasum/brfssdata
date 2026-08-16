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
#'   columns always carry CDC's canonical spelling; a name that matched
#'   only case-insensitively is reported in a
#'   `brfssdata_case_match_note` message, because the spelling that
#'   worked here will not work in the next `dplyr` verb. Use
#'   [brfss_vars()] to search names across years.
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
#'   download progress, cache notes, the full-load hint, the
#'   case-matching note, and the `na = TRUE` recode tally. Notes and
#'   warnings about what the data mean (renames, missing-code coverage,
#'   weight-domain subsetting) signal regardless of `quiet`, as does the
#'   note that a cached file failed its size or checksum check and was
#'   re-downloaded, which reports that the input bytes changed rather
#'   than narrating progress; silence a specific one by its class,
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
  download <- check_bool_arg(download, "download")
  quiet <- check_bool_arg(quiet, "quiet")
  na <- check_bool_arg(na, "na")
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
  states <- resolve_states(states)
  # Validated eagerly: passed lazily, an invalid labels value would only
  # surface if some variable actually converted.
  labels_mode <- if (isFALSE(labels)) NULL else labels_how(labels)
  cached <- file.exists(cache_path(year_asset(years)))
  # Modern years are 350-plus columns wide, so the default selection
  # materializes about 1.1 GB for 2023 alone. Said before anything is
  # downloaded or read, while narrowing the request still helps. Under
  # download = FALSE the cache alone decides whether the years can be
  # read at all, so the note waits for that verdict rather than
  # announcing a load ensure_years_cached() is about to refuse.
  if (is.null(vars) && !quiet && (download || all(cached))) {
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
  if (!is.null(vars) && download && !all(cached)) {
    check_vars_before_download(vars, years)
  }
  paths <- ensure_years_cached(years, download = download, quiet = quiet)
  dat <- query_parquet(
    paths,
    # The filter column always rides along so the subset stays visible.
    vars = if (is.null(vars) || is.null(states)) vars else union(vars, "_STATE"),
    states = states
  )
  check_year_contents(dat, years, paths)
  note_case_matches(dat, vars, quiet)
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
      exclude = LABEL_EXCLUDE,
      # Names, not columns: the coverage signal is per-variable only for
      # variables the caller chose, which is what makes it short enough
      # to act on. A full-width read passes NULL and keeps the cliff.
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
      exclude = LABEL_EXCLUDE,
      how = labels_mode,
      na = isTRUE(na)
    )
  }
  dat
}

# A cache directory copied by hand is the documented air-gapped
# workflow, and a botched copy can leave a file whose name says one
# survey year and whose rows are another. Nothing downstream would
# notice: the weights, the design variables, and the codes all look
# plausible, so the analysis is simply of the wrong year. The `year`
# column is always selected, so the comparison is free.
#
# Two shapes of evidence, because comparing the pooled rows against the
# whole request misses the likeliest hand-copy error of all. Copying
# 1995's file over 1993's name and then reading both years yields only
# 1995 rows, every one of them inside the request, so a subset test sees
# nothing while 1995 is silently counted twice. So: any year the request
# did not ask for is evidence, and so is a requested year whose file is
# cached yet contributed no rows at all. The second case has an innocent
# explanation (a states filter no respondent of that year satisfies),
# which is why it triggers the per-file probe rather than the error.
check_year_contents <- function(
  dat,
  years,
  paths,
  call = rlang::caller_env()
) {
  if (!"year" %in% names(dat) || nrow(dat) == 0) {
    return(invisible())
  }
  present <- unique(dat$year)
  extra <- setdiff(present, years)
  cached_years <- cached_file_year(basename(paths))
  silent <- setdiff(cached_years[!is.na(cached_years)], present)
  if (length(extra) == 0 && length(silent) == 0) {
    return(invisible())
  }
  # Only reached on a real mismatch, so the per-file probe costs nothing
  # in the normal case. Each file is judged against its OWN name, not
  # against the request: that is what catches the swap above. A file
  # that cannot be read is left to query_parquet()'s corrupt-cache path,
  # which already names it.
  culprits <- vapply(
    paths,
    function(p) {
      want <- cached_file_year(basename(p))
      if (is.na(want)) {
        return(FALSE)
      }
      found <- tryCatch(
        unique(query_parquet(p, vars = "year")$year),
        error = function(e) NULL
      )
      if (is.null(found) || length(found) == 0) {
        return(FALSE)
      }
      anyNA(found) || !all(found == want)
    },
    logical(1)
  )
  if (!any(culprits)) {
    # A requested year contributing nothing, with every file holding
    # what its name promises: the states filter explanation, and
    # warn_state_coverage() is the signal for it.
    return(invisible())
  }
  bad <- basename(paths[culprits])
  n_bad <- length(bad)
  bad_years <- cached_file_year(bad)
  bad_years <- bad_years[!is.na(bad_years)]
  remedy <- if (length(bad_years) > 0) {
    "Run {.code brfss_cache_clear(years = c({paste(bad_years,
     collapse = ', ')}))} and read again on a connected machine, or
     re-copy {cli::qty(n_bad)}{?the file/the files} from the cache
     {?it/they} came from."
  } else {
    "Remove {.file {bad}} from {.path {brfss_cache_dir()}} and fetch
     {cli::qty(n_bad)}{?it/them} again."
  }
  # Reported per file, from the file's own contents. Rendered here
  # rather than left as a template because the years come from a
  # damaged file and can be NA, which summarize_years() cannot format.
  held <- escape_cli_braces(vapply(
    paths[culprits],
    function(p) {
      found <- tryCatch(
        sort(unique(query_parquet(p, vars = "year")$year)),
        error = function(e) NULL
      )
      label <- if (is.null(found) || length(found) == 0) {
        "no readable year"
      } else if (anyNA(found)) {
        paste0(
          "missing years",
          if (any(!is.na(found))) {
            paste0(" and ", summarize_years(found[!is.na(found)]))
          }
        )
      } else {
        summarize_years(found)
      }
      cli::format_inline("{.file {basename(p)}} holds {label}")
    },
    character(1),
    USE.NAMES = FALSE
  ))
  cli::cli_abort(
    c(
      "Cached file{?s} {.file {bad}} {?does/do} not hold the survey
       year{?s} {?its/their} name promises.",
      rlang::set_names(held, rep("x", length(held))),
      "i" = "A file whose name and contents disagree is a damaged cache
             copy, not a survey-year quirk.",
      "i" = remedy
    ),
    class = c("brfssdata_wrong_year_cache", "brfssdata_corrupt_cache"),
    call = call
  )
}

# Case-insensitive `vars` matching is a convenience on the way in only:
# the columns come back in CDC's canonical spelling, so the lowercase
# name that just worked fails in the next dplyr verb, with no hint that
# the two are the same variable. Summarized rather than one note per
# column, because a wide lowercase request would otherwise print dozens
# of lines. Quiet-gated: it is about the call, not about the data.
note_case_matches <- function(dat, vars, quiet) {
  if (quiet || is.null(vars)) {
    return(invisible())
  }
  cols <- names(dat)
  ci <- match(toupper(vars), toupper(cols))
  changed <- !is.na(ci) & !vars %in% cols
  if (!any(changed)) {
    return(invisible())
  }
  pairs <- unique(sprintf("%s as %s", vars[changed], cols[ci[changed]]))
  n <- length(pairs)
  shown <- paste(utils::head(pairs, 3L), collapse = ", ")
  if (n > 3L) {
    shown <- paste0(shown, ", and ", n - 3L, " more")
  }
  cli::cli_inform(
    c(
      "i" = "{n} requested name{?s} matched case-insensitively; the
             column{?s} returned carr{?ies/y} CDC's spelling
             ({shown}).",
      "i" = "Use the returned spelling in later steps; a
             {.code group_by()} on the name you typed will not find it."
    ),
    class = "brfssdata_case_match_note"
  )
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
  manifest <- if (download) {
    read_manifest(quiet = quiet)
  } else {
    read_manifest_cached()
  }

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
  #
  # The note is not quiet-gated. Ordinary download progress is
  # narration, but bytes that no longer match the manifest are a
  # statement about the input: the hosted assets are occasionally
  # republished, and a pipeline that ran quietly should still record
  # that what it read changed underneath it.
  if (download && any(present)) {
    expected <- vapply(assets, manifest_size, numeric(1), manifest = manifest)
    damaged <- present & !is.na(expected) & file.size(paths) != expected
    if (any(damaged)) {
      cli::cli_inform(
        "Cached file{?s} {.file {assets[damaged]}} {?has/have} an
         unexpected size; re-downloading.",
        class = "brfssdata_cache_note"
      )
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
  # only renames a verified temp file over the old one. Like the size
  # check above, a mismatch is announced even under quiet: it reports
  # that the input bytes changed, not that work is in progress.
  #
  # Only the assets that passed are marked checked. A failed asset stays
  # due, so if the re-download below aborts (offline, or the release
  # withdrawn) the next call hashes it again and says so again, instead
  # of serving a file known not to match for the rest of the session.
  # The successful re-downloads mark themselves once verified.
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
        cli::cli_inform(
          "Cached file{?s} {.file {assets[bad]}} no longer
           {?matches/match} the data manifest's checksum;
           re-downloading.",
          class = "brfssdata_cache_note"
        )
        present[bad] <- FALSE
      }
      for (a in assets[which(due)[!failed]]) {
        asset_checked(a)
      }
    }
  }

  missing <- years[!present]

  if (length(missing) > 0 && !download) {
    # The manifest is readable offline, so a year that was never
    # published can be told apart from one merely not cached here.
    # Advising a prefetch of an unpublished year sends the user to a
    # command that can only fail with brfssdata_bad_year. An empty
    # published list (no cached or bundled manifest at all) tells us
    # nothing, so the split is skipped and every year keeps the hint.
    published <- as.integer(manifest$years)
    unpublished <- if (length(published) > 0) {
      setdiff(missing, published)
    } else {
      integer(0)
    }
    # A year absent from this machine's manifest is only proof of
    # anything when the manifest cannot be the reason. An air-gapped
    # cache copied before the newest release lists fewer years than
    # exist, and withholding the prefetch command on that basis sends
    # the reader away from the one command that would have worked. A
    # year that has not happened yet is a different matter: no refresh
    # can produce it, so the prefetch really would only fail.
    impossible <- unpublished[unpublished > as.integer(format(Sys.Date(), "%Y"))]
    prefetchable <- setdiff(missing, impossible)
    stale_risk <- setdiff(unpublished, impossible)
    bullets <- c(
      "Year{?s} {.val {as.character(missing)}} {?is/are} not in the
       local cache and {.code download = FALSE} was set.",
      "i" = "Cached years: see {.fun brfss_cache_info}."
    )
    if (length(prefetchable) > 0) {
      bullets <- c(
        bullets,
        "i" = "Prefetch on a connected machine with
               {.code brfss_download(c({paste(prefetchable,
               collapse = ', ')}))}."
      )
    }
    if (length(stale_risk) > 0) {
      # One interpolated vector per bullet: cli refuses to guess which
      # of two it should count when a plural marker is present.
      bullets <- c(
        bullets,
        "i" = "Year{?s} {.val {as.character(stale_risk)}} {?is/are} not in
               this machine's copy of the manifest.",
        "i" = "That copy may simply be older than the release, and the
               prefetch above refreshes it. It lists
               {summarize_years(published)}."
      )
    }
    if (length(impossible) > 0) {
      bullets <- c(
        bullets,
        "i" = "Year{?s} {.val {as.character(impossible)}} {?is/are} in
               the future, so no prefetch can supply {?it/them}.",
        "i" = "Published years: {summarize_years(published)}."
      )
    }
    cli::cli_abort(
      bullets,
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
