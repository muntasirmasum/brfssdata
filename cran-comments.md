## R CMD check results

0 errors | 0 warnings | 1 note

The note is "New submission" (CRAN incoming feasibility). No other
check produced a note, warning, or error.

win-builder additionally flags two words in DESCRIPTION as possibly
misspelled: "BRFSS" is the acronym of the Behavioral Risk Factor
Surveillance System, the survey this package distributes, and
"microdata" is a standard statistical term for respondent-level records.

## Test environments

* local macOS (aarch64), R 4.6.1
* GitHub Actions: ubuntu-latest (release, devel, oldrel-1),
  windows-latest (release), macos-latest (release)
* win-builder (devel)
* R-hub v2: linux, windows, macos

## Notes for reviewers

* All data access is download-on-demand from GitHub release assets;
  every example that touches the network is gated behind
  @examplesIf interactive(), and tests mock all downloads, so checks
  run fully offline.
* Downloads cache under tools::R_user_dir(); tests never touch the
  real cache, and brfss_cache_clear() manages it. Connections are
  opened with duckdb's shared_home = FALSE so nothing is written
  outside the cache and session temp directory, which is why
  DESCRIPTION requires duckdb (>= 1.5.5).
* The vignette's code is not evaluated during the package build, so no
  network access is needed; the same document runs live on the package
  website, where the data are available.
