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

Matching is deliberately conservative: a label counts as missing only
when every part of it (split on `/`, `,`, and the word "or") is a known
missing-answer phrase. Substantive answers that merely contain one of
the words, such as "Doctor refused when asked", never match. Code 88/888
("None") is an answer of zero, not missing, and is never matched; recode
it to 0 yourself before averaging a count variable such as `PHYSHLTH`.

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
if (FALSE) { # interactive()
brfss_missing_codes("GENHLTH", years = 2023)
}
```
