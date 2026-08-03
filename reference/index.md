# Package index

## Read data

Download-on-demand access to annual BRFSS microdata.

- [`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
  : Read BRFSS survey microdata
- [`brfss_years()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_years.md)
  : List the BRFSS survey years available for download

## Survey-weighted analysis

Design objects with year-appropriate weights, strata, and PSUs.

- [`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
  : Build a survey-design object for BRFSS analysis

## Variables and value labels

Search the variable catalog and CDC value-label maps.

- [`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md)
  : Search BRFSS variables across survey years
- [`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md)
  : Value labels for BRFSS variables
- [`brfss_missing_codes()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_missing_codes.md)
  : Codes CDC uses for missing-type answers

## Cache management

- [`brfss_download()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_download.md)
  : Prefetch BRFSS data and metadata into the local cache
- [`brfss_cache_dir()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
  [`brfss_cache_info()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
  [`brfss_cache_clear()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
  : Manage the local BRFSS data cache
