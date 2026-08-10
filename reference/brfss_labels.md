# Value labels for BRFSS variables

Returns the value-label catalog that accompanies the data releases: one
row per year, variable, and numeric code, with the label text from CDC's
SAS format libraries. Labels cover 1998 onward; CDC does not distribute
usable format libraries for earlier years.

The `complete` column marks variables whose format for that year is a
pure code-to-label map (no numeric ranges such as `1-30` days). Only
those variables are eligible for automatic factor conversion via
`read_brfss(labels = TRUE)`; for the rest, the catalog still documents
the special codes (typically 77/88/99) so you can recode by hand.

## Usage

``` r
brfss_labels(vars = NULL, years = NULL, download = TRUE, quiet = TRUE)
```

## Arguments

- vars:

  Optional character vector restricting to those variables, matched
  case-insensitively by exact name. (Contrast
  [`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md),
  whose `pattern` is a regular expression searched over names *and*
  label text: this function looks names up, that one searches.)

- years:

  Optional integer vector restricting to those years.

- download:

  If `FALSE`, only a cached catalog is used, and a missing catalog
  raises an error instead of being downloaded.

- quiet:

  If `TRUE`, suppress download progress output.

## Value

A tibble with columns `year`, `variable`, `code`, `label`, and
`complete`. A lookup that matches nothing returns zero rows and says so
with a `brfssdata_empty_result` message (regardless of `quiet`, which
governs download output only). When only some requested variables match,
the matching rows are returned and a `brfssdata_partial_match_note`
message names the ones with no entries, also regardless of `quiet`.

## Examples

``` r
# download = FALSE reads the cached catalog, or the snapshot bundled
# with the package, so this runs offline.
brfss_labels("GENHLTH", years = 2023, download = FALSE)
#> # A tibble: 7 × 5
#>    year variable  code label              complete
#>   <int> <chr>    <int> <chr>              <lgl>   
#> 1  2023 GENHLTH      4 Fair               TRUE    
#> 2  2023 GENHLTH      3 Good               TRUE    
#> 3  2023 GENHLTH      9 Refused            TRUE    
#> 4  2023 GENHLTH      7 Dont know/Not Sure TRUE    
#> 5  2023 GENHLTH      1 Excellent          TRUE    
#> 6  2023 GENHLTH      2 Very good          TRUE    
#> 7  2023 GENHLTH      5 Poor               TRUE    
```
