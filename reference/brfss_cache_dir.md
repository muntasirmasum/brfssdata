# Manage the local BRFSS data cache

Downloaded survey years are stored as parquet files in a per-user cache
directory so repeat use, and offline work, never re-download. The cache
location follows
[`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html) and can be
redirected with `options(brfssdata.cache_dir = ...)` or the
`R_USER_CACHE_DIR` environment variable.

- `brfss_cache_dir()` returns the cache directory path.

- `brfss_cache_info()` lists cached files with their sizes. Rows with
  `year = NA` are the metadata files (the manifest and the variable and
  label catalogs), not survey years. `verify = TRUE` also hashes each
  file and compares it with the data manifest's checksum, adding a
  `verified` column: `TRUE` on a match, `FALSE` on a mismatch, `NA`
  where the manifest has no entry to compare against (the manifest
  itself, foreign files, or a manifest published without hashes).
  Hashing reads every byte, roughly two seconds for a full 40-year
  cache, so it is off by default; the comparison uses the cached or
  bundled manifest and never touches the network.

- `brfss_cache_clear()` deletes cached survey years, all of them by
  default, and reports what it removed. The manifest and catalogs are
  kept unless `catalogs = TRUE`, so offline use of
  [`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md)
  and
  [`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md)
  survives a data-cache clear.

## Usage

``` r
brfss_cache_dir()

brfss_cache_info(verify = FALSE)

brfss_cache_clear(years = NULL, catalogs = FALSE)
```

## Arguments

- verify:

  If `TRUE`, `brfss_cache_info()` hashes every cached file and adds the
  `verified` column described above.

- years:

  Optional integer vector. If supplied to `brfss_cache_clear()`, only
  those survey years are removed; `integer(0)` removes none (useful with
  `catalogs = TRUE`). Fractional, infinite, missing, or non-numeric
  years are rejected (`brfssdata_bad_years_arg`) before anything is
  deleted.

- catalogs:

  If `TRUE`, `brfss_cache_clear()` also removes the manifest and the
  variable and label catalogs.

## Value

`brfss_cache_dir()` returns a path (character). `brfss_cache_info()`
returns a tibble with columns `file`, `year`, and `size` (bytes), plus
`verified` (logical) under `verify = TRUE`. `brfss_cache_clear()`
returns, invisibly, the paths it removed.

## Examples

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
#> 6 manifest.json              NA     6562
```
