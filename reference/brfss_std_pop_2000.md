# The 2000 projected U.S. standard population

The year-2000 projected U.S. population (Census P25-1130) used for
direct age standardization, in the two groupings BRFSS work needs:
`set = "age19"` is NCHS's 19 standard five-year age groups (all ages),
and `set = "adult6"` is the adult population collapsed to BRFSS's
`_AGE_G` groups (18-24, 25-34, 35-44, 45-54, 55-64, 65+).

## Usage

``` r
brfss_std_pop_2000
```

## Format

A tibble with 25 rows and 6 columns:

- set:

  `"age19"` or `"adult6"`; use one set at a time.

- age_group:

  Label, e.g. `"18-24"`, `"85+"`.

- age_min,age_max:

  Group bounds in years; `age_max` is `NA` for the open-ended top group.

- std_pop:

  Standard population count.

- std_weight:

  `std_pop` normalized within the set (each set sums to 1).

Rows run in ascending age order within each set, so the `adult6` rows
are in `_AGE_G` code order (1 through 6), which is the order
[`survey::svystandardize()`](https://rdrr.io/pkg/survey/man/svystandardize.html)
expects for its `population` argument (it matches that vector to the
levels of `by` by position, without checking names).

## Source

Aggregated from SEER's single-age rendering of the Census P25-1130
year-2000 projected population,
<https://seer.cancer.gov/stdpopulations/>. Anchors verified against the
published tables: under-1 3,794,901; 85+ 4,259,173; the two adult groups
Klein & Schoenborn publish unsplit carry their weights (18-24 = 0.12881,
65+ = 0.17027). Klein RJ, Schoenborn CA. *Age adjustment using the 2000
projected U.S. population.* Healthy People 2010 Statistical Notes No.
20. Hyattsville, MD: NCHS; 2001.

## Details

`adult6` is the 2000 standard cut to `_AGE_G`, not a published
distribution in its own right: it is a finer partition of the ones that
are. Klein and Schoenborn's distribution \#9, which BRFSS uses, has five
groups with 45-64 combined (18-24 .128810, 25-34 .182648, 35-44 .219077,
45-64 .299194, 65+ .170271), and CDC's own guide to direct age
adjustment of BRFSS data specifies three (18-44 .530535, 45-64 .299194,
65+ .170271). To reproduce a CDC table adjusted with either, sum the
corresponding `adult6` rows: 45-54 and 55-64 give the 45-64 weight, and
the first three give the 18-44 weight, each within four units of the
last digit CDC prints (the sums are 0.5305366 and 0.2991955 against
.530535 and .299194, since these rows are the 2000 projection
re-aggregated rather than CDC's rounded figures copied). The difference
is far below anything an estimate shows. Adjusting with six groups
instead is a defensible choice, and a different one, so say which you
used.

## See also

The *Age-adjusted prevalence* article for the
[`survey::svystandardize()`](https://rdrr.io/pkg/survey/man/svystandardize.html)
workflow this table feeds.

## Examples

``` r
brfss_std_pop_2000
#> # A tibble: 25 × 6
#>    set   age_group age_min age_max  std_pop std_weight
#>    <chr> <chr>       <int>   <int>    <dbl>      <dbl>
#>  1 age19 <1              0       0  3794901     0.0138
#>  2 age19 1-4             1       4 15191619     0.0553
#>  3 age19 5-9             5       9 19919840     0.0725
#>  4 age19 10-14          10      14 20056779     0.0730
#>  5 age19 15-19          15      19 19819518     0.0722
#>  6 age19 20-24          20      24 18257225     0.0665
#>  7 age19 25-29          25      29 17722067     0.0645
#>  8 age19 30-34          30      34 19511370     0.0710
#>  9 age19 35-39          35      39 22179956     0.0808
#> 10 age19 40-44          40      44 22479229     0.0819
#> # ℹ 15 more rows
```
