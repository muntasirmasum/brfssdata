# Age-adjusted prevalence

Most published BRFSS prevalence estimates are age-adjusted, and most
first analyses of the microdata are not, which is the usual reason the
two disagree. Health outcomes vary strongly with age, and places differ
in how old their residents are, so a crude comparison of two states, or
of one state over twenty years, mixes the thing being measured with the
age structure it sits on. Direct standardization removes that mix-up by
re-weighting every estimate to one fixed population, and the fixed
population everyone uses is the year-2000 projected U.S. population
(Klein and Schoenborn, 2001).

This package ships that standard as data and leaves the arithmetic to
[`survey::svystandardize()`](https://rdrr.io/pkg/survey/man/svystandardize.html),
which already does it correctly. The contribution here is the right
table and the worked pattern, not another implementation.

## The standard population

`brfss_std_pop_2000` carries the 2000 projected U.S. population in two
groupings. `set = "age19"` is NCHS’s 19 five-year groups covering all
ages. `set = "adult6"` collapses the adult population to the exact
groups of BRFSS’s calculated variable `_AGE_G` (18-24, 25-34, 35-44,
45-54, 55-64, 65 and over), which is what adult BRFSS prevalence work
needs.

``` r

library(brfssdata)

std <- subset(brfss_std_pop_2000, set == "adult6")
std
#>       set age_group age_min age_max  std_pop std_weight
#> 20 adult6     18-24      18      24 26258428  0.1288111
#> 21 adult6     25-34      25      34 37233437  0.1826492
#> 22 adult6     35-44      35      44 44659185  0.2190763
#> 23 adult6     45-54      45      54 37030152  0.1816520
#> 24 adult6     55-64      55      64 23961506  0.1175435
#> 25 adult6       65+      65      NA 34709480  0.1702679
```

The weights reproduce the age-18-and-over distribution in Klein and
Schoenborn’s Statistical Note 20, the same distribution CDC uses to
age-adjust adult BRFSS estimates.

## Crude and adjusted, one year

`_AGE_G` codes 1 through 6 correspond, in order, to the six rows of the
`adult6` set, so the design carries everything standardization needs.
Two preparation steps go in one
[`mutate()`](https://dplyr.tidyverse.org/reference/mutate.html).
`survey`’s post-stratification machinery wants syntactic, factor-typed
grouping variables, and CDC’s names are neither, so make a plain copy of
the age variable first (the same reason
[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
builds itself on `brfss_wt` and friends). The outcome gets its own
column at the same time, because
[`svystandardize()`](https://rdrr.io/pkg/survey/man/svystandardize.html)
has to be told which variable the estimate will use (see Cautions).

Take the factor labels from the standard-population table rather than
writing them out.
[`svystandardize()`](https://rdrr.io/pkg/survey/man/svystandardize.html)
matches `population` to the levels of `by` by position and never checks
names, so a table sorted some other way is silently wrong rather than an
error. What the whole pattern rests on is that `std` runs in ascending
age order, which makes its row *i* the row for `_AGE_G` code *i*. The
[`stopifnot()`](https://rdrr.io/r/base/stopifnot.html) below costs
nothing and says so out loud, which matters if you filter or re-sort the
table on the way in.

``` r

library(srvyr)
library(survey)

des <- brfss_design(2023, vars = c("GENHLTH", "_AGE_G"), quiet = TRUE) |>
  mutate(
    age_group = factor(`_AGE_G`, levels = 1:6, labels = std$age_group),
    fair_poor = GENHLTH >= 4
  )

stopifnot(!is.unsorted(std$age_min))
```

The crude estimate first. Codes CDC uses for don’t know and refused are
already `NA` here (`na = TRUE` is the design default), so `fair_poor` is
fair-or-poor health over substantive answers.

``` r

des |>
  summarize(fair_poor = survey_mean(fair_poor, na.rm = TRUE))
#> # A tibble: 1 × 2
#>   fair_poor fair_poor_se
#>       <dbl>        <dbl>
#> 1     0.194      0.00139
```

[`svystandardize()`](https://rdrr.io/pkg/survey/man/svystandardize.html)
re-weights the design so its age distribution matches the standard, and
everything downstream works as before:

``` r

std_des <- svystandardize(
  des,
  by = ~age_group,
  over = ~1,
  population = std$std_pop,
  excluding.missing = ~ fair_poor + age_group
)

svymean(~fair_poor, std_des, na.rm = TRUE)
#>                   mean     SE
#> fair_poorFALSE 0.81538 0.0014
#> fair_poorTRUE  0.18462 0.0014
```

Over the whole 2023 file the two differ modestly, because the sample’s
weighted age distribution sits near the 2000 standard. The adjustment
earns its keep in comparisons.

## Comparing states with different age structures

Florida’s adult population is much older than Utah’s, and fair-or-poor
health rises steeply with age, so the crude comparison mixes health with
demography. The `states` argument keeps the extract small, and filtering
by state before the design is built is variance-exact because BRFSS
strata nest within state.

``` r

two <- brfss_design(
  2023,
  vars = c("GENHLTH", "_AGE_G"),
  states = c("FL", "UT"),
  quiet = TRUE
) |>
  mutate(
    age_group = factor(`_AGE_G`, levels = 1:6, labels = std$age_group),
    fair_poor = GENHLTH >= 4,
    state = factor(`_STATE`)
  )

stopifnot(!is.unsorted(std$age_min))

two |>
  group_by(state) |>
  summarize(fair_poor = survey_mean(fair_poor, na.rm = TRUE))
#> # A tibble: 2 × 3
#>   state fair_poor fair_poor_se
#>   <fct>     <dbl>        <dbl>
#> 1 12        0.191      0.00739
#> 2 49        0.143      0.00451
```

Crudely, Florida (FIPS 12) sits near 19 percent and Utah (FIPS 49) near
14. Standardizing within each state (`over = ~state`) puts both on the
2000 age distribution:

``` r

two_std <- svystandardize(
  two,
  by = ~age_group,
  over = ~state,
  population = std$std_pop,
  excluding.missing = ~ fair_poor + age_group
)

svyby(~fair_poor, ~state, two_std, svymean, na.rm = TRUE)
#>    state fair_poorFALSE fair_poorTRUE se.fair_poorFALSE se.fair_poorTRUE
#> 12    12      0.8226126     0.1773874       0.007687164      0.007687164
#> 49    49      0.8569790     0.1430210       0.004392674      0.004392674
```

Florida’s estimate drops by more than a point once its older age
structure no longer counts against it, while Utah’s barely moves; about
a third of the crude gap between the two states was age, not health.
What survives adjustment is the number to compare across states, and the
number CDC’s own age-adjusted tables report.

## Cautions

`excluding.missing` has to name every variable the estimate will use,
the outcome included.
[`svystandardize()`](https://rdrr.io/pkg/survey/man/svystandardize.html)
drops the rows that are missing on any variable in that formula and then
computes the age weights over the survivors, so a variable left out of
the formula is still carrying age weight at the moment `na.rm = TRUE`
throws its row away. What comes back is then an average of the age-group
means weighted by each group’s standard share times its weighted
response rate, where direct standardization weights by the standard
share alone. The two coincide only when item nonresponse is flat across
the age groups, and it generally is not. Naming the age variable as
well, as `~ fair_poor + age_group` does above, is also what makes the
requirement of a complete age variable actually bite; `_AGE_G` is
imputed by CDC and is complete in modern files, so nothing is dropped on
that account here.

The consequence is that a standardized design belongs to one outcome.
Build a fresh `std_des` for each measure instead of reusing one across
several, since the calibration is specific to the rows that measure
answers. The discrepancy is small when an item is nearly complete and
grows with age-patterned nonresponse, and it is largest for questions
that sit behind a skip pattern and are put to only part of the sample.
Standardizing such an outcome puts the eligible subpopulation on the
standard age distribution, which is the comparison that was wanted.

Standardize before estimating subgroups, and note that a subgroup’s
standardized estimate uses the standard’s age distribution, not the
subgroup’s own. CDC’s published age-adjusted figures occasionally use a
measure-specific age grouping rather than the six-group standard, so
when matching a published table exactly, check the measure’s
documentation first; the `age19` set covers the finer groupings.

The whole-file estimates above are not fifty-state figures. The 2023
public-use file covers 52 reporting areas, 48 states plus the District
of Columbia, Guam, Puerto Rico, and the U.S. Virgin Islands, with
Kentucky and Pennsylvania absent that year.
[`brfss_year_info()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_year_info.md)
reports the jurisdiction count for every year in its `states` column,
and the `datasets` article traces how coverage moved across the series;
pass `states =` when the write-up claims a specific universe.

Age adjustment is for comparison, not description. The crude estimate
remains the actual burden in the population, and reports usually show
both.

## Sources

Klein RJ, Schoenborn CA. *Age adjustment using the 2000 projected U.S.
population.* Healthy People 2010 Statistical Notes, No. 20. Hyattsville,
Maryland: National Center for Health Statistics, 2001.

The table itself is aggregated from SEER’s single-age rendering of the
Census P25-1130 projection (<https://seer.cancer.gov/stdpopulations/>),
with the anchors verified against the published group tables; see
[`?brfss_std_pop_2000`](https://muntasirmasum.github.io/brfssdata/reference/brfss_std_pop_2000.md).
