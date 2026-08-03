# Getting started with brfssdata

The Behavioral Risk Factor Surveillance System (BRFSS) is the CDC’s
state-based telephone health survey. CDC established it in 1984,
collects data in all 50 states, the District of Columbia, and
participating US territories, and completes more than 400,000 adult
interviews each year, which makes it the largest continuously conducted
health survey system in the world. The public-use microdata are released
one file per survey year, each carrying several hundred variables on
health status, chronic conditions, health-care access, and risk
behaviors.

Getting at those files has traditionally meant downloading a zipped SAS
transport archive for each year, reading it with a format-specific
importer, and reconciling variable names by hand across years. brfssdata
removes that step. Forty survey years, 1985 through 2024, are stored as
compact parquet files on public releases; a year is downloaded once into
a local cache and read from there afterwards, and every query runs
through DuckDB, so asking for two variables out of a
three-hundred-column survey reads two columns instead of the whole
table.

The installed vignette leaves most of this code unevaluated so the
package builds offline, which means the copy you are reading in R shows
no output under the code. The same document runs live against real data
at <https://muntasirmasum.github.io/brfssdata/articles/brfssdata.html>,
and reading it there is the better experience.

## Installation

Once the package is on CRAN, install it the usual way.

``` r

install.packages("brfssdata")
```

The development version comes from GitHub.

``` r

pak::pak("muntasirmasum/brfssdata")
```

## A first read

[`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
is the main entry point. Give it a survey year and the variables you
want, and it returns a tibble with one row per respondent.

``` r

library(brfssdata)
library(dplyr)

dat <- read_brfss(2023, vars = c("GENHLTH", "PHYSHLTH"))
dat
#> # A tibble: 433,323 × 3
#>    GENHLTH PHYSHLTH  year
#>      <dbl>    <dbl> <int>
#>  1       2       88  2023
#>  2       2       88  2023
#>  3       4        6  2023
#>  4       2        2  2023
#>  5       4       88  2023
#>  6       3        2  2023
#>  7       4        8  2023
#>  8       4        1  2023
#>  9       3        5  2023
#> 10       3       88  2023
#> # ℹ 433,313 more rows
```

`GENHLTH` is self-rated general health on a five-point scale, and
`PHYSHLTH` is the number of days in the past thirty on which physical
health was not good. Both arrive as numeric codes, which is what most
BRFSS analyses work from. A quick tabulation confirms the scale.

``` r

dat |>
  count(GENHLTH) |>
  arrange(GENHLTH)
#> # A tibble: 8 × 2
#>   GENHLTH      n
#>     <dbl>  <int>
#> 1       1  63410
#> 2       2 142115
#> 3       3 144209
#> 4       4  61955
#> 5       5  20372
#> 6       7    897
#> 7       9    361
#> 8      NA      4
```

Leaving `vars` at its default (`NULL`) returns every column in the year,
which for a recent release means well over three hundred variables. That
is occasionally what you want, but naming the handful of variables you
actually need is much faster and keeps memory use modest.

## Variable names

BRFSS variable names are short, uppercase, and set by CDC. Names that
begin with an underscore, such as `_LLCPWT`, `_STSTR`, or `_AGE_G`, are
CDC’s calculated variables: sampling weights, design identifiers,
recoded age and race groupings, and derived risk-factor indicators.
Everything else comes straight off the questionnaire. brfssdata always
returns CDC’s canonical spelling. An underscore-prefixed name is not a
syntactic R name, so it needs backticks in dplyr code or brackets in
base R (`` `_LLCPWT` `` or `dat[["_LLCPWT"]]`).

Keeping CDC’s spelling is deliberate. `_EDUCAG` is the name printed in
the codebook, in CDC’s own SAS and Stata examples, and in most published
BRFSS code, so a column that still carries it can be looked up directly.
Backticks are accepted everywhere a column name can appear, model
formulas included, so a model fits straight on CDC’s names.

``` r

svyglm(fairpoor ~ `_EDUCAG`, design = des, family = quasibinomial())
```

If you would rather work in syntactic names throughout,
`janitor::clean_names()` converts a whole tibble in one step.

``` r

read_brfss(2023, vars = c("GENHLTH", "_EDUCAG")) |>
  janitor::clean_names()
```

The underscore is dropped rather than escaped, so `_EDUCAG` becomes
`educag` and no longer matches the name you would search for in the
codebook. There is a subtler cost as well. CDC ships both an underscored
and a plain version of eight variables, and three of those pairs occupy
the same survey years: `MRACE` and `_MRACE` both run from 2001 through
2012, `CHOLCHK` and `_CHOLCHK` overlap across many years between 1991
and 2015, and `FLUSHOT` and `_FLUSHOT` share 2002 and 2003. Cleaning the
names makes each pair collide, and `clean_names()` settles the tie by
suffixing whichever column happens to come second, so the two arrive as
`mrace` and `mrace_2` with the assignment following column order rather
than meaning. Check which is which before using either.

Typing uppercase is tedious, so `vars` is matched case-insensitively.
The lowercase request below finds `GENHLTH` and the returned column
carries the canonical name.

``` r

names(read_brfss(2023, vars = "genhlth"))
#> [1] "GENHLTH" "year"
```

Notice the `year` column. It is added to every result, whether or not
you ask for it, so a tibble always knows which survey year each row came
from.

A name that matches nothing raises an error rather than silently
returning fewer columns than you asked for.

``` r

read_brfss(2023, vars = "SMOKING")
#> Error in `read_brfss()`:
#> ! Variable "SMOKING" was not found in the requested years.
#> ℹ Use `brfss_vars()` to search available variables and the years they appear
#>   in.
```

## Which years are available

[`brfss_years()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_years.md)
reads the manifest that accompanies the data releases and reports the
published survey years. The manifest is cached and refreshed at most
once a day, and `refresh = TRUE` forces a fresh copy.

