# Build the evidence sheet behind the crosswalk curation pass:
# data-raw/crosswalk_evidence.csv, one row per consecutive generation
# pair in crosswalk_review.csv, with the mechanical evidence (code
# sets, value-label wording, variable-label similarity, name-suffix
# shape) and a SUGGESTED verdict. The suggestion is triage, not
# authority: the reviewer confirms or overrides in
# crosswalk_review.csv, and question-wording changes that live only in
# the questionnaire PDFs (the usual reason CDC bumps a name) are
# invisible here, so a "comparable TRUE" suggestion means "nothing in
# the catalogs contradicts it", never more. Run from the package root
# after 06_crosswalk.R; re-run whenever the review file gains rows.

review_path <- "data-raw/crosswalk_review.csv"
out_path <- "data-raw/crosswalk_evidence.csv"
stopifnot(file.exists(review_path))

con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
vars_cat <- DBI::dbGetQuery(
  con,
  "SELECT variable, label, year FROM
   read_parquet('data-raw/parquet/brfss_variables.parquet')"
)
labels_cat <- DBI::dbGetQuery(
  con,
  "SELECT variable, year, code, label FROM
   read_parquet('data-raw/parquet/brfss_labels.parquet')"
)

review <- utils::read.csv(
  review_path,
  stringsAsFactors = FALSE,
  colClasses = c(note = "character", status = "character")
)
review <- review[order(review$concept, review$generation), ]

latest_var_label <- function(v) {
  d <- vars_cat[vars_cat$variable == v & !is.na(vars_cat$label), , drop = FALSE]
  if (nrow(d) == 0) {
    return(NA_character_)
  }
  d$label[which.max(d$year)]
}

latest_codes <- function(v) {
  d <- labels_cat[labels_cat$variable == v, , drop = FALSE]
  if (nrow(d) == 0) {
    return(NULL)
  }
  d[d$year == max(d$year), c("code", "label")]
}

tokens <- function(x) {
  x <- tolower(ifelse(is.na(x), "", x))
  x <- gsub("[^a-z0-9 ]", " ", x)
  t <- strsplit(trimws(gsub("[[:space:]]+", " ", x)), " ")[[1]]
  setdiff(t, c("", "of", "the", "a", "an", "in", "or", "and", "to"))
}

jaccard <- function(a, b) {
  if (length(a) == 0 || length(b) == 0) {
    return(NA_real_)
  }
  length(intersect(a, b)) / length(union(a, b))
}

# Case, apostrophes, punctuation, and spacing are presentation, not
# meaning (mirrors normalize_semantic in R/brfss_labels.R).
norm_sem <- function(x) {
  x <- tolower(x)
  x <- gsub("[Ââ’´'`]", "", x)
  x <- gsub("[^a-z0-9 ]", "", x)
  gsub("[[:space:]]+", " ", trimws(x))
}

