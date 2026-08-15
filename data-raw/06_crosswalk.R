# Build the rename crosswalk: which CDC variables are generations of
# the same concept (_DRNKWK1 -> _DRNKWK2 -> _DRNKWK3), so users pooling
# years can find the whole family.
#
# CDC publishes no crosswalk, so this is rule-based candidate
# generation plus human review, with the review file checked into git
# as the curation artifact:
#
#   1. This script proposes candidate families from the variable
#      catalog (same stem after stripping trailing digits, mutually
#      non-overlapping year ranges) and merges them into
#      data-raw/crosswalk_review.csv, PRESERVING every row a human has
#      already touched. New candidates arrive with status = "candidate"
#      and comparable = NA.
#   2. The maintainer reviews candidates against the CDC codebooks:
#      flips status to "verified", sets comparable (TRUE / FALSE vs the
#      previous generation), and writes a note when the definition
#      changed. A false pairing is flipped to status = "rejected", NOT
#      deleted: a deleted row would be re-proposed as a fresh candidate
#      on every future run, while a rejected row stays in the file as
#      the tombstone that prevents that. Rejected rows never reach the
#      published parquet.
#   3. The script then expands the review file into the long
#      brfss_crosswalk.parquet (one row per variable-year) that
#      data-raw/04_upload.R publishes with the other catalogs.
#
# Run from the package root after 03_catalog.R. Idempotent: re-running
# without catalog changes rewrites the same outputs.

out_dir <- "data-raw/parquet"
review_path <- "data-raw/crosswalk_review.csv"

con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
catalog <- DBI::dbGetQuery(
  con,
  sprintf(
    "SELECT variable, year FROM read_parquet('%s')",
    file.path(out_dir, "brfss_variables.parquet")
  )
)

# --- candidate generation ---------------------------------------------------

# Stem: the name with any trailing digits removed. Requires at least
# three letters so short names cannot collide by accident, and a
# trailing-digit member so a lone continuous variable (GENHLTH every
# year) never forms a family of one.
stem_of <- function(x) sub("[0-9]+$", "", x)

per_var <- do.call(
  rbind,
  lapply(split(catalog, catalog$variable), function(d) {
    data.frame(
      variable = d$variable[[1]],
      stem = stem_of(d$variable[[1]]),
      first_year = min(d$year),
      last_year = max(d$year),
      n_years = length(unique(d$year)),
      stringsAsFactors = FALSE
    )
  })
)
rownames(per_var) <- NULL
per_var <- per_var[grepl("^_?[A-Z]{3,}$", per_var$stem), , drop = FALSE]

candidates <- do.call(
  rbind,
  lapply(split(per_var, per_var$stem), function(fam) {
    if (nrow(fam) < 2) {
      return(NULL)
    }
    # A family needs at least one digit-suffixed member; a stem that
    # only ever appears bare is just one variable.
    if (!any(fam$variable != fam$stem)) {
      return(NULL)
    }
    fam <- fam[order(fam$first_year, fam$variable), , drop = FALSE]
    # Generations replace each other: their year ranges must not
    # overlap. Same-name reuse across eras with overlapping ranges is a
    # different phenomenon (versioned questionnaires) and is excluded.
    ranges <- Map(seq, fam$first_year, fam$last_year)
    for (i in seq_len(nrow(fam) - 1)) {
      if (length(intersect(ranges[[i]], ranges[[i + 1]])) > 0) {
        return(NULL)
      }
    }
    # Deliberately no label-wording gate here. CDC rewrites the
    # 40-character variable label mid-life (PERSDOC2 was labelled HAVE
    # PERS DOC OR HLTH CARE PROVIDER in 2001 and MULTIPLE HEALTH CARE
    # PROFESSIONALS from 2005), so wording cannot separate "different
    # question" from "new abbreviation", and a family the rules drop
    # here leaves no trace at all: no candidate row to review, no
    # tombstone. Wording continuity is evidence, not a filter, and it
    # reaches the reviewer as label_similarity in
    # data-raw/crosswalk_evidence.csv; a false pairing is rejected by
    # hand in the review file, where the tombstone keeps it out.
    data.frame(
      concept = tolower(sub("^_", "", fam$stem[[1]])),
      variable = fam$variable,
      first_year = fam$first_year,
      last_year = fam$last_year,
      generation = seq_len(nrow(fam)),
      status = "candidate",
      comparable = NA,
      note = "",
      stringsAsFactors = FALSE
    )
  })
)
rownames(candidates) <- NULL
message(
  "candidates: ",
  length(unique(candidates$concept)),
  " concepts over ",
  nrow(candidates),
  " variables"
)

