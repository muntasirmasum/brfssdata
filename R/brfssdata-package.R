#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom rlang %||%
## usethis namespace: end
NULL

# Columns created inside brfss_design() and referenced via srvyr's
# data-masking interface.
utils::globalVariables(c("brfss_psu", "brfss_strata", "brfss_wt"))
