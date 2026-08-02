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
  case-insensitively.

- years:

  Optional integer vector restricting to those years.

- download:

  If `FALSE`, only cached years are used and missing years raise an
  error instead of being downloaded.

- quiet:

  If `TRUE`, suppress download progress output.

## Value

A tibble with columns `year`, `variable`, `code`, `label`, and
`complete`.

## Examples

``` r
if (FALSE) { # interactive()
brfss_labels("GENHLTH", years = 2023)
}
```
