# Manage the local BRFSS data cache

Downloaded survey years are stored as parquet files in a per-user cache
directory so repeat use, and offline work, never re-download. The cache
location follows
[`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html) and can be
redirected with `options(brfssdata.cache_dir = ...)` or the
`R_USER_CACHE_DIR` environment variable. The option must be a single
non-empty path that is not an existing regular file; anything else is
rejected (`brfssdata_bad_option`) rather than read as an empty cache.

- `brfss_cache_dir()` returns the cache directory path.

- `brfss_cache_info()` lists cached files with their sizes. Rows with
  `year = NA` are the metadata files (the manifest and the variable and
  label catalogs), not survey years. `verify = TRUE` also hashes each
  file and compares it with the data manifest's checksum, adding a
  `verified` column: `TRUE` on a match, `FALSE` on a mismatch, `NA`
  where the manifest has no entry to compare against (the manifest
  itself, foreign files, or a manifest published without hashes).
  Hashing reads every byte, roughly two seconds for a cache holding
  every year, so it is off by default; the comparison uses the cached or
  bundled manifest and never touches the network.

- `brfss_cache_clear()` deletes cached survey years, all of them by
  default, and reports what it removed. The manifest and catalogs are
  kept unless `catalogs = TRUE`, so offline use of
  [`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md)
  and
  [`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md)
  survives a data-cache clear. Called with no `years` argument in an
  interactive session, it asks for confirmation before deleting
  everything; scripts and rendered documents are never prompted, and an
  explicit `years = NULL` clears all years without asking in any
  session.

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
  `catalogs = TRUE`) and `NULL` removes every year without the
  interactive confirmation. Fractional, infinite, missing, or
  non-numeric years are rejected (`brfssdata_bad_years_arg`) before
  anything is deleted.

- catalogs:

  If `TRUE`, `brfss_cache_clear()` also removes the manifest and the
  variable and label catalogs.

## Value

`brfss_cache_dir()` returns a path (character). `brfss_cache_info()`
returns a tibble with columns `file`, `year`, and `size` (bytes), plus
`verified` (logical) under `verify = TRUE`. `brfss_cache_clear()`
returns, invisibly, the paths it removed.

## See also

[brfssdata-options](https://muntasirmasum.github.io/brfssdata/reference/brfssdata-options.md)
for every session option the package reads.

## Examples

``` r
brfss_cache_dir()
#> [1] "/home/runner/.cache/R/brfssdata"
brfss_cache_info()
#> # A tibble: 0 × 3
#> # ℹ 3 variables: file <chr>, year <int>, size <dbl>
```
