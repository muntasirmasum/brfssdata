# brfssdata

brfssdata gives R users direct, reproducible access to annual microdata
from the CDC [Behavioral Risk Factor Surveillance
System](https://www.cdc.gov/brfss/) (BRFSS), the largest continuously
conducted health telephone survey in the world.

Survey years are processed once into compact parquet files and hosted as
GitHub release assets. The package downloads each requested year a
single time into a local cache, queries it through DuckDB (so pulling a
handful of variables from a 300-plus column survey is fast), and hands
back either a tibble or a ready-made
[srvyr](https://cran.r-project.org/package=srvyr) survey-design object
with the correct weights, strata, and primary sampling units for each
survey era.

> **Status:** 40 survey years, 1985 through 2024, are published as data
> releases. BRFSS began in 1984, and CDC does distribute a 1984 file
> (12,258 records from the first 15 states) from its [web
> archive](https://archive.cdc.gov/www_cdc_gov/brfss/annual_data/annual_1984.htm);
> that year is not part of this collection.
> [`brfss_years()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_years.md)
> reports the currently hosted years, refreshing its manifest at most
> once a day (`refresh = TRUE` forces a fresh look).

## Installation

Install the development version from GitHub:

``` r

# install.packages("pak")
pak::pak("muntasirmasum/brfssdata")
```

Once the package is on CRAN, install it the usual way.

``` r

install.packages("brfssdata")
```

## Usage

``` r

library(brfssdata)

# Which survey years are published?
brfss_years()

# Respondent-level data, only the variables you need
dat <- read_brfss(2019:2023, vars = c("GENHLTH", "PHYSHLTH", "_LLCPWT"))

# The same, with safe categoricals converted to labeled factors
dat <- read_brfss(2023, vars = c("GENHLTH", "SEXVAR"), labels = TRUE)

# One state's rows only, filtered inside the query
dat <- read_brfss(2023, vars = "GENHLTH", states = "TX")

# The value-label codebook itself (1998 onward)
brfss_labels("GENHLTH", years = 2023)

# Everything the catalogs know about a variable, as a card
brfss_codebook("GENHLTH", years = 2023)

# CDC renames variables across years; find the whole family
brfss_crosswalk("_DRNKWK1")

# A survey-design object with era-correct weights, ready for srvyr.
# Codes CDC uses for "don't know" and "refused" are NA by default here,
# so the proportions cover substantive answers; see ?brfss_missing_codes.
library(srvyr)
brfss_design(2023, vars = "GENHLTH") |>
  group_by(GENHLTH) |>
  summarize(prop = survey_prop(vartype = "ci"))

# Where does a variable appear across years?
brfss_vars("smok")
```

Downloads are verified against published checksums and cached under
[`brfss_cache_dir()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
(per [`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html)). One
call to `brfss_download(2019:2023)` prefetches years plus the variable
and label catalogs, after which everything runs offline;
[`brfss_cache_info()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
and
[`brfss_cache_clear()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
manage the cache.

## The 2011 design break

BRFSS added cell-phone-only respondents and switched from
post-stratification to raking in 2011; CDC states that estimates from
2011 onward are not directly comparable to earlier years.
[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
selects the era-correct weight automatically (`_FINALWT` before 2011,
`_LLCPWT` after) and refuses to pool years across the boundary unless
you opt in with `allow_break = TRUE`.

## Access from Python, SAS, Stata, or anything else

The hosted data files are plain parquet, so no R is required to use
them. Every release asset has a stable URL:

``` python
import pandas as pd

url = ("https://github.com/muntasirmasum/brfssdata/releases/download/"
       "data-2023/brfss_2023.parquet")
df = pd.read_parquet(url)
```

The same URLs work in polars, DuckDB (any language), Julia, or Stata’s
Python bridge. SAS and Stata users who want native files can export any
extract from R with
[`haven::write_xpt()`](https://haven.tidyverse.org/reference/read_xpt.html)
(SAS Transport) or
[`haven::write_dta()`](https://haven.tidyverse.org/reference/read_dta.html);
the [Using the data outside
R](https://muntasirmasum.github.io/brfssdata/articles/outside-r.html)
article walks through both, including the variable-name limits each
format imposes on CDC’s calculated names.

For survey-weighted analysis outside R, use the design columns shipped
in every year: the final weight (`_LLCPWT` from 2011, `_FINALWT`
before), strata (`_STSTR`), and PSU (`_PSU`). The list of available
years lives at `releases/download/data-meta/manifest.json`, and each
file has a `.sha256` companion for verification.

## Citation

To cite the package, use `citation("brfssdata")`:

> Masum M (2026). *brfssdata: Access CDC Behavioral Risk Factor
> Surveillance System Data*. R package version 0.1.0,
> <https://muntasirmasum.github.io/brfssdata/>.

Analyses should also cite the underlying survey data (below).

## Data source

All data originate from the CDC BRFSS annual survey files, which are in
the public domain. Suggested citation for the data:

> Centers for Disease Control and Prevention (CDC). Behavioral Risk
> Factor Surveillance System Survey Data. Atlanta, Georgia: U.S.
> Department of Health and Human Services, Centers for Disease Control
> and Prevention, \[appropriate year\].

The hosted parquet files are derived from CDC’s published SAS Transport
files with no rows dropped, no columns dropped, and no values recoded.
Three transformations are applied: the Windows-1252 text older files
carry is re-encoded to UTF-8, blank SAS character fields (SAS’s missing
value for character data) are stored as nulls rather than empty strings,
and an integer `year` column is added. The handful of variables CDC
stored as a number in some years and text in others are written with one
storage type across all years, values unchanged, so multi-year reads
cannot split one code into `1120` and `"1120.0"`. The processing
pipeline lives in
[`data-raw/`](https://github.com/muntasirmasum/brfssdata/tree/main/data-raw);
every artifact is checksummed, and the package verifies those checksums
when it downloads.

## License

MIT for the package code. The BRFSS data are a U.S. government work in
the public domain.
