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

> **Status:** all 40 available survey years (1985-2024) are published as
> data releases; 1984 was never distributed as a SAS Transport file by
> CDC.
> [`brfss_years()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_years.md)
> always reports the currently hosted years.

## Installation

``` r

# install.packages("pak")
pak::pak("muntasirmasum/brfssdata")
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

# The value-label codebook itself (1998 onward)
brfss_labels("GENHLTH", years = 2023)

# A survey-design object with era-correct weights, ready for srvyr
library(srvyr)
brfss_design(2023, vars = "GENHLTH") |>
  group_by(GENHLTH) |>
  summarize(prop = survey_prop(vartype = "ci"))

# Where does a variable appear across years?
brfss_vars("smok")
```

Downloads are cached under
[`brfss_cache_dir()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
(per [`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html)), so
everything after the first pull works offline.
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

## Access from Python (or anything else)

The hosted data files are plain parquet, so no R is required to use
them. Every release asset has a stable URL:

``` python
import pandas as pd

url = ("https://github.com/muntasirmasum/brfssdata/releases/download/"
       "data-2023/brfss_2023.parquet")
df = pd.read_parquet(url)
```

The same URLs work in polars, DuckDB (any language), Julia, or Stata’s
Python bridge. For survey-weighted analysis outside R, use the design
columns shipped in every year: the final weight (`_LLCPWT` from 2011,
`_FINALWT` before), strata (`_STSTR`), and PSU (`_PSU`). The list of
available years lives at `releases/download/data-meta/manifest.json`,
and each file has a `.sha256` companion for verification.

## Data source and citation

All data originate from the CDC BRFSS annual survey files, which are in
the public domain. Suggested citation for the data:

> Centers for Disease Control and Prevention (CDC). Behavioral Risk
> Factor Surveillance System Survey Data. Atlanta, Georgia: U.S.
> Department of Health and Human Services, Centers for Disease Control
> and Prevention, \[appropriate year\].

The hosted parquet files are byte-for-byte derived from CDC’s published
SAS Transport files; the processing pipeline lives in
[`data-raw/`](https://muntasirmasum.github.io/brfssdata/data-raw/) and
every artifact is checksummed.

## License

MIT for the package code. The BRFSS data are a U.S. government work in
the public domain.
