# Changelog

## brfssdata 0.1.0

Initial CRAN release.

- [`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
  returns respondent-level BRFSS microdata for any of the 40 published
  survey years (1985-2024) as a tibble. Each year is downloaded once
  from the package’s data releases, verified against a published sha256
  checksum, and cached under
  [`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html); queries
  run locally through DuckDB, so selecting a handful of variables from a
  300-plus column survey stays fast and repeat use works offline.
- [`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
  builds a srvyr survey-design object with the era-correct final weight
  (`_FINALWT` through 2010, `_LLCPWT` from 2011), strata, and primary
  sampling units. Requests that pool years across the 2011 redesign fail
  unless `allow_break = TRUE` is set, because CDC states estimates are
  not comparable across that boundary. Files through 2000 carry genuine
  multi-respondent PSUs and keep the clustered variance estimator; from
  2001 on each respondent is their own PSU, and the design drops the
  nominal cluster term for identical estimates at a fraction of the
  cost. A `weight` argument selects another final weight, such as the
  child weight `_CLLCPWT`, when CDC’s documentation calls for it;
  requesting an intermediate stage of CDC’s weighting pipeline (such as
  `_LLCPWT2`, the truncated design weight computed before raking)
  triggers a classed warning, because those columns are not analysis
  weights. Module analyses that require CDC’s questionnaire-version
  datasets and their `_LCPWTV1` to `_LCPWTV3` final weights are not
  supported by the hosted annual files.
- By default,
  [`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
  sets the codes CDC uses for don’t-know, refused, and missing-type
  answers to `NA` (`na = TRUE`), so means and proportions cover
  substantive answers;
  [`read_brfss()`](https://muntasirmasum.github.io/brfssdata/reference/read_brfss.md)
  defaults to `na = FALSE` and returns the file as published. The
  exported
  [`brfss_missing_codes()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_missing_codes.md)
  lists exactly which codes are affected.
- [`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md)
  exposes CDC’s value-label catalog (1998-2024), and `labels = TRUE`
  converts variables with safe one-to-one maps to factors; ambiguous
  maps keep their numeric codes. `labels = "both"` keeps the code in the
  level text so it survives conversion.
- [`brfss_vars()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_vars.md)
  searches variable names and labels across years;
  [`brfss_years()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_years.md)
  lists the published years. Variable names match case-insensitively
  everywhere, and returned columns keep CDC’s canonical spelling.
- [`brfss_download()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_download.md)
  prefetches years and the metadata catalogs for offline use;
  [`brfss_cache_dir()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md),
  [`brfss_cache_info()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md),
  and
  [`brfss_cache_clear()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
  manage the cache. A cached file that fails integrity checks is
  re-downloaded automatically or named in a classed error with its
  remedy.
- Every error, warning, and message carries a documented condition
  class; see `?brfssdata-conditions`.