``` r

brfss_years()
#>  [1] 1985 1986 1987 1988 1989 1990 1991 1992 1993 1994 1995 1996 1997 1998 1999
#> [16] 2000 2001 2002 2003 2004 2005 2006 2007 2008 2009 2010 2011 2012 2013 2014
#> [31] 2015 2016 2017 2018 2019 2020 2021 2022 2023 2024
```

## Combining years

Pass a vector of years and they come back stacked, with the `year`
column identifying each. The complication is that BRFSS variable sets
drift. Questions rotate on and off the core questionnaire, optional
modules move between states, and CDC renames a calculated variable
whenever its definition changes, usually by bumping a trailing digit.
When a variable is absent from one of the requested years, it is filled
with `NA` for those rows rather than causing an error.

Computed weekly alcohol consumption is a clean example. The variable is
`_DRNKWK1` in 2019 to 2021, `_DRNKWK2` in 2022 and 2023, and `_DRNKWK3`
in 2024, with a change in definition at each rename. Asking for the
first two across 2021 to 2023 shows where one gives way to the other.

``` r

drinks <- read_brfss(2021:2023, vars = c("_DRNKWK1", "_DRNKWK2"))

drinks |>
  summarise(
    n = n(),
    drnkwk1 = sum(!is.na(`_DRNKWK1`)),
    drnkwk2 = sum(!is.na(`_DRNKWK2`)),
    .by = year
  ) |>
  arrange(year)
#> # A tibble: 3 × 4
#>    year      n drnkwk1 drnkwk2
#>   <int>  <int>   <int>   <int>
#> 1  2021 438693  438693       0
#> 2  2022 445132       0  445132
#> 3  2023 433323       0  433323
```

Reading both versions and coalescing them is the usual fix, but only
after checking that the definitions are close enough to justify it. That
check is your job, not the package’s; brfssdata will hand you both
columns and stay out of the way.

## Finding variables

