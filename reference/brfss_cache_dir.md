# Manage the local BRFSS data cache

Downloaded survey years are stored as parquet files in a per-user cache
directory so repeat use, and offline work, never re-download. The cache
location follows
[`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html) and can be
redirected with `options(brfssdata.cache_dir = ...)` or the
`R_USER_CACHE_DIR` environment variable.

- `brfss_cache_dir()` returns the cache directory path.

- `brfss_cache_info()` lists cached files with their sizes.

- `brfss_cache_clear()` deletes cached files, all years by default.

## Usage

``` r
brfss_cache_dir()

brfss_cache_info()

brfss_cache_clear(years = NULL)
```

## Arguments

- years:

  Optional integer vector. If supplied to `brfss_cache_clear()`, only
  those survey years are removed.

## Value

`brfss_cache_dir()` returns a path (character). `brfss_cache_info()`
returns a tibble with columns `file`, `year`, and `size`.
`brfss_cache_clear()` returns, invisibly, the paths it removed.

## Examples

``` r
brfss_cache_dir()
#> [1] "/home/runner/.cache/R/brfssdata"
brfss_cache_info()
#> # A tibble: 0 × 3
#> # ℹ 3 variables: file <chr>, year <int>, size <dbl>
```
