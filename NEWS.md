# brfssdata 0.1.0

Initial CRAN release.

* `read_brfss()` returns respondent-level BRFSS microdata for any of the
  40 published survey years (1985-2024) as a tibble. Each year is
  downloaded once from the package's data releases, verified against a
  published sha256 checksum, and cached under `tools::R_user_dir()`;
  queries run locally through DuckDB, so selecting a handful of
  variables from a 300-plus column survey stays fast and repeat use
  works offline.
* `brfss_design()` builds a srvyr survey-design object with the
  era-correct final weight (`_FINALWT` through 2010, `_LLCPWT` from
  2011), strata, and primary sampling units. Requests that pool years
  across the 2011 redesign fail unless `allow_break = TRUE` is set,
  because CDC states estimates are not comparable across that boundary.
  Files through 2000 carry genuine multi-respondent PSUs and keep the
  clustered variance estimator; from 2001 on each respondent is their
  own PSU, and the design drops the nominal cluster term for identical
  estimates at a fraction of the cost. A `weight` argument selects
  split-questionnaire weights such as `_LLCPWT2` when CDC's module
  documentation calls for them.
* By default, `brfss_design()` sets the codes CDC uses for don't-know,
  refused, and missing-type answers to `NA` (`na = TRUE`), so means and
  proportions cover substantive answers; `read_brfss()` defaults to
  `na = FALSE` and returns the file as published. The exported
  `brfss_missing_codes()` lists exactly which codes are affected.
* `brfss_labels()` exposes CDC's value-label catalog (1998-2024), and
  `labels = TRUE` converts variables with safe one-to-one maps to
  factors; ambiguous maps keep their numeric codes. `labels = "both"`
  keeps the code in the level text so it survives conversion.
* `brfss_vars()` searches variable names and labels across years;
  `brfss_years()` lists the published years. Variable names match
  case-insensitively everywhere, and returned columns keep CDC's
  canonical spelling.
* `brfss_download()` prefetches years and the metadata catalogs for
  offline use; `brfss_cache_dir()`, `brfss_cache_info()`, and
  `brfss_cache_clear()` manage the cache. A cached file that fails
  integrity checks is re-downloaded automatically or named in a classed
  error with its remedy.
* Every error, warning, and message carries a documented condition
  class; see `?brfssdata-conditions`.
