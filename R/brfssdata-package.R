#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom rlang %||%
## usethis namespace: end
NULL

# Columns created inside brfss_design() and referenced via srvyr's
# data-masking interface, plus the lazy-loaded package dataset that
# resolve_states() and warn_state_coverage() consult.
utils::globalVariables(c("brfss_psu", "brfss_strata", "brfss_wt", "brfss_states"))
