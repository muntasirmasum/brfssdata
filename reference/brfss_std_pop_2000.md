# The 2000 projected U.S. standard population

The year-2000 projected U.S. population (Census P25-1130) used for
direct age standardization, in the two groupings BRFSS work needs:
`set = "age19"` is NCHS's 19 standard five-year age groups (all ages),
and `set = "adult6"` is the adult population collapsed to BRFSS's
`_AGE_G` groups (18-24, 25-34, 35-44, 45-54, 55-64, 65+), matching the
distribution CDC uses to age-adjust adult BRFSS prevalence estimates
(Klein & Schoenborn's age-18-and-over distribution).

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

## Source

Aggregated from SEER's single-age rendering of the Census P25-1130
year-2000 projected population,
<https://seer.cancer.gov/stdpopulations/>. Anchors verified against the
published tables: under-1 3,794,901; 85+ 4,259,173; the adult set
reproduces Klein & Schoenborn's 18-and-over weights (18-24 = 0.12881).
Klein RJ, Schoenborn CA. *Age adjustment using the 2000 projected U.S.
population.* Healthy People 2010 Statistical Notes No. 20. Hyattsville,
MD: NCHS; 2001.

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
