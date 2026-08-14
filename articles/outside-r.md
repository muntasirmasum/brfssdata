# Using the data outside R

brfssdata is an R package, but the files it distributes are not an R
format. Every survey year is a plain parquet file on a public release,
and the R functions are one client among several. This article shows how
to read those files from Python, from the DuckDB command line, and from
SAS and Stata, and how to export an extract from R when a collaborator
needs a file they can open in their own software.

## The hosted files

Forty survey years, 1985 through 2024, are published as one parquet file
per year at a fixed URL. Substitute the survey year in both places:

    https://github.com/muntasirmasum/brfssdata/releases/download/data-YYYY/brfss_YYYY.parquet

For 2023 that resolves to:

    https://github.com/muntasirmasum/brfssdata/releases/download/data-2023/brfss_2023.parquet

There is no token and no API. The 2023 file is about 29 MB and holds
433,323 rows and 351 columns, compressed with zstd, which every parquet
reader of the last few years handles. Columns keep CDC’s canonical
uppercase names, leading underscores on calculated variables included
(`_LLCPWT`, `_STSTR`, `_PSU`, `_IMPRACE`), so a codebook written against
CDC’s public-use file applies unchanged. One column is added, `year`,
which matters once you read several files at once.

Three companion assets sit under a single `data-meta` tag.
`manifest.json` lists the published years, `brfss_variables.parquet` is
the variable catalog (2,128 distinct variables with their labels and the
years each one appears in), and `brfss_labels.parquet` is the
value-label catalog covering 1998 onward.

    https://github.com/muntasirmasum/brfssdata/releases/download/data-meta/manifest.json
    https://github.com/muntasirmasum/brfssdata/releases/download/data-meta/brfss_variables.parquet
    https://github.com/muntasirmasum/brfssdata/releases/download/data-meta/brfss_labels.parquet

## Python

pandas reads a parquet URL directly. Naming the columns you want keeps
memory down, though on plain HTTP the whole file still arrives before
anything is decoded.

``` python
import pandas as pd

url = (
    "https://github.com/muntasirmasum/brfssdata/releases/download/"
    "data-2023/brfss_2023.parquet"
)

df = pd.read_parquet(url, columns=["year", "GENHLTH", "_LLCPWT"])
df["GENHLTH"].value_counts().sort_index()
```

DuckDB is the better tool when you want a slice of a year rather than
the year. It reads the file over HTTP range requests, so a query
touching three columns transfers roughly those three columns instead of
all 351. Quote the underscore-prefixed names in SQL; unquoted, `_LLCPWT`
is not a valid identifier.

``` python
import duckdb

duckdb.sql(f"""
  SELECT GENHLTH,
         count(*) AS n,
         sum("_LLCPWT") AS weighted_n
  FROM read_parquet('{url}')
  GROUP BY GENHLTH
  ORDER BY GENHLTH
""")
```

Add `.df()` to hand the result back to pandas, or `.arrow()` for an
Arrow table. Several years combine in one call. Variable sets drift
across years, so `union_by_name = true` fills the gaps with nulls, and
the `year` column tells the rows apart afterwards.

``` python
base = "https://github.com/muntasirmasum/brfssdata/releases/download"
files = [f"{base}/data-{y}/brfss_{y}.parquet" for y in (2021, 2022, 2023)]

duckdb.sql(f"""
  SELECT year, count(*) AS n
  FROM read_parquet({files}, union_by_name = true)
  GROUP BY year
  ORDER BY year
""").df()
```

polars works the same way through `pl.read_parquet()`, and pyarrow
through `pyarrow.parquet.read_table()`.

## The DuckDB command line

Nothing about the above needs Python. The DuckDB CLI runs the same
queries, and the `httpfs` extension is what teaches it to read an https
path. Recent versions load that extension on demand, but installing it
explicitly works on any version.

``` sql
INSTALL httpfs;
LOAD httpfs;

SELECT year, GENHLTH, count(*) AS n
FROM read_parquet(
  'https://github.com/muntasirmasum/brfssdata/releases/download/data-2023/brfss_2023.parquet'
)
GROUP BY year, GENHLTH
ORDER BY GENHLTH;
```

`DESCRIBE SELECT * FROM read_parquet(...)` prints the schema without
reading the rows, which is a quick way to check whether a variable
exists in a given year. To hand a subset to software that cannot read
parquet, `COPY` writes it out:

``` sql
COPY (
  SELECT year, GENHLTH, SEXVAR, "_LLCPWT", "_STSTR", "_PSU"
  FROM read_parquet(
    'https://github.com/muntasirmasum/brfssdata/releases/download/data-2023/brfss_2023.parquet'
  )
) TO 'brfss_2023_extract.csv' (HEADER, FORMAT CSV);
```

