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
#> 1  2023 GENHLTH      1 Excellent          TRUE    
#> 2  2023 GENHLTH      2 Very good          TRUE    
#> 3  2023 GENHLTH      3 Good               TRUE    
#> 4  2023 GENHLTH      4 Fair               TRUE    
#> 5  2023 GENHLTH      5 Poor               TRUE    
#> 6  2023 GENHLTH      7 Dont know/Not Sure TRUE    
#> 7  2023 GENHLTH      9 Refused            TRUE
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
#> 1  2023 PHYSHLTH    77 Dont know/Not sure FALSE   
#> 2  2023 PHYSHLTH    88 None               FALSE   
#> 3  2023 PHYSHLTH    99 Refused            FALSE
```

Labels cover 1998 onward. CDC does not distribute usable format
libraries for earlier years, so neither switch has anything to work with
there. `labels = TRUE` leaves the variables numeric and says nothing
about it. `na = TRUE` does say something, because a silent no-op leaves
CDC’s don’t-know and refused codes sitting in the data as if they were
answers: a request touching a year with no catalog at all raises a
`brfssdata_na_coverage_warning`, and a year the catalog covers only
thinly, 1998 itself among them, raises a `brfssdata_na_coverage_note`.

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
#> 1  2023 GENHLTH      7 Dont know/Not Sure
#> 2  2023 GENHLTH      9 Refused
```

## Keeping don’t know apart from refused

Stata has extended missing values, `.a` through `.z`, and analysts
arriving from it expect don’t know and refused to survive as distinct
kinds of missing. R has one `NA`, so `na = TRUE` folds them together.
For 2023 `PHYSHLTH` that is 9,072 don’t-know answers and 1,710 refusals
arriving as the same thing, and a question about who declines to answer
can no longer be asked of the result.

The middle path is to read with `na = FALSE` and derive the distinction
from the catalog, which already carries the reason in its `label`
column. Join it on year and code, keep the reason in a column of its
own, and clear the value afterwards:

``` r

reasons <- brfss_missing_codes("PHYSHLTH", years = 2023) |>
  mutate(
    reason = case_when(
      startsWith(label, "Don") ~ "dont know",
      startsWith(label, "Refus") ~ "refused",
      .default = "other missing"
    )
  ) |>
  select(year, code, reason)

phys <- read_brfss(2023, vars = "PHYSHLTH", na = FALSE, quiet = TRUE) |>
  left_join(reasons, by = join_by(year, PHYSHLTH == code)) |>
  mutate(
    reason = factor(
      coalesce(reason, "answered"),
      levels = c("answered", "dont know", "refused", "other missing")
    ),
    PHYSHLTH = if_else(reason == "answered", PHYSHLTH, NA)
  )

count(phys, reason)
#> # A tibble: 3 × 2
#>   reason         n
#>   <fct>      <int>
#> 1 answered  422541
#> 2 dont know   9072
#> 3 refused     1710
```

`PHYSHLTH` is now what `na = TRUE` would have given, and `reason`
carries what was lost, so a nonresponse model or a sensitivity analysis
that treats refusal differently from don’t know still has its inputs.
Joining on `year` as well as code is what makes this safe across years,
since CDC’s codes for a variable are not guaranteed to hold still.

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

The `quiet` argument is a narrower control, and it does reach one of
these. It silences progress narration and the recode tally with it,
since the tally reports what a read did rather than cautioning about it.
The tally itself survives: `na = TRUE` attaches it to the result as the
`brfss_na_recode` attribute, one row per variable, year, and code, so a
quiet read is still auditable. Most dplyr verbs carry it along, but
[`summarise()`](https://dplyr.tidyverse.org/reference/summarise.html)
drops it, so read it off the object
[`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
returned rather than out of the middle of a pipeline.

``` r

recoded <- read_brfss(
  2023,
  vars = c("GENHLTH", "PHYSHLTH"),
  na = TRUE,
  quiet = TRUE
)

attr(recoded, "brfss_na_recode")
#> # A tibble: 4 × 4
#>   variable  year  code     n
#>   <chr>    <int> <dbl> <int>
#> 1 GENHLTH   2023     7   897
#> 2 GENHLTH   2023     9   361
#> 3 PHYSHLTH  2023    77  9072
#> 4 PHYSHLTH  2023    99  1710
```

The coverage and drift signals are not gated on `quiet` at all.
`brfssdata_na_coverage_warning`, `brfssdata_na_coverage_note`, and
`brfssdata_label_drift_warning` fire whatever it is set to, and are
silenced by class.
