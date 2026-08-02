# Changelog

## brfssdata 0.0.0.9000

- Initial development version: read_brfss(), brfss_design(),
  brfss_vars(), brfss_years(), and cache management.
- Value labels: brfss_labels() exposes CDC’s format-library labels
  (1998-2024), and `labels = TRUE` in read_brfss()/brfss_design()
  converts variables with safe code-to-label maps into factors.
