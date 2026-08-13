# Value labels and missing codes

BRFSS answers arrive as numeric codes. A `1` in `GENHLTH` means
“Excellent”, a `7` means “Don’t know / Not sure”, and nothing in the
file itself says so; the meanings live in CDC’s SAS format libraries,
one per survey year. brfssdata ships those meanings as a catalog and
gives you two switches that use it, `labels` and `na`. This article is
the full tour of both, including the places where the package
deliberately refuses to convert and the one trap the catalog cannot
catch for you.

``` r

library(brfssdata)
library(dplyr)
```

## The label catalog

[`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md)
returns the catalog as a plain table, one row per year, variable, and
code. It is data, not magic: everything the `labels` and `na` switches
do is an audit-able lookup against these rows.

``` r

brfss_labels("GENHLTH", years = 2023)
#> # A tibble: 7 × 5
#>    year variable  code label              complete
#>   <int> <chr>    <int> <chr>              <lgl>   
#> 1  2023 GENHLTH      4 Fair               TRUE    
#> 2  2023 GENHLTH      3 Good               TRUE    
#> 3  2023 GENHLTH      9 Refused            TRUE    
#> 4  2023 GENHLTH      7 Dont know/Not Sure TRUE    
#> 5  2023 GENHLTH      1 Excellent          TRUE    
#> 6  2023 GENHLTH      2 Very good          TRUE    
#> 7  2023 GENHLTH      5 Poor               TRUE
```

The `complete` column marks formats that are pure code-to-label maps.
`PHYSHLTH` is the classic counterexample: its substantive values are a
count of days, so CDC’s format documents only the special codes and
`complete` is `FALSE`.

``` r

brfss_labels("PHYSHLTH", years = 2023)
#> # A tibble: 3 × 5
#>    year variable  code label              complete
#>   <int> <chr>    <int> <chr>              <lgl>   
#> 1  2023 PHYSHLTH    88 None               FALSE   
#> 2  2023 PHYSHLTH    77 Dont know/Not sure FALSE   
#> 3  2023 PHYSHLTH    99 Refused            FALSE
```

Labels cover 1998 onward. CDC does not distribute usable format
libraries for earlier years, so both switches quietly have nothing to
work with there (a coverage note tells you when a request touches those
years).

## labels = TRUE: conversion, conservatively

Setting `labels = TRUE` on
[`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
or
[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
converts eligible variables to factors.

``` r

read_brfss(2023, vars = c("GENHLTH", "SEXVAR"), labels = TRUE)
#> # A tibble: 433,323 × 3
#>    GENHLTH   SEXVAR  year
#>    <fct>     <fct>  <int>
#>  1 Very good Female  2023
#>  2 Very good Female  2023
#>  3 Fair      Female  2023
#>  4 Very good Female  2023
#>  5 Fair      Female  2023
#>  6 Good      Female  2023
#>  7 Fair      Male    2023
#>  8 Fair      Female  2023
#>  9 Good      Female  2023
#> 10 Good      Male    2023
#> # ℹ 433,313 more rows
```

A variable converts only when every one of these holds for the requested
years:

- its CDC format is `complete` (a pure code-to-label map, no numeric
  ranges),
- the map is one-to-one in both directions (some CDC formats give one
  code several labels, or reuse one label across codes, and converting
  those would quietly rewrite the data),
- the code set is identical across the requested years,
- every value observed in the data is covered by the map,
- and the wording of each code did not change meaning across those years
  (cosmetic rewording is fine and arrives in the latest year’s phrasing;
  a real meaning change triggers a `brfssdata_label_drift_warning` and
  the variable stays numeric).

Everything else is left as numeric codes. `PHYSHLTH` never converts,
because turning a count of days into a factor would destroy it.

`labels = "both"` keeps the code visible inside each level, the haven
convention, so factor output stays easy to join back to code-based
recodes.

``` r

read_brfss(2023, vars = "GENHLTH", labels = "both", na = TRUE) |>
  count(GENHLTH)
#> # A tibble: 6 × 2
#>   GENHLTH            n
#>   <fct>          <int>
#> 1 [1] Excellent  63410
#> 2 [2] Very good 142115
#> 3 [3] Good      144209
#> 4 [4] Fair       61955
#> 5 [5] Poor       20372
#> 6 NA              1262
```

## Missing-type codes become NA with `na = TRUE`

Labeling renames codes; deciding which of them mean missing is a
separate decision, and the package keeps it separate. With `na = FALSE`
the don’t-know and refused codes become factor levels like any other,
which is why a labeled `GENHLTH` has seven levels instead of five.
`na = TRUE` sets the codes CDC uses for missing-type answers (don’t
know, refused, not asked, blank) to `NA` first, using the same catalog.

``` r

read_brfss(2023, vars = "GENHLTH", labels = TRUE, na = TRUE) |>
  count(GENHLTH)
#> # A tibble: 6 × 2
#>   GENHLTH        n
#>   <fct>      <int>
#> 1 Excellent  63410
#> 2 Very good 142115
#> 3 Good      144209
#> 4 Fair       61955
#> 5 Poor       20372
#> 6 NA          1262
```

The two entry points deliberately default differently:

- `read_brfss(na = FALSE)`: the raw-file contract. You get the file as
  CDC published it, codes and all.
- `brfss_design(na = TRUE)`: the analysis contract. An estimate whose
  denominator includes “Refused” is almost never the estimate anyone
  wants.

[`brfss_missing_codes()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_missing_codes.md)
lists exactly which year, variable, and code combinations the switch
clears, so the behavior is auditable.

``` r

brfss_missing_codes("GENHLTH", years = 2023)
#> # A tibble: 2 × 4
#>    year variable  code label             
#>   <int> <chr>    <int> <chr>             
#> 1  2023 GENHLTH      9 Refused           
#> 2  2023 GENHLTH      7 Dont know/Not Sure
```

## The 88 trap: “None” is an answer, not a missing code

CDC’s count variables use `88` (or `888`) for “None”. That is a real
answer of zero, so `na = TRUE` correctly leaves it alone, and that
correctness bites anyone who averages the column as-is: with 77 and 99
cleared, the healthiest respondents still carry the value 88, and mean
“days of poor physical health” comes out absurdly high. Recode it
yourself, on purpose, before any arithmetic:

``` r

dat <- read_brfss(2023, vars = "PHYSHLTH", na = TRUE) |>
  mutate(PHYSHLTH = replace(PHYSHLTH, PHYSHLTH == 88, 0))
mean(dat$PHYSHLTH, na.rm = TRUE)
#> [1] 4.482591
```

## NA-cleared data changes how comparisons behave

One consequence of `na = TRUE` worth internalizing: `%in%` folds `NA` to
`FALSE`. After clearing, `GENHLTH %in% c(4, 5)` silently classifies
every missing answer as “not fair/poor”, which is a claim about people
who refused to answer. Comparisons that propagate `NA`, like
`GENHLTH >= 4`, keep the missingness honest, and survey estimators then
handle it explicitly.

``` r

dat <- read_brfss(2023, vars = "GENHLTH", na = TRUE)
# NA stays NA:
table(dat$GENHLTH >= 4, useNA = "ifany") |> head()
#> 
#>  FALSE   TRUE   <NA> 
#> 349734  82327   1262
# NA becomes FALSE, silently:
table(dat$GENHLTH %in% c(4, 5), useNA = "ifany") |> head()
#> 
#>  FALSE   TRUE 
#> 350996  82327
```

## Controlling the console

Both switches narrate what they did through classed conditions, so you
can silence or capture exactly the signals you mean to. The recode tally
is a `brfssdata_na_note`; the pre-1998 coverage signals are
`brfssdata_na_coverage_note` and `brfssdata_na_coverage_warning`; label
drift is `brfssdata_label_drift_warning`. The full catalog is in
`?brfssdata-conditions`.

``` r

withCallingHandlers(
  des <- brfss_design(2019:2023, vars = "GENHLTH"),
  brfssdata_na_note = function(cnd) {
    invokeRestart("muffleMessage")
  }
)
```

The `quiet` argument, by contrast, governs progress narration only.
Analytical signals, including everything above, fire regardless, and are
silenced by class, never by `quiet = TRUE`.
