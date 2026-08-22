# One row per published BRFSS survey year

The year inventory that accompanies the data releases: respondent and
variable counts, the number of reporting jurisdictions, the hosted
file's size in bytes, the CDC documentation page for the year, and the
identity of the CDC source file each year was built from, plus a locally
computed `cached` flag saying whether the year is already in
[`brfss_cache_dir()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md).
Use it to see the collection at a glance before downloading anything;
[`brfss_years()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_years.md)
remains the plain integer vector of published years.

## Usage

``` r
brfss_year_info(years = NULL, download = TRUE, quiet = TRUE)
```

## Arguments

- years:

  Optional integer vector restricting to those years.

- download:

  If `FALSE`, only a cached catalog is used, and a missing catalog
  raises an error instead of being downloaded.

- quiet:

  If `TRUE`, suppress download progress output.

## Value

A tibble with columns `year`, `respondents`, `variables`, `states`
(reporting jurisdictions in the file), `size` (bytes of the hosted
parquet), `codebook_url` (CDC's documentation page for the year), the
source-identity columns `source_file` (the CDC file the year was built
from), `source_format`, `source_sha256` (its checksum as downloaded),
and `downloaded` (the date it was retrieved from CDC), and `cached`
(logical, computed locally).

## See also

[`brfss_years()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_years.md);
the *datasets* article for the same numbers in prose.

## Examples

``` r
if (FALSE) { # interactive()
brfss_year_info(2019:2023)
}
```
