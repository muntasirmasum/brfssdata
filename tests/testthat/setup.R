# brfss_design() sets survey.lonely.psu when it is unset, by design, so
# running the suite would otherwise leave the option changed in an
# interactive session and make test order matter.
#
# The baseline captured here is the state after this package (and so
# survey, via srvyr) has loaded: survey's .onLoad sets the option to
# "fail". A session that ran the suite therefore ends at "fail" rather
# than unset, exactly as if it had loaded survey directly; that is
# survey's doing, not a suite leak, and it is the value brfss_design()
# treats as unset.
local({
  before <- getOption("survey.lonely.psu")
  withr::defer(options(survey.lonely.psu = before), teardown_env())
})
