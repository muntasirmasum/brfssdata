# Read BRFSS survey microdata

Returns respondent-level BRFSS data for one or more survey years as a
tibble. Each requested year is downloaded once into the local cache (see
[`brfss_cache_dir()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md))
and read from there afterwards; the query itself runs through DuckDB, so
selecting a handful of variables from a 300-plus column survey stays
fast.

Different survey years carry different variable sets. When years are
combined, variables absent from a year are filled with `NA`. A `year`
column always identifies the survey year of each row.

## Usage

``` r
read_brfss(years, vars = NULL, download = TRUE, quiet = FALSE, labels = FALSE)
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

- download:

  If `FALSE`, only cached years are used and missing years raise an
  error instead of being downloaded.

- quiet:

  If `TRUE`, suppress download progress output.

- labels:

  If `TRUE`, convert variables with safe value-label maps to factors
  using CDC's format libraries (available from 1998 on). A variable
  converts only when its format is a pure code-to-label map, its code
  set agrees across the requested years, and every observed value is
  covered; everything else keeps its numeric codes. See
  [`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md)
  for the raw catalog.

## Value

A tibble with one row per respondent and a `year` column.

## See also

[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
to get a survey-design object instead of a plain tibble.

## Examples

``` r
if (FALSE) { # interactive()
# General health and design variables for two years
dat <- read_brfss(2022:2023, vars = c("GENHLTH", "_LLCPWT"))
}
```
