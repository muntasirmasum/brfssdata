# Package index

## Read data

Download-on-demand access to annual BRFSS microdata.

- [`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
  : Read BRFSS survey microdata
- [`brfss_years()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_years.md)
  : List the BRFSS survey years available for download
- [`brfss_year_info()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_year_info.md)
  : One row per published BRFSS survey year

## Survey-weighted analysis

Design objects with year-appropriate weights, strata, and PSUs.

- [`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
  : Build a survey-design object for BRFSS analysis
- [`brfss_std_pop_2000`](https://muntasirmasum.github.io/brfssdata/reference/brfss_std_pop_2000.md)
  : The 2000 projected U.S. standard population

## Find and understand variables

Search the catalogs, read the codebook, follow renames.

- [`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md)
  : Search BRFSS variables across survey years
- [`brfss_codebook()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_codebook.md)
  : Codebook card: everything the catalogs know about a variable
- [`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md)
  : Value labels for BRFSS variables
- [`brfss_missing_codes()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_missing_codes.md)
  : Codes CDC uses for missing-type answers
- [`brfss_crosswalk()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_crosswalk.md)
  : Rename crosswalk: which variables are generations of one measure

## Reference data

- [`brfss_states`](https://muntasirmasum.github.io/brfssdata/reference/brfss_states.md)
  : BRFSS reporting jurisdictions: FIPS codes, names, and Census regions

## Cite

- [`brfss_citation()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_citation.md)
  : Citations for the package and the survey years an analysis used

## Cache management

- [`brfss_download()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_download.md)
  : Prefetch BRFSS data and metadata into the local cache
- [`brfss_cache_dir()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
  [`brfss_cache_info()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
  [`brfss_cache_clear()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
  : Manage the local BRFSS data cache
