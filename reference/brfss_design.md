# Build a survey-design object for BRFSS analysis

Returns a
[`srvyr::as_survey_design()`](http://gdfe.co/srvyr/reference/as_survey_design.md)
`tbl_svy` with the complex sampling design applied: primary sampling
units (`_PSU`), strata (`_STSTR`), and the year-appropriate final
weight. Weight selection is automatic: `_FINALWT` for years before 2011
(post-stratification era) and `_LLCPWT` from 2011 on (raking era). Pass
`weight` to override it (see *Choosing a weight*).

By default the codes CDC uses for don't know / refused / missing answers
are set to `NA` (`na = TRUE`), so means and proportions are computed
over substantive answers; see
[`brfss_missing_codes()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_missing_codes.md)
for the exact codes and the `na` entry under Arguments for details.

## Usage

``` r
brfss_design(
  years,
  vars = NULL,
  weight = NULL,
  allow_break = FALSE,
  pool_weights = TRUE,
  download = TRUE,
  quiet = FALSE,
  labels = FALSE,
  na = TRUE
)
```

## Arguments

- years:

  Integer vector of survey years, e.g. `2023` or `2019:2023`. See
  [`brfss_years()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_years.md)
  for what is available.

- vars:

  Optional character vector of analysis variables to carry into the
  design, matched case-insensitively like in
  [`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md).
  Design variables are always included. The default loads every column
  (455 columns by 506,467 rows for 2011 alone) and says so; passing only
  the variables you analyze is much faster and smaller.

- weight:

  Optional name of the weight column to use instead of the automatic era
  weight, e.g. `"_LLCPWT2"` for split-questionnaire content; matched
  case-insensitively. See *Choosing a weight*.

- allow_break:

  Set to `TRUE` to permit pooling years across the 2011 methodology
  change. A warning is still issued.

- pool_weights:

  If `TRUE` and more than one year is requested, divide each weight by
  the number of years.

- download:

  If `FALSE`, only cached years are used and missing years raise an
  error instead of being downloaded.

- quiet:

  If `TRUE`, suppress download progress output.

- labels:

  Controls value-label conversion via CDC's format libraries (available
  from 1998 on). `FALSE` (the default) keeps every numeric code. `TRUE`
  converts variables with safe maps to factors; note the conversion is
  lossy: the CDC codes are gone, and
  [`as.numeric()`](https://rdrr.io/r/base/numeric.html) on the result
  returns factor level positions, not codes (most CDC code sets are
  non-contiguous, so the two disagree). `"both"` keeps the code in the
  level text (`"[1] Excellent"`) so it stays recoverable. A variable
  converts only when its format is a pure code-to-label map, its code
  set agrees across the requested years, and every observed value is
  covered; everything else keeps its numeric codes. Identifier and
  design columns (`_STATE`, the weights, strata, and PSU) always keep
  numeric codes so filters like `_STATE == 6` keep working. See
  [`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md)
  for the catalog.

- na:

  If `TRUE` (the default here), set the codes CDC uses for missing-type
  answers (don't know / not sure, refused, not asked) to `NA` before the
  design is built, so estimates cover substantive answers; see
  [`brfss_missing_codes()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_missing_codes.md)
  for exactly which codes, and the same argument in
  [`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
  (where the default is `FALSE`) for the full details.

## Value

A `tbl_svy` survey-design object. The underlying data carry three added
syntactic columns the design is built on: `brfss_wt` (the selected,
possibly pooled, weight), `brfss_psu`, and `brfss_strata` (the raw
stratum for a single year; the year-by-stratum interaction when years
are pooled). The original CDC columns are kept unchanged.

## Choosing a weight

`_LLCPWT` is the final weight for the combined landline-and-cell sample
and is correct for core-questionnaire analyses. From 2013 on (2015
excepted), the files also carry `_LLCPWT2` and related weights for
split-questionnaire and module content; the two differ on essentially
every respondent, so analyzing a variable asked of only one
questionnaire version with the overall weight gives a materially wrong
estimate. This package cannot tell which weight an analysis variable
needs (the files do not say), so consult the year's CDC module-analysis
documentation ("Complex Sampling Weights and Preparing Module Data for
Analysis") and pass, e.g., `weight = "_LLCPWT2"` when it says to. A
user-supplied weight is used for every requested year and still divides
by the year count under `pool_weights`.

CDC states that estimates from 2011 onward are not directly comparable
to earlier years, because 2011 added cell-phone-only respondents and
replaced post-stratification with raking. Requests that pool years from
both sides of that boundary therefore fail unless `allow_break = TRUE`
is set deliberately.

That guard covers the one break CDC describes as disqualifying, and it
is not a general promise that any two years on the same side are
comparable. Raking margins, state participation, and collection
conditions all move within an era. CDC publishes a comparability
document with each annual release, and a year-over-year shift is worth
reading there before it is read as a change in the population.

When several years are combined, weights are divided by the number of
years (`pool_weights = TRUE`, the default) so that pooled estimates
represent an average year rather than a sum of populations, and the
variance strata become the year-by-stratum interaction, treating each
annual survey as an independent sample. The pooled estimate averages
over the states participating each year; when participation differs
across the pooled years, totals mix coverage, and a warning says so.

From 2001 on, `_PSU` is a record sequence number that restarts in each
state, so it repeats across the file but is unique within a stratum:
every stratum-by-PSU cell holds exactly one respondent. Single-PSU
strata are therefore common and would make variance estimation fail. If
`options(survey.lonely.psu)` is unset, this function sets it to
`"adjust"` (standard BRFSS practice) and says so once per session. Any
value you set other than `"fail"` is respected; `"fail"` is what the
survey package itself installs on load, so it cannot be told apart from
"never set" and is treated as unset. To insist on `"fail"`, or to pin
any handling, set `options(brfssdata.lonely_psu = ...)`, which is copied
into `survey.lonely.psu` unconditionally. The option stays set for the
session because survey consults it at estimation time, not design time.

Because that clustering is nominal, the design for those years is built
without a cluster term, which gives the same estimates, standard errors,
and degrees of freedom far faster than carrying a cluster factor with
one level per respondent. Files through 2000 carry genuine
multi-respondent PSUs and keep the clustered estimator, nested within
stratum because the identifiers are reused. The choice is made from the
data, so it follows the file rather than the year.

## Examples

``` r
if (FALSE) { # interactive()
library(srvyr)
des <- brfss_design(2023, vars = "GENHLTH")
des |>
  group_by(GENHLTH) |>
  summarize(prop = survey_prop())
}
```
