# The per-variable codebook card: catalog joins, missing flags, family
# membership, and the print method.

test_that("a codebook card joins label, values, and missing codes", {
  local_brfss_cache(2023, catalog = TRUE)
  cb <- brfss_codebook("GENHLTH", download = FALSE)
  expect_s3_class(cb, "brfss_codebook")
  expect_identical(cb$variable, "GENHLTH")
  values <- cb$values[[1]]
  expect_true(all(c(1, 7, 9) %in% values$code))
  expect_true(all(values$missing[values$code %in% c(7, 9)]))
  expect_false(any(values$missing[values$code %in% 1:5]))
  missing <- cb$missing_codes[[1]]
  expect_setequal(missing$code, c(7L, 9L))
})

test_that("vars is required and matched case-insensitively", {
  local_brfss_cache(2023, catalog = TRUE)
  expect_error(brfss_codebook(), class = "brfssdata_bad_vars_arg")
  expect_error(brfss_codebook(1:2), class = "brfssdata_bad_vars_arg")
  cb <- brfss_codebook("genhlth", download = FALSE)
  expect_identical(cb$variable, "GENHLTH")
  expect_error(
    brfss_codebook("NOPE_NOT_REAL", download = FALSE),
    class = "brfssdata_bad_var"
  )
})

test_that("family membership comes from the crosswalk", {
  dir <- local_brfss_cache(2023, catalog = TRUE)
  # Put OLDGEN in the variable catalog so the codebook can find it.
  write_fixture_parquet(
    data.frame(
      variable = c("OLDGEN", "NEWGEN"),
      label = c("Old generation", "New generation"),
      year = c(2022L, 2023L),
      stringsAsFactors = FALSE
    ),
    file.path(dir, "brfss_variables.parquet")
  )
  cb <- brfss_codebook("OLDGEN", download = FALSE)
  expect_identical(cb$concept, "mixgen")
  expect_identical(cb$related[[1]], "NEWGEN")
})

test_that("the print method renders a card", {
  local_brfss_cache(2023, catalog = TRUE)
  cb <- brfss_codebook("GENHLTH", download = FALSE)
  out <- cli::cli_fmt(print(cb))
  expect_match(paste(out, collapse = "\n"), "GENHLTH")
  expect_match(paste(out, collapse = "\n"), "missing-type")
})
