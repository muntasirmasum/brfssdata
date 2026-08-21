# Validating against CDC's published estimates

A data package asks to be trusted twice: that the bytes it serves are
the bytes it published, and that estimates computed from them reproduce
what the data’s owner reports. The first is mechanical and automatic
here. The second is checkable in a few lines, and this article shows
how, because the strongest validation is the one you run yourself.

## The bytes

Every hosted file has a published sha256, twice over. The data manifest
carries a per-asset hash that
[`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
verifies on every download, and each release asset also has a plain
`.sha256` sidecar next to it. Both records come from the same hashing
step at publish time, so the sidecar is a second copy, not a second
opinion. What it catches is drift: a manifest and an asset that no
longer agree after a partial republish, or either file corrupted in
transport or storage. A weekly integration job downloads real years
fresh, verifies the sidecars against the downloaded bytes, re-asserts
the recorded row counts, and computes the known-answer estimate below;
the package does not ship until that passes.

## Reproducing a published prevalence

CDC publishes design-based BRFSS estimates in the Prevalence & Trends
tool (<https://www.cdc.gov/brfss/brfssprevalence/>). For 2023, Health
Status, the published share of adults reporting fair or poor general
health is 19.4 percent. The same figure from this package:

``` r

library(brfssdata)
library(srvyr)

des <- brfss_design(2023, vars = "GENHLTH", quiet = TRUE)

des |>
  summarize(fair_poor = survey_mean(GENHLTH >= 4, na.rm = TRUE, vartype = "ci"))
#> # A tibble: 1 × 3
#>   fair_poor fair_poor_low fair_poor_upp
#>       <dbl>         <dbl>         <dbl>
#> 1     0.194         0.191         0.196
```

Two details make this line match the published figure. The design
carries the era-correct weight, strata, and PSUs, and `na = TRUE` (the
default here) has set the don’t-know and refused codes to `NA`, so
`GENHLTH >= 4` divides fair-or-poor by substantive answers, which is the
denominator CDC uses. Run the same check on any measure you are about to
build a paper on; if you cannot reproduce the published number, resolve
that before going further.

## Reliability screening

CDC suppresses BRFSS estimates built on fewer than 50 respondents or
with a relative standard error above 30 percent, and reviewers
increasingly expect the same screen. Both inputs come straight from a
srvyr summary, with
[`unweighted()`](http://gdfe.co/srvyr/reference/unweighted.md) supplying
the denominator that suppression rules actually mean (respondents, not
weighted counts):

``` r

library(dplyr)

screened <- brfss_design(
  2023,
  vars = c("GENHLTH", "_AGE_G"),
  states = "VT",
  quiet = TRUE
) |>
  group_by(`_AGE_G`) |>
  summarize(
    fair_poor = survey_mean(GENHLTH >= 4, na.rm = TRUE, vartype = c("se", "cv")),
    n_unweighted = unweighted(sum(!is.na(GENHLTH)))
  ) |>
  mutate(
    suppress = n_unweighted < 50 | fair_poor_cv > 0.30
  )

screened
#> # A tibble: 6 × 6
#>   `_AGE_G` fair_poor fair_poor_se fair_poor_cv n_unweighted suppress
#>      <dbl>     <dbl>        <dbl>        <dbl>        <int> <lgl>   
#> 1        1     0.101       0.0219       0.217           256 FALSE   
#> 2        2     0.105       0.0142       0.135           604 FALSE   
#> 3        3     0.120       0.0176       0.146           910 FALSE   
#> 4        4     0.135       0.0133       0.0981         1058 FALSE   
#> 5        5     0.177       0.0154       0.0869         1672 FALSE   
#> 6        6     0.162       0.0118       0.0725         3121 FALSE
```

Anything flagged gets suppressed or footnoted, not reported as if it
were solid. The package deliberately leaves this as your code rather
than a function: the right denominator depends on the estimate (the
respondents actually contributing to it, after subsetting and missing
handling), and a convenience flagger fed the wrong `n` would lend false
authority exactly where caution is needed.

## Intervals near zero

Wald intervals misbehave for proportions near 0 or 1, where much BRFSS
subgroup work lives. The survey package provides the Korn-Graubard
interval, which is what NCHS presentation standards call for:

``` r

library(survey)

svyciprop(~I(GENHLTH == 5), des, method = "beta", na.rm = TRUE)
#>                          2.5%  97.5%
#> I(GENHLTH == 5) 0.0446 0.0432 0.0459
```

The `na.rm = TRUE` is not optional on a design built with `na = TRUE`.
[`svyciprop()`](https://rdrr.io/pkg/survey/man/svyciprop.html) defaults
to `na.rm = FALSE`, and one `NA` anywhere in the column carries through
the whole calculation, so the estimate and both limits come back `NA`
with no warning to say why.
[`survey_mean()`](http://gdfe.co/srvyr/reference/survey_mean.md) takes
the same argument for the same reason.

Compare the result with the symmetric interval from
[`survey_mean()`](http://gdfe.co/srvyr/reference/survey_mean.md) for the
same quantity; for prevalences under about five percent, or any estimate
whose Wald interval crosses zero, report the Korn-Graubard one.

## What to report

A reproducible BRFSS result states the weighted estimate with its
confidence interval and method, the unweighted number of respondents
behind it, the suppression rule applied, a one-sentence design statement
(final weight, strata, PSU, and the lonely-PSU handling, which this
package sets to `"adjust"` when the design contains a single-PSU
stratum), and the per-year data citation, which
[`brfss_citation()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_citation.md)
writes:

``` r

brfss_citation(2023)
#> Centers for Disease Control and Prevention (CDC) (2023). "Behavioral
#> Risk Factor Surveillance System Survey Data, 2023."
#> <https://www.cdc.gov/brfss/>.
#> 
#> Masum M (2026). _brfssdata: Access CDC Behavioral Risk Factor
#> Surveillance System Data_. doi:10.32614/CRAN.package.brfssdata
#> <https://doi.org/10.32614/CRAN.package.brfssdata>. R package version
#> 0.1.0, <https://muntasirmasum.github.io/brfssdata/>.
```
