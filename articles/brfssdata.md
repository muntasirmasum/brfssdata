# Getting started with brfssdata

The Behavioral Risk Factor Surveillance System (BRFSS) is the CDC’s
annual state-based health survey, fielded continuously since 1984 with
roughly 400,000 adult respondents per year in recent releases. brfssdata
turns the annual public-use files into something you can query from R in
seconds: each survey year lives as a compact parquet file on a public
release, is downloaded once into a local cache, and is queried through
DuckDB so you transfer only the years and variables you ask for.

The code below is shown unevaluated in the installed vignette so the
package builds without network access; run it interactively.

## Which years are available?

``` r

library(brfssdata)
brfss_years()
```

## Reading respondent-level data

[`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
returns a tibble. A `year` column always identifies the survey year, and
when several years are combined, variables missing from a year are
filled with `NA` (BRFSS variable sets drift over time).

``` r

dat <- read_brfss(2019:2023, vars = c("GENHLTH", "PHYSHLTH"))
```

The first request for a year downloads it into
[`brfss_cache_dir()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md);
after that everything, including offline work, reads from the cache.
[`brfss_cache_info()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
shows what is stored and
[`brfss_cache_clear()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
removes it.

## Finding variables

Variable names and availability change across years.
[`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md)
searches names and labels and reports the years each variable appears
in.

``` r

brfss_vars("smok")
```

## Survey-weighted analysis

BRFSS is a complex survey: analyses need the sampling weights, strata,
and primary sampling units.
[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
returns a srvyr design object with all of that applied, choosing the
weight that matches the survey era.

``` r

library(srvyr)

brfss_design(2023, vars = "GENHLTH") |>
  group_by(GENHLTH) |>
  summarize(prop = survey_prop(vartype = "ci"))
```

Pooling several years divides the weights by the number of years (an
average-year interpretation); disable with `pool_weights = FALSE`.

## The 2011 boundary

In 2011 BRFSS added cell-phone-only respondents and moved from
post-stratification to raking; the final weight changed from `_FINALWT`
to `_LLCPWT`, and CDC warns that estimates are not directly comparable
across that boundary.
[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
enforces the boundary: a request spanning it fails unless you opt in.

``` r

# Errors on purpose:
brfss_design(2009:2013)

# Deliberate pooling, with a warning:
brfss_design(2009:2013, allow_break = TRUE)
```

## Citing the data

> Centers for Disease Control and Prevention (CDC). Behavioral Risk
> Factor Surveillance System Survey Data. Atlanta, Georgia: U.S.
> Department of Health and Human Services, Centers for Disease Control
> and Prevention, \[appropriate year\].
