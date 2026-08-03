# Search BRFSS variables across survey years

BRFSS variable names and availability drift across years. This function
searches the variable catalog that accompanies the data releases and
reports, for each match, which years carry the variable. The catalog is
downloaded once and cached like the data itself.

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
tibble.

## Examples

``` r
if (FALSE) { # interactive()
brfss_vars("smok")
}
```
