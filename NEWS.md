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