Since names move, you generally want to search before you read.
[`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md)
matches a regular expression, case-insensitively, against both variable
names and their labels, and reports the years each match appears in.

``` r

brfss_vars("smok")
#> # A tibble: 96 × 3
#>    variable label                                    years    
#>    <chr>    <chr>                                    <chr>    
#>  1 ALLOWADS PLACEMENT OF BILLBOARD ADS ABOUT SMOKING 1998     
#>  2 ATKNSMOK START SMOKING AFTER ATTK?                2002     
#>  3 ATKSMOK  SMOKE MORE AFTER ATTK?                   2002     
#>  4 BEGSMOKE AGE STARTED SMOKING REGULARLY            1991-1992
#>  5 BIDINOW  NOW SMOKE INDIAN CIGARETTES              2001-2003
#>  6 BIDISMK  EVER SMOKED INDIAN CIGARETTE             2001-2003
#>  7 CANCER   THINK SMOKELESS USE CAUSE MOUTH CANCER   1986     
#>  8 CIGAR    EVER SMOKED A CIGAR                      1998     
#>  9 CIGAR2   EVER SMOKED CIGAR                        2001-2003
#> 10 CIGARNOW CURRENTLY SMOKE CIGARS                   2001-2003
#> # ℹ 86 more rows
```

The `years` column collapses runs of consecutive years, so `2005-2024`
means every year in that span and `2011-2013, 2020` means a variable
that appeared for three years, disappeared, and came back once. Reading
that column carefully is the fastest way to spot renamed variables. Two
entries with near-identical labels and non-overlapping year ranges are
almost always the same question under a new name.

Calling
[`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md)
with no pattern returns the whole catalog, which holds 2,128 distinct
variables across the forty years. Restricting to particular years
narrows the search, and the result here shows the rename pattern
plainly.

``` r

brfss_vars("binge", years = 2021:2023)
#> # A tibble: 3 × 3
#>   variable label                              years    
#>   <chr>    <chr>                              <chr>    
#> 1 DRNK3GE5 BINGE DRINKING                     2021-2023
#> 2 _RFBING5 BINGE DRINKING CALCULATED VARIABLE 2021     
#> 3 _RFBING6 BINGE DRINKING CALCULATED VARIABLE 2022-2023
```

`_RFBING5` and `_RFBING6` share a label and cover 2021 and then 2022 to
2023, which is the signature of a calculated variable whose definition
was revised. The underlying questionnaire item, `DRNK3GE5`, kept its
name across all three years.

## Value labels

