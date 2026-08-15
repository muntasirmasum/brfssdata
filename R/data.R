#' BRFSS reporting jurisdictions: FIPS codes, names, and Census regions
#'
#' Every jurisdiction that appears in the BRFSS `_STATE` value-label
#' maps: the 50 states, the District of Columbia, and the participating
#' territories (American Samoa, Guam, Palau, Puerto Rico, Virgin
#' Islands). `fips` matches the `_STATE` column in the data, so this
#' table joins directly onto any extract, and it is what the `states`
#' argument of [read_brfss()] and [brfss_design()] accepts names and
#' postal abbreviations from.
#'
#' @format A tibble with 56 rows and 5 columns:
#' \describe{
#'   \item{fips}{Census state FIPS code (integer), as in `_STATE`.}
#'   \item{name}{Jurisdiction name, e.g. `"Texas"`.}
#'   \item{abbr}{Two-letter postal abbreviation, e.g. `"TX"`.}
#'   \item{region}{Census region (`Northeast`, `Midwest`, `South`,
#'     `West`); `NA` for territories, which the Census regions do not
#'     cover.}
#'   \item{division}{Census division, e.g. `"West South Central"`;
#'     `NA` for territories.}
#' }
#' @source Census state FIPS codes (FIPS PUB 5-2) and Census regions
#'   and divisions; jurisdiction list cross-checked against CDC's
#'   `_STATE` format maps. Not every jurisdiction participates every
#'   year; see the `datasets` article for how reporting areas changed.
#' @examples
#' brfss_states
#' @seealso The `states` argument of [read_brfss()] and
#'   [brfss_design()]; the *Merging BRFSS with external data* article.
"brfss_states"

#' The 2000 projected U.S. standard population
#'
#' The year-2000 projected U.S. population (Census P25-1130) used for
#' direct age standardization, in the two groupings BRFSS work needs:
#' `set = "age19"` is NCHS's 19 standard five-year age groups (all
#' ages), and `set = "adult6"` is the adult population collapsed to
#' BRFSS's `_AGE_G` groups (18-24, 25-34, 35-44, 45-54, 55-64, 65+).
#'
#' `adult6` is the 2000 standard cut to `_AGE_G`, not a published
#' distribution in its own right: it is a finer partition of the ones
#' that are. Klein and Schoenborn's distribution #9, which BRFSS uses,
#' has five groups with 45-64 combined (18-24 .128810, 25-34 .182648,
#' 35-44 .219077, 45-64 .299194, 65+ .170271), and CDC's own guide to
#' direct age adjustment of BRFSS data specifies three (18-44 .530535,
#' 45-64 .299194, 65+ .170271). To reproduce a CDC table adjusted with
#' either, sum the corresponding `adult6` rows: 45-54 and 55-64 give the
#' 45-64 weight, and the first three give the 18-44 weight, each to
#' within the published tables' rounding. Adjusting with six groups
#' instead is a defensible choice, and a different one, so say which you
#' used.
#'
#' @format A tibble with 25 rows and 6 columns:
#' \describe{
#'   \item{set}{`"age19"` or `"adult6"`; use one set at a time.}
#'   \item{age_group}{Label, e.g. `"18-24"`, `"85+"`.}
#'   \item{age_min,age_max}{Group bounds in years; `age_max` is `NA`
#'     for the open-ended top group.}
#'   \item{std_pop}{Standard population count.}
#'   \item{std_weight}{`std_pop` normalized within the set (each set
#'     sums to 1).}
#' }
#' Rows run in ascending age order within each set, so the `adult6`
#' rows are in `_AGE_G` code order (1 through 6), which is the order
#' `survey::svystandardize()` expects for its `population` argument
#' (it matches that vector to the levels of `by` by position, without
#' checking names).
#' @source Aggregated from SEER's single-age rendering of the Census
#'   P25-1130 year-2000 projected population,
#'   <https://seer.cancer.gov/stdpopulations/>. Anchors verified
#'   against the published tables: under-1 3,794,901; 85+ 4,259,173;
#'   the two adult groups Klein & Schoenborn publish unsplit carry
#'   their weights (18-24 = 0.12881, 65+ = 0.17027). Klein RJ,
#'   Schoenborn CA. *Age adjustment using the 2000 projected U.S.
#'   population.* Healthy People 2010 Statistical Notes No. 20.
#'   Hyattsville, MD: NCHS; 2001.
#' @examples
#' brfss_std_pop_2000
#' @seealso The *Age-adjusted prevalence* article for the
#'   `survey::svystandardize()` workflow this table feeds.
"brfss_std_pop_2000"
