# Rename crosswalk: which variables are generations of one measure

CDC renames a variable when its definition or its questionnaire context
changes, usually by bumping a trailing digit: `_DRNKWK1` becomes
`_DRNKWK2` becomes `_DRNKWK3`. A multi-year analysis that requests only
one of those names silently loses the other years. This function returns
the crosswalk that accompanies the data releases: variables grouped into
concept families, one row per variable and year, so the whole family is
visible at once.

Families are proposed mechanically (same stem, non-overlapping year
ranges, similar label wording) and reviewed by hand against CDC's
codebooks over time. `status` records how far that review has gone for
each family: `"verified"` means a person checked it, `"candidate"` means
the rules proposed it and review is pending, so treat a candidate family
as a strong hint, not a fact. For verified pairs, `comparable` records
the outcome: `TRUE` when the definitions match the previous generation,
`FALSE` when they do not (with `note` saying what changed); it stays
`NA` while unreviewed. A rename is *never* a promise of comparability –
CDC renamed the variable for a reason – so combining generations is
always your decision;
[`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
points here (a `brfssdata_rename_note` message) when a requested
variable is empty in years a sibling generation covers.

## Usage

``` r
brfss_crosswalk(vars = NULL, years = NULL, download = TRUE, quiet = TRUE)
```

## Arguments

- vars:

  Optional character vector of variable names, matched
  case-insensitively by exact name like in
  [`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md).
  A match on *any* member of a family returns the whole family – that is
  the point of the lookup.

- years:

  Optional integer vector restricting the `year` rows. The family
  membership shown is unaffected; only rows are filtered.

- download:

  If `FALSE`, only a cached catalog is used, and a missing catalog
  raises an error instead of being downloaded.

- quiet:

  If `TRUE`, suppress download progress output.

## Value

A tibble with columns `concept` (family identifier), `variable`, `year`,
`generation` (1, 2, ... in order of first appearance), `status`,
`comparable`, and `note`, one row per variable-year. A lookup that
matches nothing returns zero rows with a `brfssdata_empty_result`
message.

## See also

[`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md)
to search variables;
[`brfss_codebook()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_codebook.md)
for a per-variable summary that includes the family.

## Examples

``` r
# The whole family, from any member's name. download = FALSE reads
# the cached copy, or the snapshot bundled with the package, so this
# runs offline.
brfss_crosswalk("_DRNKWK1", download = FALSE)
#> ! Using the rename crosswalk snapshot bundled with the package (frozen at
#>   release); `brfss_download()` caches the current copy.
#> # A tibble: 6 × 7
#>   concept variable  year generation status   comparable note                    
#>   <chr>   <chr>    <int>      <int> <chr>    <lgl>      <chr>                   
#> 1 drnkwk  _DRNKWK1  2019          1 verified NA         ""                      
#> 2 drnkwk  _DRNKWK1  2020          1 verified NA         ""                      
#> 3 drnkwk  _DRNKWK1  2021          1 verified NA         ""                      
#> 4 drnkwk  _DRNKWK2  2022          2 verified TRUE       "The input question dro…
#> 5 drnkwk  _DRNKWK2  2023          2 verified TRUE       "The input question dro…
#> 6 drnkwk  _DRNKWK3  2024          3 verified TRUE       "Renamed with AVEDRNK3-…
```
