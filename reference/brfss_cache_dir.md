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
#> # A tibble: 6 × 3
#>   file                     year     size
#>   <chr>                   <int>    <dbl>
#> 1 brfss_2021.parquet       2021 26033879
#> 2 brfss_2022.parquet       2022 26280485
#> 3 brfss_2023.parquet       2023 29077288
#> 4 brfss_labels.parquet       NA   119739
#> 5 brfss_variables.parquet    NA    63889
#> 6 manifest.json              NA      285
```
