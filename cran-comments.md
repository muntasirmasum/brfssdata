## R CMD check results

0 errors | 0 warnings | 0 notes

* This is a new release.

## Test environments

* local macOS (aarch64), R 4.6.1
* GitHub Actions: ubuntu-latest (release, devel, oldrel-1),
  windows-latest (release), macos-latest (release)
* win-builder (devel)

## Notes for reviewers

* All data access is download-on-demand from GitHub release assets;
  every example that touches the network is gated behind
  @examplesIf interactive(), and tests mock all downloads, so checks
  run fully offline.
* Downloads cache under tools::R_user_dir(); tests never touch the
  real cache, and brfss_cache_clear() manages it.
