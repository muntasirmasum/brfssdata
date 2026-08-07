# Prefetch BRFSS data and metadata into the local cache

Downloads the requested survey years, and by default also the data
manifest and the metadata catalogs (variables, labels, the rename
crosswalk, and the year inventory), so that everything works offline
afterwards:
[`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md),
[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md),
[`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md),
[`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md),
[`brfss_crosswalk()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_crosswalk.md),
[`brfss_year_info()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_year_info.md),
and `labels`/`na` conversion all run from the cache. Use it to populate
the cache once on a connected machine (the directory from
[`brfss_cache_dir()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
can then be copied to an air-gapped one), or to pre-download years ahead
of a workshop. Files already cached and current are not re-downloaded.

## Usage

``` r
brfss_download(years = NULL, catalogs = TRUE, quiet = FALSE)
```

## Arguments

- years:

  Optional integer vector of survey years to cache. `NULL` fetches only
  the metadata.

- catalogs:

  If `TRUE` (the default), also cache the manifest and the metadata
  catalogs.

- quiet:

  If `TRUE`, suppress download progress and the summary.

## Value

Invisibly, the
[`brfss_cache_info()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
tibble after the fetch.

## Examples

``` r
if (FALSE) { # interactive()
brfss_download(2019:2023)
}
```
