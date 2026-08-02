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
   and record row/column counts for validation.
3. `03_catalog.R` — build `brfss_variables.parquet` (variable, label,
   year) from the processed years, using the variable labels haven reads
   from the XPT files.
4. `04_upload.R` — create/refresh the GitHub releases: one `data-YYYY`
   release per year with its parquet plus a `.sha256` file, and a
   `data-meta` release holding `manifest.json` and the variable catalog.
   The manifest is uploaded last, so a partially published year is never
   advertised.

Era notes encoded in the scripts:

- URL patterns: `LLCPyyyyXPT.zip` (2011+), `CDBRFSyyXPT.zip`
  (1990-2010), `CDBRFSyy_XPT.zip` (1984-1989, from lodown's catalog;
  those years are no longer on CDC's index, so treat as a probe).
- Weights: `_FINALWT` before 2011, `_LLCPWT` after; strata `_STSTR` and
  PSU `_PSU` throughout.
- Validation targets per year (records, variables) come from the CDC
  year pages and are asserted in `02_build_parquet.R` for the years
  where they are known.
