# List the BRFSS survey years available for download

Reads the data manifest that accompanies the hosted parquet releases and
returns the survey years currently published. The manifest is cached
locally and refreshed at most once a day; pass `refresh = TRUE` to force
a new download.

## Usage

``` r
brfss_years(refresh = FALSE)
```

## Arguments

- refresh:

  If `TRUE`, re-download the manifest even if a fresh cached copy
  exists.

## Value

An integer vector of available survey years. If the manifest cannot be
refreshed, or the cached copy is unreadable, a message notes the
fallback (cached or bundled copy) that was used instead.

## Examples

``` r
if (FALSE) { # interactive()
brfss_years()
}
```
