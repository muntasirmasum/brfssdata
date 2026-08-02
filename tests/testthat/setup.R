# brfss_design() sets survey.lonely.psu when it is unset, by design, so
# running the suite would otherwise leave the option changed in an
# interactive session and make test order matter.
local({
  before <- getOption("survey.lonely.psu")
  withr::defer(options(survey.lonely.psu = before), teardown_env())
})
