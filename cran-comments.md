## Update

This is a patch release, 0.1.0 to 0.1.1, and it changes no R code. It
adds the package's CRAN DOI to inst/CITATION, documents four columns
that brfss_year_info() already returns from the hosted year inventory,
refreshes the crosswalk and manifest snapshots bundled in inst/extdata,
and corrects wording in the vignette and README.

## R CMD check results

PENDING: fill in from the checks below before submitting.

## Test environments

* local macOS (aarch64): PENDING (R version, date, result, test count)
* GitHub Actions: ubuntu-latest (R 4.2, release, devel, oldrel-1),
  windows-latest (release), macos-latest (release): PENDING
* win-builder (devel and release): PENDING
* R-hub v2 (R-devel): linux, windows, macos: PENDING

## Reverse dependencies

PENDING: confirm there are none with
tools::package_dependencies("brfssdata", db = available.packages(),
reverse = TRUE).

## Notes for reviewers

* All data access is download-on-demand from GitHub release assets.
  Examples for the metadata functions run offline against catalog
  snapshots bundled in inst/extdata (they pass download = FALSE, which
  never touches the network); examples that would download survey data
  are gated behind @examplesIf interactive(); and tests mock all
  downloads. Checks therefore run fully offline.
* Downloaded data are stored under tools::R_user_dir("brfssdata",
  "cache") in line with CRAN's storage policy: nothing is downloaded
  except on an explicit user request, the location is announced the
  first time it is created and reported by brfss_cache_dir(), and the
  contents are managed by the exported brfss_cache_info() and
  brfss_cache_clear(). Downloads are verified against published sha256
  checksums, and files that fail later integrity checks are replaced
  or reported with their remedy. Nothing is written outside that
  directory and the session tempdir.
* DESCRIPTION requires duckdb (>= 1.5.5) because connections are opened
  with duckdb's shared_home = FALSE, which keeps DuckDB's own storage
  out of ~/.duckdb (the write-location policy above). That argument
  first appears in duckdb 1.5.5: verified against the duckdb-r sources,
  R/Driver.R carries it at tag v1.5.5 and not at v1.5.4.3 or any
  earlier release, so the floor is the minimum that works, not merely
  the newest version.
* No vignette chunk that touches data or the network is evaluated
  during the package build (the one evaluated chunk prints the local
  citation), so checks need no network access; the same document runs
  live on the package website, where the data are available.
