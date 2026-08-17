# Build a survey-design object for BRFSS analysis

Returns a
[`srvyr::as_survey_design()`](http://gdfe.co/srvyr/reference/as_survey_design.md)
`tbl_svy` with the complex sampling design applied: the year-appropriate
final weight, strata (`_STSTR`), and the primary sampling units (`_PSU`)
in the years where those identify a real cluster. From 2001 on they do
not, and the design says so when it is built; see *Why some years have
no PSU term*, which also shows that the standard errors are unchanged
either way. Weight selection is automatic: `_FINALWT` for years before
2011 (post-stratification era) and `_LLCPWT` from 2011 on (raking era).
Pass `weight` to override it (see *Choosing a weight*).

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
  states = NULL,
  weight = NULL,
  unsafe_weight = FALSE,
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

- states:

  Optional vector of reporting jurisdictions (FIPS, postal
  abbreviations, or names; see
  [brfss_states](https://muntasirmasum.github.io/brfssdata/reference/brfss_states.md)),
  filtered inside the query like in
  [`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md).
  Filtering by state *before* the design is built is variance-exact
  here: BRFSS strata (`_STSTR`) nest within state, so a state subset
  keeps whole strata and yields the same estimates, standard errors, and
  degrees of freedom as subsetting the full design afterwards. That
  property is specific to whole-stratum subsets; any other domain (an
  age group, one sex) must be analyzed by filtering the returned design
  object, never the data (see the *Survey design in BRFSS* article).

- weight:

  Optional name of the weight column to use instead of the automatic era
  weight, e.g. `"_CLLCPWT"` for the child-level modules; matched
  case-insensitively. Must be one of CDC's final analysis weights unless
  `unsafe_weight = TRUE`. See *Choosing a weight*.

- unsafe_weight:

  Set to `TRUE` to allow a `weight` that is not one of CDC's final
  analysis weights (an intermediate pipeline stage, or any other numeric
  column). The design still warns with a pointed class, and the values
  must be positive and finite. Has no effect when `weight` names a final
  weight.

- allow_break:

  Set to `TRUE` to permit pooling years across the 2011 methodology
  change. A warning is still issued.

- pool_weights:

  If `TRUE` and more than one year is requested, divide each weight by
  the number of years that contributed rows, which a `states` filter or
  the domain of a user-supplied `weight` can make smaller than the
  number requested (see Details).

- download:

  If `FALSE`, only cached years are used and missing years raise an
  error instead of being downloaded.

- quiet:

  If `TRUE`, suppress progress and housekeeping output: download
  progress, cache notes, the full-load hint, the case-matching note, and
  the `na = TRUE` recode tally. Notes and warnings about what the data
  mean (renames, missing-code coverage, weight-domain subsetting) signal
  regardless of `quiet`, as does the note that a cached file failed its
  size or checksum check and was re-downloaded, which reports that the
  input bytes changed rather than narrating progress; silence a specific
  one by its class, e.g.
  `suppressMessages(..., classes = "brfssdata_rename_note")`. See
  [brfssdata-conditions](https://muntasirmasum.github.io/brfssdata/reference/brfssdata-conditions.md)
  for every class.

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
  set agrees across the requested years, every observed value is
  covered, and its label wording did not change meaning across those
  years; everything else keeps its numeric codes. Wording that did
  change (CDC reused `COLNTES1` codes 3 to 5 for different screening
  intervals from 2022 on) keeps its codes too, with a
  `brfssdata_label_drift_warning` naming the variables; read those years
  separately if you want each year's own wording. Levels come from the
  newest requested year, so purely cosmetic rewording is shown in CDC's
  most recent phrasing. Identifier and design columns (`_STATE`, the
  weights, strata, and PSU) always keep numeric codes so filters like
  `_STATE == 6` keep working. See
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

`weight` accepts CDC's final analysis weights: the full-sample weights
`_FINALWT` (1985-2010) and `_LLCPWT` (2011 on), the domain weights
`_CLLCPWT` (2011 on) and, for 2006-2010, `_CHILDWT` and `_HOUSEWT`, and
the 2007 questionnaire-version weights `_FINALQ1`, `_FINALQ2`,
`_CHILDQ1`, and `_CHILDQ2`. `_LLCPWT` is correct for core-questionnaire
analyses of the combined landline-and-cell sample; `_FINALWT` is its
pre-2011 counterpart. A final weight requested for years outside its
published span fails before anything is downloaded, with the span named.

The files also carry the intermediate stages of CDC's weighting
pipeline, such as `_STRWT`, `_WT2RAKE`, and `_LLCPWT2` (the truncated
design weight, computed before raking). None of those is an analysis
weight, and estimates computed with one are not calibrated to CDC's
population totals, so requesting one, or any other column that is not a
final weight, is a classed error (`brfssdata_unrecognized_weight`)
unless `unsafe_weight = TRUE` says you mean it. The override still warns
with a pointed class, and the weight values must be positive and finite
either way.

Optional modules asked in states that fielded several questionnaire
versions are published by CDC as separate version datasets (`LLCPyyV1`
to `LLCPyyV3`) with their own final weights (`_LCPWTV1` to `_LCPWTV3`).
Those datasets are not part of this package's hosted annual files, so
version-specific module analyses need CDC's own downloads. The year's
CDC module-analysis documentation ("Complex Sampling Weights and
Preparing Module Data for Analysis") says which modules belong to the
combined dataset, where the default `_LLCPWT` is correct. A
user-supplied domain weight defines its analytic domain: a module weight
exists only for the records its module applies to (completed child
interviews for `_CLLCPWT`, so most rows carry `NA` there), and the
design subsets to the rows the weight covers, reporting the drop with a
`brfssdata_weight_subset_note` message, which matches CDC's
module-analysis guidance. An explicitly named full-sample weight
(`_FINALWT`, `_LLCPWT`) gets the same treatment as the automatic era
weight instead: it must cover every respondent, and a missing value
there means a damaged file and stops the build. A user-supplied weight
is used for every requested year, and pooling divides by the
contributing-year count described below.

The reverse mistake, a module variable analyzed under a full-sample
weight, is caught by a confinement check: when a requested variable has
data almost only where a module weight is non-missing (2023 child asthma
`CASTHDX2` sits inside `_CLLCPWT`'s records for 99.7% of its answers), a
`brfssdata_module_weight_warning` names the module weight to consider.
It warns rather than fails because state-optional modules that CDC
assigns to the core weight produce the same shape; the year's
module-analysis documentation settles those. The check runs only when
`vars` is given and can be disabled with
`options(brfssdata.module_weight_check = FALSE)`.

CDC states that estimates from 2011 onward are not directly comparable
to earlier years, because 2011 added cell-phone-only respondents and
replaced post-stratification with raking. Requests that pool years from
both sides of that boundary therefore fail unless `allow_break = TRUE`
is set deliberately.

That guard covers the one break CDC describes as disqualifying, and it
is not a general promise that any two years on the same side are
comparable. Raking margins, state participation, and collection
conditions all move within an era. CDC publishes a comparability
document with each annual release; check a year-over-year shift there
before reading it as a change in the population.

When several years are combined, weights are divided by the number of
years (`pool_weights = TRUE`, the default) so that pooled estimates
represent an average year rather than a sum of populations, and the
variance strata become the year-by-stratum interaction, treating each
annual survey as an independent sample. The divisor counts the years
that actually contribute rows, not the years requested: a `states` or
`weight` filter can empty a year (Kentucky collected no 2023 data, so
`states = "KY"` over `2022:2023` is a 2022-only design), and dividing
that by the requested count would halve every total while leaving means
and proportions untouched, since the constant cancels there. A
`brfssdata_empty_year_warning` names any year that contributed nothing,
so an average over fewer years is not read as covering all of them. The
pooled estimate averages over the states participating each year; when
participation differs across the pooled years, totals mix coverage, and
a warning says so.

## Why some years have no PSU term

A design built for 2001 or later prints `ids: 1`, which reads as if the
primary sampling units had been dropped. They have not been ignored;
from 2001 on there is nothing for them to say.

From 2001 on, `_PSU` is a record sequence number that restarts in each
state, so it repeats across the file but is unique within a stratum:
every stratum-by-PSU cell holds exactly one respondent. Single-PSU
strata are therefore common and would make variance estimation fail.
When the design just built carries at least one of them and
`options(survey.lonely.psu)` is unset, this function sets it to
`"adjust"` (standard BRFSS practice) and says so once per session. A
design with no such stratum (1995 and 2003 have none, 2023 has 101)
leaves the option alone, so an unrelated survey analysis later in the
session keeps survey's own fail-fast default. Any value you set other
than `"fail"` is respected; `"fail"` is what the survey package itself
installs on load, so it cannot be told apart from "never set" and is
treated as unset. To insist on `"fail"`, or to pin any handling, set
`options(brfssdata.lonely_psu = ...)`, which is copied into
`survey.lonely.psu` unconditionally. The option stays set for the
session because survey consults it at estimation time, not design time.

Because that clustering is nominal, the design for those years is built
without a cluster term, which gives the same estimates, standard errors,
and degrees of freedom far faster than carrying a cluster factor with
one level per respondent. On the 2023 file, fair-or-poor `GENHLTH`
returns 0.193696115777860 with a standard error of 0.001389477801364
whether the cluster term is supplied or not, to the last bit of a
double, and both designs report 431,177 degrees of freedom. Files
through 2000 carry genuine multi-respondent PSUs and keep the clustered
estimator, nested within stratum because the identifiers are reused, and
there the two specifications do differ: the same estimate on 1995 has a
standard error of 0.001830302439388 with the cluster term against
0.001826985014850 without it, on 61,230 degrees of freedom rather than
113,870. The choice is from the data, so it follows the file rather than
the year.

The design object itself prints only srvyr's syntactic column names,
which say nothing about which CDC weight was chosen. The build therefore
states the specification in `svyset` terms, naming the weight, the
stratum column, and whether a cluster term applies
(`brfssdata_design_spec_note`, suppressed by `quiet = TRUE`).

## See also

[`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
for the underlying data;
[brfssdata-options](https://muntasirmasum.github.io/brfssdata/reference/brfssdata-options.md)
for the session options (`brfssdata.lonely_psu`,
`brfssdata.module_weight_check`) this function consults.

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
