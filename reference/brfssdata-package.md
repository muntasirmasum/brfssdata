# brfssdata: Access CDC Behavioral Risk Factor Surveillance System Data

Download, cache, and analyze annual microdata from the United States
Centers for Disease Control and Prevention Behavioral Risk Factor
Surveillance System (BRFSS) <https://www.cdc.gov/brfss/>. Each requested
survey year is downloaded once as a compact file hosted on public
releases, verified against a published checksum, and cached locally;
queries then run through 'DuckDB' (via the 'duckdb' package), so column
selection and repeat analyses never re-transfer data. Survey-design
helpers construct 'srvyr' design objects with year-appropriate weights,
strata, and primary sampling units, including explicit handling of the
2011 weighting methodology change and of the codes CDC uses for
missing-type answers.

## Getting started

[`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
downloads a survey year once, caches it, and reads the columns you name
into a tibble.
[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
returns the same extract as an srvyr survey design with the year's own
weight, strata, and PSU already set, which is what prevalence estimates
and their intervals need.

To find out what to ask for,
[`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md)
searches variable names and labels across years,
[`brfss_codebook()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_codebook.md)
prints what the catalogs know about a variable, and
[`brfss_crosswalk()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_crosswalk.md)
follows CDC's renames across generations.
[`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md)
and
[`brfss_missing_codes()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_missing_codes.md)
are the value-label and missing-code tables behind the `labels` and `na`
arguments of the two read paths.

[`brfss_years()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_years.md),
[`brfss_year_info()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_year_info.md),
and
[`brfss_download()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_download.md)
cover what is published and what is cached;
[`brfss_cache_dir()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md),
[`brfss_cache_info()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md),
and
[`brfss_cache_clear()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
manage the cache itself, and
[`brfss_citation()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_citation.md)
cites the years you used.
[brfssdata-conditions](https://muntasirmasum.github.io/brfssdata/reference/brfssdata-conditions.md)
lists the class of every error, warning, and message the package
signals.

## See also

Useful links:

- <https://muntasirmasum.github.io/brfssdata/>

- <https://github.com/muntasirmasum/brfssdata>

- Report bugs at <https://github.com/muntasirmasum/brfssdata/issues>

## Author

**Maintainer**: Muntasir Masum <muntasir.1124@gmail.com>
([ORCID](https://orcid.org/0000-0002-4210-2844)) \[copyright holder\]

Authors:

- Muntasir Masum <muntasir.1124@gmail.com>
  ([ORCID](https://orcid.org/0000-0002-4210-2844)) \[copyright holder\]
