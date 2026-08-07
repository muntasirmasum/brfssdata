# Codes CDC uses for missing-type answers

Returns the rows of the value-label catalog whose label marks a
missing-type answer: don't know / not sure, refused, or a
not-asked/missing placeholder. These are exactly the codes that
`na = TRUE` in
[`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
and
[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
sets to `NA`, so this function is the audit trail for that behavior, and
the join table for recoding by hand.

Matching is deliberately conservative. A label counts as missing when
every part of it (split on `/`, `,`, and the word "or") is a known
missing-answer phrase, or when the only parts beyond those phrases start
with the word "missing" and at least one part names the answer itself
(don't know / not sure / refused) – the shape of CDC's
calculated-variable buckets such as "Don't know, refused or missing
values" on `_FRTLT1A`. A short audited allowlist covers CDC's "component
question" wordings on the `RACE2` family. Substantive answers that
merely contain one of the words, such as "Doctor refused when asked" or
a bare "Missing Fruit Responses" exclusion flag, never match. Code
88/888 ("None") is an answer of zero, not missing, and is never matched;
recode it to 0 yourself before averaging a count variable such as
`PHYSHLTH`.

## Usage

``` r
brfss_missing_codes(vars = NULL, years = NULL, download = TRUE, quiet = TRUE)
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

A tibble with columns `year`, `variable`, `code`, and `label`, one row
per code the missing-value rules match. Labels cover 1998 on, so earlier
years never appear.

## See also

[`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md)
for the full catalog.

## Examples

``` r
brfss_missing_codes("GENHLTH", years = 2023, download = FALSE)
#> # A tibble: 2 × 4
#>    year variable  code label             
#>   <int> <chr>    <int> <chr>             
#> 1  2023 GENHLTH      9 Refused           
#> 2  2023 GENHLTH      7 Dont know/Not Sure
```
