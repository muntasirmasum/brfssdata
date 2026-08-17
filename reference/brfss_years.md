# List the BRFSS survey years available for download

Reads the data manifest that accompanies the hosted parquet releases and
returns the survey years currently published. The manifest is cached
locally and refreshed at most once a day; pass `refresh = TRUE` to force
a new download.

The three arguments cover the three questions in order. `download`
decides whether the network may be touched at all, `refresh` forces a
download that the daily cadence would otherwise skip, and `quiet`
silences the housekeeping notes. `download = FALSE` therefore wins over
`refresh = TRUE`: the strictly offline promise is the stronger one, and
the skipped refresh is reported rather than assumed.

## Usage

``` r
brfss_years(refresh = FALSE, download = TRUE, quiet = FALSE)
```

## Arguments

- refresh:

  If `TRUE`, re-download the manifest even if a fresh cached copy
  exists. Ignored under `download = FALSE`.

- download:

  If `FALSE`, only the cached (or bundled) manifest is read and the
  network is never touched.

- quiet:

  If `TRUE`, suppress the housekeeping notes about which copy was used
  (`brfssdata_manifest_note`). The returned years are the same either
  way.

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
