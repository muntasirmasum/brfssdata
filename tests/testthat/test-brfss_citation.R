# brfss_citation(): offline bibentry generation.

test_that("brfss_citation returns per-year CDC entries plus the package", {
  local_brfss_cache(c(2022, 2023))
  cit <- brfss_citation(2022:2023)
  expect_s3_class(cit, "bibentry")
  expect_length(cit, 3L)
  txt <- format(cit, style = "text")
  expect_true(any(grepl("2022", txt)))
  expect_true(any(grepl("2023", txt)))
  expect_true(any(grepl("brfssdata", txt)))
  # and it renders to BibTeX
  expect_true(any(grepl("^@", format(toBibtex(cit)))))
})

test_that("years = NULL cites the collection span", {
  local_brfss_cache(c(2022, 2023))
  cit <- brfss_citation()
  expect_length(cit, 2L)
  expect_true(any(grepl("2022-2023", format(cit, style = "text"))))
})

test_that("unpublished years and malformed input are rejected", {
  local_brfss_cache(2023)
  expect_error(brfss_citation(1888), class = "brfssdata_bad_year")
  expect_error(brfss_citation("now"), class = "brfssdata_bad_years_arg")
})
