# srvyr's estimation verbs, re-exported.
#
# brfss_design() hands back an srvyr design, and srvyr's S3 methods
# dispatch from its loaded-but-unattached namespace, so a session with
# only brfssdata and dplyr attached builds a design and groups it
# successfully, then dies inside summarize() with a bare "could not find
# function survey_prop" and a backtrace that never names srvyr. Because
# everything upstream worked, that reads as a typo or a broken install.
# These are exactly the verbs the README and the articles use, so the
# documented workflow runs as written; srvyr is already an Imports
# dependency, so nothing new is depended on.

#' @importFrom srvyr survey_mean
#' @export
srvyr::survey_mean

#' @importFrom srvyr survey_prop
#' @export
srvyr::survey_prop

#' @importFrom srvyr survey_total
#' @export
srvyr::survey_total

#' @importFrom srvyr unweighted
#' @export
srvyr::unweighted

#' @importFrom srvyr as_survey_design
#' @export
srvyr::as_survey_design
