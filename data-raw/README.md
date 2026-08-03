# Data pipeline

Turns CDC BRFSS annual files into the hosted parquet releases the package
reads. Not part of the installed package (`.Rbuildignore`d).

Run the numbered scripts in order, from the package root, in the uvr
environment:

1. `01_download.R` — download annual XPT zips from CDC into
   `data-raw/raw/` (gitignored). CDC sits behind Akamai bot protection
   that 403s most non-browser clients; the script sends browser-like
   headers, but expect to run this step from a residential network, or
   drop manually downloaded zips into `data-raw/raw/`.
2. `02_build_parquet.R` — read each XPT with haven, add an integer
   `year` column, keep CDC variable names verbatim, write one
   zstd-compressed parquet per year to `data-raw/parquet/` (gitignored),
   and assert row counts against both CDC's year pages (where known) and
   the counts recorded from the published releases.
3. `03_catalog.R` — build `brfss_variables.parquet` (variable, label,
   year) from the processed years, using the variable labels haven reads
   from the XPT files.
4. `05_labels.R` — parse CDC's SAS format libraries into
   `brfss_labels.parquet` (year, variable, code, label, complete), the
   value-label catalog behind `brfss_labels()`, `labels = TRUE`, and the
   `na = TRUE` missing-code handling.
5. `04_upload.R` — create/refresh the GitHub releases: one `data-YYYY`
   release per year with its parquet plus a `.sha256` file, and a
   `data-meta` release holding `manifest.json` (schema v2, with a
   per-asset sha256/size map the package verifies at download time),
   `brfss_variables.parquet`, `brfss_labels.parquet`, and their
   `.sha256` sidecars. The manifest is uploaded last, so a partially
   published year is never advertised. `publish_meta()` also refreshes
   the bundled fallback `inst/extdata/manifest.json` from the same code
   path.
6. `site_year_stats.R` — record per-year row/column/size statistics
   from the published releases into
   `vignettes/articles/brfss_year_stats.csv`, which feeds the "The
   datasets" article and the row-count regression pins in step 2.
   Re-run after publishing new data years.

Era notes encoded in the scripts:

- URL patterns: `LLCPyyyyXPT.zip` (2011+), `CDBRFSyyXPT.zip`
  (1990-2010), `CDBRFSyy_XPT.zip` (1984-1989, from lodown's catalog;
  those years are no longer on CDC's index, so treat as a probe).
- Weights: `_FINALWT` before 2011, `_LLCPWT` after; strata `_STSTR` and
  PSU `_PSU` throughout. From 2013 on (2015 excepted) the files also
  carry `_LLCPWT2` for split-questionnaire content, selectable via
  `brfss_design(weight = )`.
- Validation targets per year (records, variables) come from the CDC
  year pages and are asserted in `02_build_parquet.R` for the years
  where they are known; every year is additionally pinned to the row
  count recorded from the published release.

Possible later data release: a `weight_hint` column in the variable
catalog, derived from CDC's annual "Complex Sampling Weights and
Preparing Module Data for Analysis" documents, so `brfss_design()`
could detect when an analysis variable calls for a module weight
instead of relying on documentation alone. Needs no package API change.