## SAS

SAS support for parquet depends on which SAS you run, and the honest
summary is narrow. The SAS Viya platform provides a LIBNAME engine for
parquet, introduced in Viya 2021.2.6, and SAS documents ZSTD, the codec
these files use, among the compression types that engine reads. That
engine is not part of SAS 9, and its reach has grown release by release,
starting with directories local to the compute server and adding cloud
object storage later. It also points at a directory rather than a URL,
so you would download the file first. If you run Viya, check the LIBNAME
engines for ORC and Parquet reference for your release before assuming a
path works; the shape of the code is this:

``` sas
libname brfss parquet "/path/to/downloaded/files";

proc surveyfreq data = brfss.brfss_2023;
  strata _STSTR;
  cluster _PSU;
  weight _LLCPWT;
  tables GENHLTH;
run;
```

The route that works on any SAS, including SAS 9, is to export a SAS
Transport file from R.
[`haven::write_xpt()`](https://haven.tidyverse.org/reference/read_xpt.html)
writes one.

``` r

library(brfssdata)
library(dplyr)
library(haven)

extract <- read_brfss(
  2023,
  vars = c(
    "GENHLTH", "SEXVAR", "_AGE_G", "_IMPRACE",
    "_LLCPWT", "_STSTR", "_PSU"
  ),
  quiet = TRUE
) |>
  slice_head(n = 5000)

xpt <- tempfile(fileext = ".xpt")
write_xpt(extract, xpt)
file.size(xpt)
#> [1] 321840
```

Reading it back confirms the names survived:

``` r

names(read_xpt(xpt, n_max = 1))
#> [1] "GENHLTH"  "SEXVAR"   "_AGE_G"   "_IMPRACE" "_LLCPWT"  "_STSTR"   "_PSU"    
#> [8] "year"
```

### Which transport version

Transport files come in two flavors, SAS reads them by different routes,
and `version` is therefore the argument that decides whether your
collaborator can open the file at all.

Version 8 is haven’s default and allows variable names up to 32
characters. SAS’s XPORT libname engine cannot read it, because that
engine implements the Version 5 feature set; pointed at a V8 file it
reports that the file is not a SAS data set. What reads it is the
`%XPT2LOC` autocall macro, which has shipped with SAS since 9.4M2 and
handles both flavors:

``` sas
filename xptfile "/path/to/brfss23.xpt";
%xpt2loc(libref = work, filespec = xptfile);
```

Version 5 is the older specification and the one the XPORT engine reads
directly, which is why submission workflows and older sites still ask
for it:

``` sas
libname xptfile xport "/path/to/brfss23.xpt";

proc copy in = xptfile out = work;
run;
```

Version 5 caps both the dataset member name and every variable name at 8
characters. The member name defaults to the file name without its
extension, so a random temporary file name fails outright:

``` r

write_xpt(extract, tempfile(fileext = ".xpt"), version = 5)
#> Error in `write_xpt()`:
#> ! `name` must be 8 characters or fewer.
```

Pass `name` to fix that. Variable names are the subtler problem. Every
one of the 2,128 variables in CDC’s catalog is 8 characters or fewer,
`_IMPRACE` sitting exactly at the limit, so a straight CDC extract comes
through version 5 unchanged. Derived variables do not, and the
truncation is silent:

``` r

derived <- extract |>
  mutate(fairpoor_health = as.integer(GENHLTH %in% 4:5))

v5 <- tempfile(fileext = ".xpt")
write_xpt(derived, v5, version = 5, name = "brfss23")
names(read_xpt(v5, n_max = 1))
#> [1] "GENHLTH"  "SEXVAR"   "_AGE_G"   "_IMPRACE" "_LLCPWT"  "_STSTR"   "_PSU"    
#> [8] "year"     "fairpoor"
```

`fairpoor_health` arrives as `fairpoor`, with no warning, and two
derived names sharing their first 8 characters would collide the same
way. Choose by what the recipient will run: version 8 if they can call
`%XPT2LOC`, version 5 if they will point the XPORT engine at the file,
and in that second case rename your derived variables to 8 characters
yourself so you pick the abbreviations instead of inheriting them.

Transport files carry the numeric codes, not the meanings. Ship the
relevant slice of the value-label catalog next to the data so the
recipient has a codebook:

``` r

brfss_labels(
  c("GENHLTH", "SEXVAR", "_AGE_G", "_IMPRACE"),
  years = 2023
) |>
  arrange(variable, code)
#> # A tibble: 21 × 5
#>     year variable  code label              complete
#>    <int> <chr>    <int> <chr>              <lgl>   
#>  1  2023 GENHLTH      1 Excellent          TRUE    
#>  2  2023 GENHLTH      2 Very good          TRUE    
#>  3  2023 GENHLTH      3 Good               TRUE    
#>  4  2023 GENHLTH      4 Fair               TRUE    
#>  5  2023 GENHLTH      5 Poor               TRUE    
#>  6  2023 GENHLTH      7 Dont know/Not Sure TRUE    
#>  7  2023 GENHLTH      9 Refused            TRUE    
#>  8  2023 SEXVAR       1 Male               TRUE    
#>  9  2023 SEXVAR       2 Female             TRUE    
#> 10  2023 _AGE_G       1 Age 18 to 24       TRUE    
#> # ℹ 11 more rows
```

## Stata

[`haven::write_dta()`](https://haven.tidyverse.org/reference/read_dta.html)
writes a Stata file, defaulting to the Stata 14 format; pass
`version = 13` or lower for older Stata. The complication is naming.
Stata permits a leading underscore but reserves such names for its own
system variables (`_n`, `_N`, `_b`, `_cons`), and the manual advises
against user variables that begin with one. haven does not enforce this,
so [`write_dta()`](https://haven.tidyverse.org/reference/read_dta.html)
on a raw BRFSS extract succeeds and the trouble surfaces later, in
Stata. Rename first:

``` r

for_stata <- extract |>
  rename_with(\(x) sub("^_", "x_", x))

names(for_stata)
#> [1] "GENHLTH"   "SEXVAR"    "x_AGE_G"   "x_IMPRACE" "x_LLCPWT"  "x_STSTR"  
#> [7] "x_PSU"     "year"

dta <- tempfile(fileext = ".dta")
write_dta(for_stata, dta)
file.size(dta)
#> [1] 305675
```

Prefixing is safer than deleting the underscore outright. CDC’s catalog
contains both `_RACE` and `RACE`, and both `_SEX` and `SEX`, among other
pairs, so stripping the character can quietly merge two different
variables in a multi-year extract. Stata allows names up to 32
characters, which nothing in BRFSS comes near.

On the Stata side, declare the design before estimating anything:

``` stata
use "brfss_2023_extract.dta", clear

svyset x_PSU [pweight = x_LLCPWT], strata(x_STSTR) singleunit(centered)
svy: proportion GENHLTH
```

Single-PSU strata are common in BRFSS, because the public-use files give
each respondent their own primary sampling unit within a stratum, so any
stratum holding one respondent holds one PSU. Software differs in what
it does with them. In R,
[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
sets `options(survey.lonely.psu = "adjust")` when the option is unset
(any value other than survey’s own load-time `"fail"` counts as set by
you), which centers those strata at the grand mean;
`singleunit(centered)` is the Stata option with the same behavior.

Reading with `read_brfss(labels = TRUE)` returns factors for variables
whose CDC format is a complete code-to-label map covering every observed
value, and
[`write_dta()`](https://haven.tidyverse.org/reference/read_dta.html)
turns those factors into Stata value labels, so the codes arrive already
documented.

## CSV

CSV is the format nothing refuses, and when you do not know what the
recipient will open the file with, it is the safe answer.

``` r

readr::write_csv(for_stata, "brfss_2023_extract.csv")

# base R only
utils::write.csv(for_stata, "brfss_2023_extract.csv", row.names = FALSE)
```

The cost is size and types. Written out in full, the 2023 file is about
447 MB as CSV against 29 MB as parquet, roughly fifteen times larger.
None of the column types survive the trip either, so every reader on the
other end re-guesses whether a column is integer, double, or text, and a
leading-zero FIPS code or a variable that is numeric in one year and
character in another is where that guessing goes wrong. Send a
column-selected, row-filtered extract instead of a whole year, and if
the recipient can read parquet at all, send parquet.

## Citing and verifying

Whatever tool opens the file, the data are CDC’s and the citation is
CDC’s:

> Centers for Disease Control and Prevention (CDC). Behavioral Risk
> Factor Surveillance System Survey Data. Atlanta, Georgia: U.S.
> Department of Health and Human Services, Centers for Disease Control
> and Prevention, \[appropriate year\].

Each parquet file is built from CDC’s published SAS Transport release by
the pipeline in
[`data-raw/`](https://github.com/muntasirmasum/brfssdata/tree/main/data-raw),
and every published survey year has a `.sha256` companion at the same
URL with `.sha256` appended. Anyone downloading outside R can check what
they received:

``` bash
base=https://github.com/muntasirmasum/brfssdata/releases/download/data-2023

curl -LO $base/brfss_2023.parquet
curl -LO $base/brfss_2023.parquet.sha256

shasum -a 256 -c brfss_2023.parquet.sha256   # sha256sum -c on Linux
#> brfss_2023.parquet: OK
```

Recording that checksum alongside the analysis is what lets someone else
confirm years later that they are holding the same file you analyzed.
