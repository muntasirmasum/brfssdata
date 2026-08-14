#' Options that change how brfssdata behaves
#'
#' @description
#' Every session option the package reads, in one place. Set any of
#' them with [options()], typically in a project `.Rprofile`; none is
#' required for normal use.
#'
#' @section Options:
#' \describe{
#'   \item{`brfssdata.cache_dir`}{Path used for the local data cache
#'     instead of the [tools::R_user_dir()] default. Point it at a
#'     shared or project-local directory to reuse one set of downloads
#'     across machines or projects; a lab or an HPC cluster needs only
#'     one populated copy on a shared filesystem, with every user's
#'     option pointing at it. See [brfss_cache_dir()] and the *Getting
#'     started* vignette's offline recipe.}
#'   \item{`brfssdata.lonely_psu`}{A single string copied into
#'     `options(survey.lonely.psu = ...)` when [brfss_design()] detects
#'     single-PSU strata, replacing the package's default `"adjust"`.
#'     See the *Survey design* article for what the settings mean.}
#'   \item{`brfssdata.module_weight_check`}{Set to `FALSE` to disable
#'     the optional-module weight diagnostic that [brfss_design()] runs
#'     when `vars` is supplied (the
#'     `brfssdata_module_weight_warning` signal).}
#'   \item{`brfssdata.repo`}{Advanced. The GitHub repository
#'     (`"owner/name"`) whose releases host the data, for forks that
#'     publish their own builds or air-gapped mirrors. Checksums still
#'     come from that repository's manifest, so pointing here at a repo
#'     you do not trust extends your trust to its data. Not needed for
#'     normal use.}
#' }
#'
#' The package also *writes* one option while working:
#' [brfss_design()] sets `options(survey.lonely.psu)` for the session
#' (announced once via `brfssdata_lonely_psu_note`), and downloads
#' temporarily raise `options(timeout)` to at least an hour. Downloads
#' through the preferred curl backend additionally abort if a
#' connection takes over a minute to establish or a transfer sits below
#' 100 bytes/s for five minutes, so a dead proxy fails with an error
#' instead of hanging.
#'
#' @seealso [brfssdata-conditions] for the condition classes that
#'   control console output, [brfss_cache_dir()] for cache management.
#' @name brfssdata-options
NULL
