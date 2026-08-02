# Build a survey-design object for BRFSS analysis

Returns a
[`srvyr::as_survey_design()`](http://gdfe.co/srvyr/reference/as_survey_design.md)
`tbl_svy` with the complex sampling design applied: primary sampling
units (`_PSU`), strata (`_STSTR`), and the year-appropriate final
weight. Weight selection is automatic: `_FINALWT` for years before 2011
(post-stratification era) and `_LLCPWT` from 2011 on (raking era).

CDC states that estimates from 2011 onward are not directly comparable
to earlier years, because 2011 added cell-phone-only respondents and
replaced post-stratification with raking. Requests that pool years from
both sides of that boundary therefore fail unless `allow_break = TRUE`
is set deliberately.

When several years are combined, weights are divided by the number of
years (`pool_weights = TRUE`, the default) so that pooled estimates
represent an average year rather than a sum of populations, and the
variance strata become the year-by-stratum interaction, treating each
annual survey as an independent sample.

Because BRFSS public-use files make each respondent their own primary
sampling unit, single-PSU strata are common and would make variance
estimation fail. If `options(survey.lonely.psu)` is unset, this function
sets it to `"adjust"` (standard BRFSS practice) and says so once per
session; an option you set yourself is always respected.

## Usage

``` r
brfss_design(
  years,
  vars = NULL,
  allow_break = FALSE,
  pool_weights = TRUE,
  download = TRUE,
  quiet = FALSE,
  labels = FALSE
)
```

## Arguments

- years:

  Integer vector of survey years, e.g. `2023` or `2019:2023`. See
  [`brfss_years()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_years.md)
  for what is available.

- vars:

  Optional character vector of analysis variables to carry into the
  design. Design variables are always included.

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

  If `TRUE`, convert variables with safe value-label maps to factors
  using CDC's format libraries (available from 1998 on). A variable
  converts only when its format is a pure code-to-label map, its code
  set agrees across the requested years, and every observed value is
  covered; everything else keeps its numeric codes. See
  [`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md)
  for the raw catalog.

## Value

A `tbl_svy` survey-design object. The underlying data carry three added
syntactic columns the design is built on: `brfss_wt` (the selected,
possibly pooled, weight), `brfss_psu`, and `brfss_strata` (the raw
stratum for a single year; the year-by-stratum interaction when years
are pooled). The original CDC columns are kept unchanged.

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