BRFSS answers are numeric codes, and the meaning of each code lives in
CDC’s SAS format libraries.
[`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md)
exposes those as a plain table with one row per year, variable, and
code.

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

Setting `labels = TRUE` on a read converts eligible variables to factors
using those maps.

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

Labeling renames codes; deciding which of them mean missing is a
separate step, and the `GENHLTH` above has seven levels rather than five
because CDC’s don’t-know and refused codes became factor levels like any
other. The `na` argument handles that: `na = TRUE` sets the codes CDC
uses for missing-type answers to `NA` before labeling, using the same
catalog, so the factor arrives with its five substantive levels.

``` r

read_brfss(2023, vars = "GENHLTH", labels = TRUE, na = TRUE) |>
  count(GENHLTH)
#> ℹ Set 1258 responses across 1 variable to NA (don't know / refused / missing
#>   codes).
#> ℹ See `brfss_missing_codes()` for the affected codes; disable with `na =
#>   FALSE`.
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

[`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
defaults to `na = FALSE` and returns the file exactly as CDC published
it;
[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
defaults to `na = TRUE`, because an estimate whose denominator includes
“Refused” is almost never the estimate anyone wants.
[`brfss_missing_codes()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_missing_codes.md)
lists exactly which year, variable, and code combinations are affected,
so the behavior is auditable rather than magic.

``` r

brfss_missing_codes("GENHLTH", years = 2023)
#> # A tibble: 2 × 4
#>    year variable  code label             
#>   <int> <chr>    <int> <chr>             
#> 1  2023 GENHLTH      9 Refused           
#> 2  2023 GENHLTH      7 Dont know/Not Sure
```

Conversion is deliberately conservative. A variable becomes a factor
only when its CDC format is a pure code-to-label map, carrying no
numeric ranges such as `1-30` days, when the map is an unambiguous
one-to-one correspondence (some CDC formats give one code several
labels, or reuse one label across codes, and converting those would
quietly rewrite the data), and when every value observed in the data
falls inside that map. The `complete` column in the label catalog marks
the formats that meet the first condition. `PHYSHLTH` is a good
counterexample: its format documents only the special codes, because the
substantive values are a count of days.

``` r

brfss_labels("PHYSHLTH", years = 2023)
#> # A tibble: 3 × 5
#>    year variable  code label              complete
#>   <int> <chr>    <int> <chr>              <lgl>   
#> 1  2023 PHYSHLTH    88 None               FALSE   
#> 2  2023 PHYSHLTH    77 Dont know/Not sure FALSE   
#> 3  2023 PHYSHLTH    99 Refused            FALSE
```

Turning that into a factor would silently destroy the day counts, so
`labels = TRUE` leaves it numeric, and the catalog tells you that 88
means none, 77 means don’t know, and 99 means refused. `na = TRUE`
clears 77 and 99 here too, but 88 is an answer (zero days), not a
missing code, and averaging `PHYSHLTH` without recoding it to 0 first
overstates bad-health days for the healthiest respondents.

``` r

read_brfss(2023, vars = "PHYSHLTH", na = TRUE) |>
  mutate(PHYSHLTH = replace(PHYSHLTH, PHYSHLTH == 88, 0))
```

The same caution applies across years: when several years are requested,
a variable converts only if its code set agrees across them.

Labels cover 1998 onward. CDC does not distribute usable format
libraries for earlier years, so `labels = TRUE` has nothing to work with
before 1998 and quietly leaves those variables as numeric codes.

## Caching and offline work

Every download lands in a per-user cache directory, resolved through
[`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html). You can
see where it is and what is in it.

``` r

brfss_cache_dir()
#> [1] "/home/runner/.cache/R/brfssdata"
brfss_cache_info()
#> # A tibble: 6 × 3
#>   file                     year     size
#>   <chr>                   <int>    <dbl>
#> 1 brfss_2021.parquet       2021 26033879
#> 2 brfss_2022.parquet       2022 26280485
#> 3 brfss_2023.parquet       2023 29077288
#> 4 brfss_labels.parquet       NA   119739
#> 5 brfss_variables.parquet    NA    63889
#> 6 manifest.json              NA     6275
```

Because reads come from the cache, a year you have already downloaded is
available with no network at all. Setting `download = FALSE` makes that
explicit: cached years are read normally, and a request for a year you
do not have fails with a clear message instead of reaching for the
network.

``` r

nrow(read_brfss(2023, vars = "GENHLTH", download = FALSE))
#> [1] 433323
```

This is the setting to use on a compute cluster without outbound network
access, or in a reproducible pipeline where an unexpected download would
be a bug.
[`brfss_download()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_download.md)
populates the cache in one call, years and metadata catalogs together,
so the usual offline recipe is to run it once on a connected machine,
copy the directory across, and point
`options(brfssdata.cache_dir = ...)` at it.

``` r

brfss_download(2019:2023)
```

Downloads are verified against the sha256 checksums published with each
release, and a cached file that later turns out damaged is either
re-downloaded automatically or named in an error along with the exact
call that fixes it.

[`brfss_cache_clear()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
removes cached survey years, all of them when called with no arguments,
only the ones you name otherwise. The manifest and catalogs stay unless
you also pass `catalogs = TRUE`, so clearing data does not break offline
variable searches.

``` r

brfss_cache_clear(2021)
brfss_cache_clear()
brfss_cache_clear(catalogs = TRUE)
```

## Survey-weighted analysis

BRFSS uses a complex sampling design, and unweighted estimates from it
are wrong in both the point estimate and the standard error.
[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
returns a [srvyr](https://cran.r-project.org/package=srvyr) design
object with the sampling weight, strata (`_STSTR`), and primary sampling
units (`_PSU`) already applied, so you can move straight to analysis.

``` r

library(srvyr)

brfss_design(2023, vars = "GENHLTH") |>
  filter(!is.na(GENHLTH)) |>
  group_by(GENHLTH) |>
  summarize(pct = survey_prop(vartype = "ci"))
#> # A tibble: 5 × 4
#>   GENHLTH    pct pct_low pct_upp
#>     <dbl>  <dbl>   <dbl>   <dbl>
#> 1       1 0.159   0.156   0.161 
#> 2       2 0.311   0.308   0.314 
#> 3       3 0.336   0.333   0.340 
#> 4       4 0.149   0.147   0.152 
#> 5       5 0.0446  0.0433  0.0459
```

The weight is chosen to match the survey era: `_FINALWT` for years
before 2011 and `_LLCPWT` from 2011 on (a `weight` argument selects
another final weight, such as the child weight `_CLLCPWT`, when CDC’s
documentation calls for it; see
[`?brfss_design`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
for why the intermediate pipeline weights like `_LLCPWT2` warn). The
design is built on three added columns, `brfss_wt`, `brfss_psu`, and
`brfss_strata`, because CDC’s names are not syntactic and cannot enter a
model formula; the original CDC columns are kept alongside them,
unchanged. The don’t-know and refused codes arrive as `NA` here by
default (`na = TRUE`), which is why the filter above is on
[`is.na()`](https://rdrr.io/r/base/NA.html) and not on code ranges; pass
`na = FALSE` for the raw codes.

Two behaviors are worth knowing about up front. Because BRFSS public-use
files make each respondent their own primary sampling unit, single-PSU
strata are common and would otherwise make variance estimation fail, so
[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
sets `options(survey.lonely.psu = "adjust")` if the option is unset, and
says so once per session. Any value you set other than `"fail"` is
respected as yours; `"fail"` is what the survey package itself installs
on load, so it reads as unset, and `options(brfssdata.lonely_psu = ...)`
is the way to pin any handling, `"fail"` included. And when you request
several years, weights are divided by the number of years, so pooled
estimates describe an average year rather than a summed population,
while the strata become the year-by-stratum interaction, which treats
each annual survey as an independent sample. Pass `pool_weights = FALSE`
to leave the weights undivided; if state participation differs across
the pooled years, a warning names the states involved.

### The 2011 boundary

In 2011 BRFSS combined cell phone and landline samples into a single
public-use dataset for the first time, and adopted a new weighting
method, iterative proportional fitting, also known as raking, in place
of post-stratification. CDC advises data users not to make direct
comparisons with data collected before 2011, and to begin new trend
lines with that year.
[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
enforces the advice rather than burying it in a help page, so a request
spanning the boundary fails.

``` r

brfss_design(2009:2013)
#> Error in `brfss_design()`:
#> ! Years 2009-2013 span the 2011 BRFSS redesign.
#> ✖ CDC states post-2011 estimates are not directly comparable to earlier years
#>   (cell-phone frame and raking weights).
#> ℹ Analyze the eras separately, or set `allow_break = TRUE` to pool anyway.
```

If you have a considered reason to pool across it, opt in explicitly and
the call proceeds with a warning.

``` r

brfss_design(2009:2013, allow_break = TRUE)
```

Two articles carry this further. [Survey design in
BRFSS](https://muntasirmasum.github.io/brfssdata/articles/survey-design.html)
works through weights, strata, single-PSU handling, subpopulation
analysis, and multi-year pooling in detail. [Survey-weighted logistic
regression](https://muntasirmasum.github.io/brfssdata/articles/logistic-regression.html)
fits a full model with `svyglm()`, walking from recoding and weighted
prevalence through design-based confidence intervals on the odds ratios.

## Using the data outside R

Nothing about the cache is specific to R. The files are ordinary
parquet, readable by anything that speaks the format, so if you or a
collaborator work in Python, SAS, Stata, or plain SQL, you can point
those tools at the same files brfssdata downloaded, or export a prepared
subset from R. [Using the data outside
R](https://muntasirmasum.github.io/brfssdata/articles/outside-r.html)
covers each route.

## Citing

The package and the survey data are cited separately, and both entries
come back from one call.

``` r

citation("brfssdata")
#> To cite brfssdata in publications, cite the package itself. Analyses of
#> the underlying survey data should also cite CDC's BRFSS for the survey
#> year(s) used.
#> 
#>   Masum M (2026). _brfssdata: Access CDC Behavioral Risk Factor
#>   Surveillance System Data_. R package version 0.1.0,
#>   <https://muntasirmasum.github.io/brfssdata/>.
#> 
#>   Centers for Disease Control and Prevention (CDC). Behavioral Risk
#>   Factor Surveillance System Survey Data. Atlanta, Georgia: U.S.
#>   Department of Health and Human Services, Centers for Disease Control
#>   and Prevention, [appropriate year].
#> 
#> To see these entries in BibTeX format, use 'print(<citation>,
#> bibtex=TRUE)', 'toBibtex(.)', or set
#> 'options(citation.bibtex.max=999)'.
```

The second entry is CDC’s recommended form for the data itself. Replace
`[appropriate year]` with the survey year or years you analyzed, and
repeat the citation for each year if your journal expects that.
Manuscripts reporting BRFSS estimates conventionally also report
response rates from CDC’s Summary Data Quality Report for the years
analyzed.