# --- merge with the reviewed file -------------------------------------------
# Human edits always win: an existing (concept, variable) row is kept
# verbatim, whatever its status; only genuinely new candidates are
# appended. Rows the generator no longer proposes stay in the file (the
# reviewer may have added a family the rules cannot see, e.g. a rename
# without a shared stem).

if (file.exists(review_path)) {
  # note must stay character: read.csv types an all-blank column as
  # logical, and rbind would then turn every existing blank note into
  # NA while new rows keep "".
  reviewed <- utils::read.csv(
    review_path,
    stringsAsFactors = FALSE,
    colClasses = c(note = "character", status = "character")
  )
  reviewed$comparable <- as.logical(reviewed$comparable)
  new_rows <- candidates[
    !paste(candidates$concept, candidates$variable) %in%
      paste(reviewed$concept, reviewed$variable),
    ,
    drop = FALSE
  ]
  message(
    "merge: keeping ",
    nrow(reviewed),
    " reviewed rows, adding ",
    nrow(new_rows)
  )
  review <- rbind(reviewed, new_rows)
} else {
  review <- candidates
}
review <- review[order(review$concept, review$generation, review$variable), ]

# A newly catalogued earlier member of an existing family gets a fresh
# generation number that can collide with a frozen reviewed one;
# machine-renumbering reviewed rows is forbidden, so collisions are the
# maintainer's to resolve in the CSV.
gen_dup <- unique(review$concept[
  duplicated(review[c("concept", "generation")]) &
    review$status != "rejected"
])
if (length(gen_dup) > 0) {
  warning(
    "duplicate generation numbers in concept(s) ",
    paste(gen_dup, collapse = ", "),
    "; renumber by hand in ",
    review_path,
    call. = FALSE
  )
}
utils::write.csv(review, review_path, row.names = FALSE, na = "")

# --- expand to the long hosted parquet --------------------------------------
# One row per variable-year, years taken from the catalog so the
# parquet always reflects where the variable actually appears. Rejected
# rows are tombstones for the merge above and never publish.

publishable <- review[review$status != "rejected", , drop = FALSE]
orphans <- setdiff(publishable$variable, catalog$variable)
if (length(orphans) > 0) {
  stop(
    "review rows whose variable is not in the catalog (typo?): ",
    paste(orphans, collapse = ", "),
    call. = FALSE
  )
}
long <- merge(
  publishable[c("concept", "variable", "generation", "status", "comparable", "note")],
  catalog[c("variable", "year")],
  by = "variable"
)
long <- long[order(long$concept, long$generation, long$year), ]
long <- long[c("concept", "variable", "year", "generation", "status", "comparable", "note")]

duckdb::duckdb_register(con, "crosswalk", long)
DBI::dbExecute(
  con,
  sprintf(
    "COPY (SELECT concept, variable, CAST(year AS INTEGER) AS year,
            CAST(generation AS INTEGER) AS generation, status,
            CAST(comparable AS BOOLEAN) AS comparable, note
     FROM crosswalk ORDER BY concept, generation, year)
     TO '%s' (FORMAT parquet, COMPRESSION zstd)",
    file.path(out_dir, "brfss_crosswalk.parquet")
  )
)
message(
  "wrote ",
  file.path(out_dir, "brfss_crosswalk.parquet"),
  ": ",
  nrow(long),
  " variable-year rows"
)
