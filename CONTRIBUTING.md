# Contributing to brfssdata

Thank you for helping. This page covers how to report problems, propose
changes, and set up a development copy. The [Code of
Conduct](https://muntasirmasum.github.io/brfssdata/CODE_OF_CONDUCT.md)
applies to every interaction in this project.

## Reporting a problem

Open an issue at <https://github.com/muntasirmasum/brfssdata/issues>.
Three templates are offered.

- **Bug report**, for an R error or behavior that does not match the
  documentation. Include a minimal reproducible example, the output of
  [`sessionInfo()`](https://rdrr.io/r/utils/sessionInfo.html), and the
  output of
  [`brfss_cache_info()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_cache_dir.md)
  when a download or a cached file is involved.
- **Data problem**, for anything about the hosted files or the catalogs:
  a value label that reads wrong, a code that is or is not treated as
  missing, a crosswalk pairing you doubt, a row count that differs from
  CDC’s codebook. Give the survey year, the variable name as CDC spells
  it, and the code or label in question. Most data questions are settled
  by CDC’s own codebook or SAS format library for that year, so a link
  or page number speeds things up.
- **Feature request**, for new functionality. The package deliberately
  stays a data-access and design-construction layer; tabulation,
  reliability screening, and age standardization are left to
  [survey](https://cran.r-project.org/package=survey) and
  [srvyr](https://cran.r-project.org/package=srvyr), and the articles on
  the package site show those patterns. Requests that fit the layer are
  welcome.

Questions that are not bugs are welcome as issues too; there is no
separate discussion forum.

## Making changes

1.  Fork the repository and branch from `main`.
2.  The package uses standard tooling: `devtools::load_all()`,
    `devtools::test()`, `devtools::document()`, and `devtools::check()`.
    Code is formatted with [air](https://posit-dev.github.io/air/)
    (`air format .`) and uses the base pipe `|>`.
3.  The test suite runs offline against fixtures under
    `tests/testthat/`; nothing in `R CMD check` downloads data. To
    exercise real data, point the package at a local cache with
    `options(brfssdata.cache_dir = "...")` and pass `download = FALSE`.
4.  Every user-facing change needs a bullet in `NEWS.md`, and changes to
    an exported function need its roxygen comment updated and
    `devtools::document()` rerun.
5.  Before opening a pull request: `devtools::check()` clean (no errors,
    warnings, or notes), spelling clean
    ([`spelling::spell_check_package()`](https://docs.ropensci.org/spelling//reference/spell_check_package.html);
    legitimate words go in `inst/WORDLIST`), and tests for new behavior,
    using snapshot tests for messages, warnings, and errors.

## Changes to the data

The hosted parquet files and catalogs are built by the numbered scripts
in `data-raw/` (see
[`data-raw/README.md`](https://muntasirmasum.github.io/brfssdata/data-raw/README.md))
and published to GitHub releases by the maintainer. Pull requests can
change the build scripts, the label and missing-code rules, or the
crosswalk review file (`data-raw/crosswalk_review.csv`, with the
supporting evidence in `data-raw/crosswalk_evidence.csv`); the
maintainer rebuilds, validates, and republishes. Data are never edited
by hand. The hosted files must remain derivable from CDC’s published SAS
Transport files with only the transformations listed in the README, so a
proposed change that recodes values or drops rows will not be accepted.
