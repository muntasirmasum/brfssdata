# Build the shipped data objects: data/brfss_states.rda and
# data/brfss_std_pop_2000.rda. Run from the package root; re-run
# whenever the sources change (they essentially never do: state FIPS
# assignments and the 2000 standard population are fixed).

# --- brfss_states ------------------------------------------------------------
# Every jurisdiction that appears in BRFSS's _STATE format maps: the 50
# states, DC, and the participating territories. FIPS codes are the
# Census state codes (FIPS PUB 5-2); region and division are the Census
# Bureau's, via R's own datasets for the states, hand-set for DC
# (Census places it in the South / South Atlantic), NA for territories
# (the Census regions do not cover them).

state_fips <- c(
  1L, 2L, 4L, 5L, 6L, 8L, 9L, 10L, 12L, 13L, 15L, 16L, 17L, 18L, 19L,
  20L, 21L, 22L, 23L, 24L, 25L, 26L, 27L, 28L, 29L, 30L, 31L, 32L, 33L,
  34L, 35L, 36L, 37L, 38L, 39L, 40L, 41L, 42L, 44L, 45L, 46L, 47L, 48L,
  49L, 50L, 51L, 53L, 54L, 55L, 56L
)
stopifnot(length(state_fips) == 50)

brfss_states <- rbind(
  data.frame(
    fips = state_fips,
    name = datasets::state.name,
    abbr = datasets::state.abb,
    region = as.character(datasets::state.region),
    division = as.character(datasets::state.division),
    stringsAsFactors = FALSE
  ),
  data.frame(
    fips = c(11L, 60L, 66L, 70L, 72L, 78L),
    name = c(
      "District of Columbia",
      "American Samoa",
      "Guam",
      "Palau",
      "Puerto Rico",
      "Virgin Islands"
    ),
    abbr = c("DC", "AS", "GU", "PW", "PR", "VI"),
    region = c("South", NA, NA, NA, NA, NA),
    division = c("South Atlantic", NA, NA, NA, NA, NA),
    stringsAsFactors = FALSE
  )
)
brfss_states <- brfss_states[order(brfss_states$fips), ]
rownames(brfss_states) <- NULL
# R's own region labels use "North Central"; the Census renamed that
# region "Midwest" in 1984, and every modern Census product uses the
# new name.
brfss_states$region[brfss_states$region == "North Central"] <- "Midwest"
brfss_states <- tibble::as_tibble(brfss_states)

# Cross-check against the catalog: every _STATE code CDC has ever
# labeled must be here, and nothing else.
catalog_codes <- DBI::dbGetQuery(
  DBI::dbConnect(duckdb::duckdb(shared_home = FALSE)),
  "SELECT DISTINCT code FROM
   read_parquet('data-raw/parquet/brfss_labels.parquet')
   WHERE variable = '_STATE'"
)$code
stopifnot(setequal(brfss_states$fips, catalog_codes))

# --- brfss_std_pop_2000 -------------------------------------------------------
# The 2000 projected U.S. standard population (Census P25-1130), from
# SEER's single-age distribution (standard 205, ages 0-99; total
# 274,633,642), aggregated to the two groupings BRFSS work needs:
#
#   set "age19"  - NCHS's 19 standard five-year groups (0, 1-4, 5-9,
#                  ..., 80-84, 85+), the general-purpose standard.
#   set "adult6" - ages 18 and over collapsed to BRFSS's _AGE_G groups
#                  (18-24, 25-34, ..., 65+); weights match Klein &
#                  Schoenborn's age-18-and-over distribution (18-24 =
#                  0.128810 there, rounded from these counts).
#
# std_weight is normalized within each set, so each set's weights sum
# to 1 over the population that set covers.
# Source: https://seer.cancer.gov/stdpopulations/stdpop.singleagesthru99.txt

src <- "data-raw/raw/stdpop.singleagesthru99.txt"
if (!file.exists(src)) {
  utils::download.file(
    "https://seer.cancer.gov/stdpopulations/stdpop.singleagesthru99.txt",
    src,
    mode = "wb"
  )
}
lines <- readLines(src)
single <- data.frame(
  standard = substr(lines, 1, 3),
  age = as.integer(substr(lines, 4, 6)),
  pop = as.numeric(substr(lines, 7, nchar(lines)))
)
single <- single[single$standard == "205", ]
stopifnot(sum(single$pop) == 274633642)

group_sum <- function(lo, hi) {
  sum(single$pop[single$age >= lo & single$age <= hi])
}

age19_bounds <- rbind(
  c(0, 0),
  c(1, 4),
  cbind(seq(5, 80, by = 5), seq(9, 84, by = 5)),
  c(85, 999)
)
age19 <- data.frame(
  set = "age19",
  age_group = c(
    "<1",
    "1-4",
    paste(seq(5, 80, by = 5), seq(9, 84, by = 5), sep = "-"),
    "85+"
  ),
  age_min = as.integer(age19_bounds[, 1]),
  age_max = as.integer(ifelse(age19_bounds[, 2] == 999, NA, age19_bounds[, 2])),
  std_pop = mapply(group_sum, age19_bounds[, 1], age19_bounds[, 2])
)

adult6_bounds <- rbind(
  c(18, 24),
  c(25, 34),
  c(35, 44),
  c(45, 54),
  c(55, 64),
  c(65, 999)
)
adult6 <- data.frame(
  set = "adult6",
  age_group = c("18-24", "25-34", "35-44", "45-54", "55-64", "65+"),
  age_min = as.integer(adult6_bounds[, 1]),
  age_max = as.integer(ifelse(adult6_bounds[, 2] == 999, NA, adult6_bounds[, 2])),
  std_pop = mapply(group_sum, adult6_bounds[, 1], adult6_bounds[, 2])
)

brfss_std_pop_2000 <- rbind(age19, adult6)
brfss_std_pop_2000$std_weight <- stats::ave(
  brfss_std_pop_2000$std_pop,
  brfss_std_pop_2000$set,
  FUN = function(x) x / sum(x)
)
rownames(brfss_std_pop_2000) <- NULL
brfss_std_pop_2000 <- tibble::as_tibble(brfss_std_pop_2000)

# Anchors from the published tables (NCHS/NM-IBIS 11-group table in
# thousands: <1 = 3,795; 85+ = 4,259; Klein & Schoenborn's age-18+
# distribution rounds 18-24 to 0.128810).
stopifnot(
  brfss_std_pop_2000$std_pop[[1]] == 3794901,
  brfss_std_pop_2000$std_pop[[19]] == 4259173,
  brfss_std_pop_2000$std_pop[brfss_std_pop_2000$age_group == "18-24"] ==
    26258428,
  round(
    brfss_std_pop_2000$std_weight[brfss_std_pop_2000$age_group == "18-24"],
    6
  ) ==
    0.128811
)

save(
  brfss_states,
  file = "data/brfss_states.rda",
  compress = "xz",
  version = 2
)
save(
  brfss_std_pop_2000,
  file = "data/brfss_std_pop_2000.rda",
  compress = "xz",
  version = 2
)
message("wrote data/brfss_states.rda and data/brfss_std_pop_2000.rda")
