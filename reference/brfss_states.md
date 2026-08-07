# BRFSS reporting jurisdictions: FIPS codes, names, and Census regions

Every jurisdiction that appears in the BRFSS `_STATE` value-label maps:
the 50 states, the District of Columbia, and the participating
territories (American Samoa, Guam, Palau, Puerto Rico, Virgin Islands).
`fips` matches the `_STATE` column in the data, so this table joins
directly onto any extract, and it is what the `states` argument of
[`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
and
[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
accepts names and postal abbreviations from.

## Usage

``` r
brfss_states
```

## Format

A tibble with 56 rows and 5 columns:

- fips:

  Census state FIPS code (integer), as in `_STATE`.

- name:

  Jurisdiction name, e.g. `"Texas"`.

- abbr:

  Two-letter postal abbreviation, e.g. `"TX"`.

- region:

  Census region (`Northeast`, `Midwest`, `South`, `West`); `NA` for
  territories, which the Census regions do not cover.

- division:

  Census division, e.g. `"West South Central"`; `NA` for territories.

## Source

Census state FIPS codes (FIPS PUB 5-2) and Census regions and divisions;
jurisdiction list cross-checked against CDC's `_STATE` format maps. Not
every jurisdiction participates every year; see the `datasets` article
for how reporting areas changed.

## See also

The `states` argument of
[`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
and
[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md);
the *Merging BRFSS with external data* article.

## Examples

``` r
brfss_states
#> # A tibble: 56 × 5
#>     fips name                 abbr  region    division          
#>    <int> <chr>                <chr> <chr>     <chr>             
#>  1     1 Alabama              AL    South     East South Central
#>  2     2 Alaska               AK    West      Pacific           
#>  3     4 Arizona              AZ    West      Mountain          
#>  4     5 Arkansas             AR    South     West South Central
#>  5     6 California           CA    West      Pacific           
#>  6     8 Colorado             CO    West      Mountain          
#>  7     9 Connecticut          CT    Northeast New England       
#>  8    10 Delaware             DE    South     South Atlantic    
#>  9    11 District of Columbia DC    South     South Atlantic    
#> 10    12 Florida              FL    South     South Atlantic    
#> # ℹ 46 more rows
```
