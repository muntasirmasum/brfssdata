# Search BRFSS variables across survey years

BRFSS variable names and availability drift across years. This function
searches the variable catalog that accompanies the data releases and
reports, for each match, which years carry the variable. The catalog is
downloaded once and cached like the data itself.

A search that matches nothing says so and suggests near misses:
variables whose name or label is a small edit away (a typo'd pattern),
variables matching every word of a multi-word pattern in any order, and,
when `years` is given, matches that exist only in other years.

## Usage

``` r
brfss_vars(pattern = NULL, years = NULL, download = TRUE, quiet = TRUE)
```

## Arguments

- pattern:

  Optional single regular expression matched (case-insensitively)
  against variable names and labels. The default lists every variable.

- years:

  Optional integer vector restricting the search to particular survey
  years.

- download:

  If `FALSE`, only a cached catalog is used, and a missing catalog
  raises an error instead of being downloaded.

- quiet:

  If `TRUE`, suppress download progress output.

## Value

A tibble with one row per variable: `variable`, `label` (the most recent
non-missing label, since label text can drift across years), and `years`
(a compact summary of the years the variable appears in, e.g.
`"2011-2013, 2020"`). Searches that match nothing return a zero-row
tibble and say so with a `brfssdata_empty_result` message carrying the
suggestions described above.

## Examples

``` r
# download = FALSE reads the cached catalog, or the snapshot bundled
# with the package, so this runs offline.
brfss_vars("smok", download = FALSE)
#> # A tibble: 96 × 3
#>    variable label                                    years    
#>    <chr>    <chr>                                    <chr>    
#>  1 ALLOWADS PLACEMENT OF BILLBOARD ADS ABOUT SMOKING 1998     
#>  2 ATKNSMOK START SMOKING AFTER ATTK?                2002     
#>  3 ATKSMOK  SMOKE MORE AFTER ATTK?                   2002     
#>  4 BEGSMOKE AGE STARTED SMOKING REGULARLY            1991-1992
#>  5 BIDINOW  NOW SMOKE INDIAN CIGARETTES              2001-2003
#>  6 BIDISMK  EVER SMOKED INDIAN CIGARETTE             2001-2003
#>  7 CANCER   THINK SMOKELESS USE CAUSE MOUTH CANCER   1986     
#>  8 CIGAR    EVER SMOKED A CIGAR                      1998     
#>  9 CIGAR2   EVER SMOKED CIGAR                        2001-2003
#> 10 CIGARNOW CURRENTLY SMOKE CIGARS                   2001-2003
#> # ℹ 86 more rows
```
