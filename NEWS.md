# brfssdata 0.1.0

* Initial development version: read_brfss(), brfss_design(), brfss_vars(),
  brfss_years(), and cache management.
* Value labels: brfss_labels() exposes CDC's format-library labels
  (1998-2024), and `labels = TRUE` in read_brfss()/brfss_design()
  converts variables with safe code-to-label maps into factors.
* `vars` is matched case-insensitively in read_brfss(), brfss_design(),
  and brfss_labels(), so `"genhlth"` finds `GENHLTH`. Returned columns
  keep CDC's canonical uppercase names.
* Added a package citation (`citation("brfssdata")`) alongside the CDC
  data citation.
* Declared the minimum duckdb version (>= 1.5.5). Connections are opened
  with `shared_home = FALSE`, which earlier duckdb releases reject.
* brfss_design() is much faster on 2001 and later years, and pooling
  several of them now works at all. Those files give every respondent
  their own PSU, so the clustering carries no information; the design is
  built without a cluster term, which leaves the estimates, standard
  errors, and degrees of freedom unchanged. A weighted mean over one year
  went from about 80 seconds to 1.5, and over two pooled years from 345
  seconds to 3. Pooling three years previously failed outright, because
  the nested-clusters check that `survey` runs on a design without
  nesting builds a cluster-by-stratum table too large for R to allocate.
* Years through 2000 carry genuine multi-respondent PSUs and keep the
  clustered estimator, which gives a different (correct) standard error
  for them. The choice is made from the data rather than from the year.
