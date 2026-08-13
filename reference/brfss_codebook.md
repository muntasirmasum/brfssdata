# Codebook card: everything the catalogs know about a variable

One row per requested variable, joining the three metadata catalogs: the
variable catalog (label wording and year availability), the value-label
catalog (codes and their meanings, with the missing-type codes flagged),
and the rename crosswalk (the variable's concept family, if it belongs
to one). It answers "what is this variable" in one call; use
[`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md)
to *find* variables first.

Printing renders a card per variable, capped at 10 cards by default;
`print(x, n = Inf)` renders every card. The returned object is still a
regular tibble; the `values` and `missing_codes` columns are
list-columns of tibbles, `related` a list-column of sibling variable
names.

## Usage

``` r
brfss_codebook(vars, years = NULL, download = TRUE, quiet = TRUE)
```

## Arguments

- vars:

  Character vector of variable names, matched case-insensitively by
  exact name (required – for browsing the whole catalog use
  [`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md)).

- years:

  Optional integer vector: restrict the value-label and availability
  detail to those years.

- download:

  If `FALSE`, only a cached catalog is used, and a missing catalog
  raises an error instead of being downloaded.

- quiet:

  If `TRUE`, suppress download progress output.

## Value

A tibble of class `brfss_codebook` with columns `variable`, `label`
(most recent wording), `years` (compact range string), `values`
(list-column: `year`, `code`, `label`, `complete`, `missing` per row),
`missing_codes` (list-column, the `missing` subset), `concept`, and
`related` (list-column of sibling generations from the crosswalk).

## Details

The card documents codes and labels only. It carries no units, no scale
factor, and no valid range, so a calculated variable CDC stores scaled
(`_BMI5` and `_DRNKWK2` carry two implied decimals) looks no different
here from an unscaled one, and a range format lists its special codes
without the ordinary values around them. Read magnitudes against CDC's
codebook for the year, whose address is
`brfss_year_info()$codebook_url`.

## See also

[`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md),
[`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md),
[`brfss_missing_codes()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_missing_codes.md),
[`brfss_crosswalk()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_crosswalk.md).

## Examples

``` r
brfss_codebook("GENHLTH", years = 2023, download = FALSE)
#> ! Using the rename crosswalk snapshot bundled with the package (frozen at
#>   release); `brfss_download()` caches the current copy.
#> ── GENHLTH ─────────────────────────────────────────────────────────────────────
#> GENERAL HEALTH
#> Years: 2023
#> Values (2023):
#>   1: Excellent
#>   2: Very good
#>   3: Good
#>   4: Fair
#>   5: Poor
#>   7: Dont know/Not Sure [missing-type]
#>   9: Refused [missing-type]
#> 
```
