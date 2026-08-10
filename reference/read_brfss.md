# Read BRFSS survey microdata

Returns respondent-level BRFSS data for one or more survey years as a
tibble. Each requested year is downloaded once into the local cache (see
[`brfss_cache_dir()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md))
and read from there afterwards; the query itself runs through DuckDB, so
selecting a handful of variables from a 300-plus column survey stays
fast. Cached files are re-verified against the manifest's checksums at
most once a day per session; a file that no longer matches is announced
and re-downloaded verified. With `download = FALSE` nothing is checked,
nothing is downloaded, and nothing is ever deleted.

Different survey years carry different variable sets. When years are
combined, variables absent from a year are filled with `NA`. A `year`
column always identifies the survey year of each row.

## Usage

``` r
read_brfss(
  years,
  vars = NULL,
  states = NULL,
  download = TRUE,
  quiet = FALSE,
  labels = FALSE,
  na = FALSE
)
```

## Arguments

- years:

  Integer vector of survey years, e.g. `2023` or `2019:2023`. See
  [`brfss_years()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_years.md)
  for what is available.

- vars:

  Optional character vector of variable names to return. The default
  returns every variable. Names are matched case-insensitively
  (`"genhlth"` finds `GENHLTH`), and returned columns always carry CDC's
  canonical spelling. Use
  [`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md)
  to search names across years.

- states:

  Optional vector restricting rows to those reporting jurisdictions:
  state FIPS codes, postal abbreviations, or names, mixed freely and
  matched case-insensitively (`c(48, "CA", "maine")`). See
  [brfss_states](https://muntasirmasum.github.io/brfssdata/reference/brfss_states.md)
  for the full list. The filter is pushed into the DuckDB query, so
  other states' rows never reach R, and the `_STATE` column is always
  returned so the filter stays visible. A requested state absent from a
  requested year's file (states do occasionally miss a year) raises a
  classed warning rather than returning silently fewer rows.

- download:

  If `FALSE`, only cached years are used and missing years raise an
  error instead of being downloaded.

- quiet:

  If `TRUE`, suppress progress and housekeeping output: download
  progress, cache notes, the full-load hint, and the `na = TRUE` recode
  tally. Notes and warnings about what the data mean (renames,
  missing-code coverage, weight-domain subsetting) signal regardless of
  `quiet`; silence a specific one by its class, e.g.
  `suppressMessages(..., classes = "brfssdata_rename_note")`. See
  [brfssdata-conditions](https://muntasirmasum.github.io/brfssdata/reference/brfssdata-conditions.md)
  for every class.

- labels:

  Controls value-label conversion via CDC's format libraries (available
  from 1998 on). `FALSE` (the default) keeps every numeric code. `TRUE`
  converts variables with safe maps to factors; note the conversion is
  lossy: the CDC codes are gone, and
  [`as.numeric()`](https://rdrr.io/r/base/numeric.html) on the result
  returns factor level positions, not codes (most CDC code sets are
  non-contiguous, so the two disagree). `"both"` keeps the code in the
  level text (`"[1] Excellent"`) so it stays recoverable. A variable
  converts only when its format is a pure code-to-label map, its code
  set agrees across the requested years, every observed value is
  covered, and its label wording did not change meaning across those
  years; everything else keeps its numeric codes. Wording that did
  change (CDC reused `COLNTES1` codes 3 to 5 for different screening
  intervals from 2022 on) keeps its codes too, with a
  `brfssdata_label_drift_warning` naming the variables; read those years
  separately if you want each year's own wording. Levels come from the
  newest requested year, so purely cosmetic rewording is shown in CDC's
  most recent phrasing. Identifier and design columns (`_STATE`, the
  weights, strata, and PSU) always keep numeric codes so filters like
  `_STATE == 6` keep working. See
  [`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md)
  for the catalog.

- na:

  If `TRUE`, set the codes CDC uses for missing-type answers (don't know
  / not sure, refused, not asked) to `NA`, using the value-label
  catalog; see
  [`brfss_missing_codes()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_missing_codes.md)
  for exactly which codes. The default here is `FALSE`: `read_brfss()`
  returns the file as CDC published it.
  ([`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
  defaults to `TRUE`, because estimates over raw codes are almost never
  what an analyst wants.) Code 88/888 ("None") means zero, is never
  touched, and needs recoding to 0 by hand before averaging count
  variables. Labels cover 1998 on, so earlier years pass through
  unchanged and say so with a `brfssdata_na_coverage_warning` warning; a
  request touching a year the catalog covers only partially (like 1998)
  raises a `brfssdata_na_coverage_note` message rather than staying
  silent.

## Value

A tibble with one row per respondent and a `year` column.

## See also

[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
to get a survey-design object instead of a plain tibble;
[brfssdata-conditions](https://muntasirmasum.github.io/brfssdata/reference/brfssdata-conditions.md)
for the classes of every error, warning, and message this package
signals.

## Examples

``` r
if (FALSE) { # interactive()
# General health and design variables for two years
dat <- read_brfss(2022:2023, vars = c("GENHLTH", "_LLCPWT"))
}
```
