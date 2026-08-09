# brfss_citation(): offline bibentry generation.

bib_keys <- function(cit) {
  vapply(
    unclass(cit),
    function(e) attr(e, "key") %||% NA_character_,
    character(1),
    USE.NAMES = FALSE
  )
}

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

test_that("every entry carries a BibTeX key, so the .bib compiles", {
  local_brfss_cache(c(2022, 2023))
  cit <- brfss_citation(2022:2023)
  expect_setequal(bib_keys(cit), c("brfss2022", "brfss2023", "brfssdata"))
  # An empty key renders as "@Misc{," and makes the file uncompilable.
  bib <- format(toBibtex(cit))
  expect_false(any(grepl("^@[A-Za-z]+\\{,", bib)))
  expect_true(any(grepl("^@Misc\\{brfss2023,", bib)))
  expect_true(any(grepl("^@Manual\\{brfssdata,", bib)))
})

test_that("years = NULL cites the collection span", {
  local_brfss_cache(c(2022, 2023))
  cit <- brfss_citation()
  expect_length(cit, 2L)
  expect_true(any(grepl("2022-2023", format(cit, style = "text"))))
  expect_setequal(bib_keys(cit), c("brfss", "brfssdata"))
  expect_false(any(grepl("^@[A-Za-z]+\\{,", format(toBibtex(cit)))))
})

test_that("unpublished years and malformed input are rejected", {
  local_brfss_cache(2023)
  expect_error(brfss_citation(1888), class = "brfssdata_bad_year")
  expect_error(brfss_citation("now"), class = "brfssdata_bad_years_arg")
  expect_error(brfss_citation(NA_integer_), class = "brfssdata_bad_years_arg")
  expect_error(brfss_citation(2023.5), class = "brfssdata_bad_years_arg")
  # A zero-length request used to slip through and return a bare list.
  expect_error(brfss_citation(integer(0)), class = "brfssdata_bad_years_arg")
})
