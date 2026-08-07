# End-to-end check against the real released data, run weekly by
# .github/workflows/integration.yaml. Everything here is intentionally
# independent of the fixtures: real downloads, the published .sha256
# sidecars (not just the manifest hashes the package verifies itself),
# recorded row counts, and one known-answer estimate.

library(brfssdata)

years <- c(1993L, 2023L, 2024L) # pre-break era, known-answer year, newest
fail <- function(...) stop(sprintf(...), call. = FALSE)

# 1. Real downloads through the package (manifest-hash verification runs
#    inside read_brfss on this path).
for (year in years) {
  dat <- read_brfss(year, vars = "GENHLTH", quiet = TRUE)
  message(sprintf("%d: %d rows downloaded and read", year, nrow(dat)))
}

# 2. The published .sha256 sidecars agree with what we cached. This is
#    the independent verification channel: a manifest that lied about
#    its own hashes would pass the package's check but fail this one.
for (year in years) {
  sidecar_url <- sprintf(
    "https://github.com/muntasirmasum/brfssdata/releases/download/data-%d/brfss_%d.parquet.sha256",
    year,
    year
  )
  sidecar <- tempfile()
  utils::download.file(sidecar_url, sidecar, quiet = TRUE)
  published <- strsplit(trimws(readLines(sidecar)[[1]]), "\\s+")[[1]][[1]]
  cached <- cli::hash_file_sha256(
    file.path(brfss_cache_dir(), sprintf("brfss_%d.parquet", year))
  )
  if (!identical(published, cached)) {
    fail("%d: cached file does not match the published .sha256", year)
  }
  message(sprintf("%d: sidecar checksum verified", year))
}

# 3. Row counts match the recorded statistics for every checked year.
stats <- utils::read.csv("vignettes/articles/brfss_year_stats.csv")
for (year in years) {
  expected <- stats$respondents[stats$year == year]
  got <- nrow(read_brfss(year, vars = "GENHLTH", quiet = TRUE))
  if (length(expected) != 1L || got != expected) {
    fail("%d: %d rows, expected %s", year, got, toString(expected))
  }
}
message("row counts match brfss_year_stats.csv")

# 4. Era-correct design columns are present.
pre <- read_brfss(1993, vars = c("_FINALWT", "_STSTR", "_PSU"), quiet = TRUE)
if (anyNA(pre$`_FINALWT`)) {
  fail("1993: _FINALWT carries missing values")
}
for (year in c(2023L, 2024L)) {
  post <- read_brfss(
    year,
    vars = c("_LLCPWT", "_STSTR", "_PSU"),
    quiet = TRUE
  )
  if (anyNA(post$`_LLCPWT`)) {
    fail("%d: _LLCPWT carries missing values", year)
  }
}
message("design columns present in both eras")

# 5. Known answer. Design-weighted fair-or-poor general health, 2023.
#    0.1937 is the design-based estimate from the released 2023 file
#    (see the survey-design article, "about 19.4 percent") and matches
#    CDC's published figure from the BRFSS Prevalence & Trends tool
#    (https://www.cdc.gov/brfss/brfssprevalence/), Health Status, 2023.
#    A wrong weight column, a broken na step, or corrupted data all land
#    outside +/- 0.5 pp of it.
des <- brfss_design(2023, vars = "GENHLTH", quiet = TRUE)
# GENHLTH >= 4, not %in% c(4, 5): %in% maps NA to FALSE and would fold
# the na-cleared don't-know/refused rows back into the denominator.
est <- srvyr::summarize(
  des,
  fair_poor = srvyr::survey_mean(GENHLTH >= 4, na.rm = TRUE)
)
if (abs(est$fair_poor - 0.1937) > 0.005) {
  fail("2023 fair-or-poor prevalence %.4f outside 0.1937 +/- 0.005", est$fair_poor)
}
message(sprintf("known answer holds: fair-or-poor = %.4f", est$fair_poor))

# 6. The weight total is a plausible US adult population.
wt_total <- sum(des$variables$`_LLCPWT`)
if (wt_total < 2e8 || wt_total > 3e8) {
  fail("2023 weight total %.0f outside the 200M-300M adult band", wt_total)
}
message(sprintf("weight total plausible: %.0f", wt_total))

# 7. The documented child-module workflow builds on real data. The
#    child weight covers only completed child interviews (49,541 rows
#    in 2023), so the design must subset to them, keep no missing
#    weights, and say what it dropped.
child <- withCallingHandlers(
  brfss_design(2023, vars = "GENHLTH", weight = "_CLLCPWT"),
  brfssdata_weight_subset_note = function(m) {
    message("subset note observed")
    invokeRestart("muffleMessage")
  }
)
n_child <- nrow(child$variables)
if (n_child < 45000 || n_child > 55000) {
  fail("2023 _CLLCPWT design has %d rows, expected about 49,541", n_child)
}
if (anyNA(child$variables$brfss_wt)) {
  fail("2023 _CLLCPWT design carries missing weights after subsetting")
}
message(sprintf("child-weight design holds: %d rows", n_child))

# 8. Cross-year type consistency on a variable CDC stored as text in
#    2001 and as a number in 2000 before the canonical-type rebuild:
#    one type, no ".0" artifacts, no blank strings.
msa <- read_brfss(c(2000L, 2001L), vars = "_MSACODE", quiet = TRUE)
if (!is.character(msa$`_MSACODE`)) {
  fail("_MSACODE across 2000-2001 is not character")
}
vals <- msa$`_MSACODE`[!is.na(msa$`_MSACODE`)]
if (any(grepl("\\.0$", vals))) {
  fail("_MSACODE carries '.0' promotion artifacts")
}
if (any(vals == "")) {
  fail("_MSACODE carries blank strings instead of NA")
}
message("_MSACODE type-consistent across the 2000/2001 boundary")

# 9. The trailing-noun missing bucket really clears. _FRTLT1A code 9 is
#    "Don't know, refused or missing values"; 2021 carried 51,087 nines
#    that the whole-token matcher used to leave in place.
frt <- read_brfss(2021L, vars = "_FRTLT1A", quiet = TRUE, na = TRUE)
if (any(frt$`_FRTLT1A` %in% 9)) {
  fail("_FRTLT1A 2021 still carries code 9 under na = TRUE")
}
if (!anyNA(frt$`_FRTLT1A`)) {
  fail("_FRTLT1A 2021 shows no NAs; the na step apparently did nothing")
}
message("_FRTLT1A missing bucket cleared under na = TRUE")

# 10. na = TRUE on a pre-catalog year announces its own no-op.
seen_note <- FALSE
invisible(withCallingHandlers(
  read_brfss(1993L, vars = "GENHLTH", na = TRUE),
  brfssdata_na_coverage_note = function(m) {
    seen_note <<- TRUE
    invokeRestart("muffleMessage")
  }
))
if (!seen_note) {
  fail("1993 na = TRUE emitted no coverage note")
}
message("pre-1998 coverage note fires")

message("integration check passed")
