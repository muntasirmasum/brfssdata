## R CMD check results

0 errors | 0 warnings | 0 notes on all local and CI platforms.

win-builder (R-devel) reported 1 NOTE (CRAN incoming feasibility):

* New submission (this is a new release).
* Possibly misspelled words in DESCRIPTION: "BRFSS" is the acronym of
  the Behavioral Risk Factor Surveillance System, the survey this
  package distributes; "microdata" is a standard statistical term.
* A (possibly) invalid relative file URI in README.md has been fixed
  in this submission (now an absolute URL).

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
  real cache, and brfss_cache_clear() manages it.