pair_rows <- list()
for (concept in unique(review$concept)) {
  fam <- review[review$concept == concept, , drop = FALSE]
  if (nrow(fam) < 2) {
    next
  }
  for (i in seq_len(nrow(fam) - 1)) {
    a <- fam[i, ]
    b <- fam[i + 1, ]

    lab_a <- latest_var_label(a$variable)
    lab_b <- latest_var_label(b$variable)
    sim <- jaccard(tokens(lab_a), tokens(lab_b))

    codes_a <- latest_codes(a$variable)
    codes_b <- latest_codes(b$variable)
    if (is.null(codes_a) || is.null(codes_b)) {
      codes_equal <- NA
      drift <- "no-catalog-labels"
      drift_detail <- if (is.null(codes_a) && is.null(codes_b)) {
        "neither generation has catalog labels (pre-1998?)"
      } else if (is.null(codes_a)) {
        sprintf("%s has no catalog labels", a$variable)
      } else {
        sprintf("%s has no catalog labels", b$variable)
      }
    } else {
      codes_equal <- setequal(codes_a$code, codes_b$code)
      shared <- intersect(codes_a$code, codes_b$code)
      la <- codes_a$label[match(shared, codes_a$code)]
      lb <- codes_b$label[match(shared, codes_b$code)]
      changed <- shared[norm_sem(la) != norm_sem(lb)]
      if (!codes_equal) {
        drift <- "code-set-differs"
        drift_detail <- sprintf(
          "only in %s: {%s}; only in %s: {%s}",
          a$variable,
          paste(setdiff(codes_a$code, codes_b$code), collapse = ","),
          b$variable,
          paste(setdiff(codes_b$code, codes_a$code), collapse = ",")
        )
      } else if (length(changed) > 0) {
        drift <- "label-wording-differs"
        drift_detail <- paste(
          vapply(
            changed,
            function(cd) {
              sprintf(
                "code %s: '%s' -> '%s'",
                cd,
                codes_a$label[codes_a$code == cd],
                codes_b$label[codes_b$code == cd]
              )
            },
            character(1)
          ),
          collapse = " | "
        )
      } else {
        drift <- "none"
        drift_detail <- ""
      }
    }

    # A trailing number of 10 or more is usually not a version counter:
    # PRSNL65/PRSNL70 are age cutoffs, not generations.
    suffixes <- suppressWarnings(as.integer(sub(
      "^.*?([0-9]+)$",
      "\\1",
      c(a$variable, b$variable)
    )))
    name_flag <- if (any(!is.na(suffixes) & suffixes >= 10)) {
      "suffix >= 10: looks like an age/code, not a version counter"
    } else {
      ""
    }

    gap <- b$first_year - a$last_year

    if (nzchar(name_flag)) {
      status <- "rejected?"
      comparable <- ""
      confidence <- "low"
      rationale <- name_flag
    } else if (identical(drift, "no-catalog-labels")) {
      status <- "verified?"
      comparable <- ""
      confidence <- "low"
      rationale <- paste(drift_detail, "- compare codebooks by hand")
    } else if (isFALSE(codes_equal)) {
      status <- "verified?"
      comparable <- "FALSE"
      confidence <- "medium"
      rationale <- "same concept but the code set changed; note the diff"
    } else if (identical(drift, "label-wording-differs")) {
      status <- "verified?"
      comparable <- "check"
      confidence <- "medium"
      rationale <- "codes identical but answer wording changed; judge whether meaning moved"
    } else {
      status <- "verified?"
      comparable <- "TRUE"
      confidence <- if (!is.na(sim) && sim >= 0.5 && gap <= 3) "high" else "medium"
      rationale <- "codes and answer labels identical; check question wording in the codebook if the estimate matters"
    }

    pair_rows[[length(pair_rows) + 1]] <- data.frame(
      concept = concept,
      from_var = a$variable,
      to_var = b$variable,
      from_years = sprintf("%d-%d", a$first_year, a$last_year),
      to_years = sprintf("%d-%d", b$first_year, b$last_year),
      gap_years = gap,
      label_from = lab_a,
      label_to = lab_b,
      label_similarity = round(sim, 2),
      codes_equal = codes_equal,
      drift = drift,
      drift_detail = drift_detail,
      name_flag = name_flag,
      suggested_status = status,
      suggested_comparable = comparable,
      confidence = confidence,
      rationale = rationale,
      stringsAsFactors = FALSE
    )
  }
}
evidence <- do.call(rbind, pair_rows)
# Review order: problems first, then by confidence, then alphabetical.
ord <- order(
  evidence$name_flag == "",
  match(evidence$confidence, c("low", "medium", "high")),
  evidence$concept
)
evidence <- evidence[ord, ]
utils::write.csv(evidence, out_path, row.names = FALSE, na = "")
message(
  "wrote ",
  out_path,
  ": ",
  nrow(evidence),
  " generation pairs (",
  sum(evidence$confidence == "high"),
  " high / ",
  sum(evidence$confidence == "medium"),
  " medium / ",
  sum(evidence$confidence == "low"),
  " low confidence; ",
  sum(nzchar(evidence$name_flag)),
  " flagged suffix >= 10)"
)
