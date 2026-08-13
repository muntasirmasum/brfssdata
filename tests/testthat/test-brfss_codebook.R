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

# cli wraps at the console width, so a phrase under test can arrive
# split across lines; flatten before matching.
render_card <- function(cb) {
  gsub("\\s+", " ", paste(cli::cli_fmt(print(cb)), collapse = " "))
}

# The variable catalog the codebook joins against, written over the
# fixture one: PHYSHLTH carries the range-format label rows the label
# fixture ships (77/88/99, complete = FALSE), NOFMT has no label rows
# at all in a year the catalog covers, and OLDVAR sits before coverage
# starts.
write_codebook_catalog <- function(dir) {
  write_fixture_parquet(
    data.frame(
      variable = c("PHYSHLTH", "NOFMT", "OLDVAR"),
      label = c(
        "Number of days physical health not good",
        "Continuous measure",
        "An early variable"
      ),
      year = c(2023L, 2023L, 1995L),
      stringsAsFactors = FALSE
    ),
    file.path(dir, "brfss_variables.parquet")
  )
}

test_that("a range format is flagged as incomplete and says so in print", {
  dir <- local_brfss_cache(2023, catalog = TRUE)
  write_codebook_catalog(dir)
  cb <- brfss_codebook("PHYSHLTH", download = FALSE)
  values <- cb$values[[1]]
  expect_setequal(values$code, c(77L, 88L, 99L))
  expect_false(any(values$complete))
  out <- render_card(cb)
  expect_match(out, "Range format")
  expect_match(out, "not listed")
})

test_that("a complete format prints no range footer", {
  local_brfss_cache(2023, catalog = TRUE)
  cb <- brfss_codebook("GENHLTH", download = FALSE)
  expect_true(all(cb$values[[1]]$complete))
  out <- render_card(cb)
  expect_no_match(out, "Range format")
})

test_that("an empty value set inside coverage blames the format", {
  dir <- local_brfss_cache(2023, catalog = TRUE)
  write_codebook_catalog(dir)
  cb <- brfss_codebook("NOFMT", download = FALSE)
  expect_identical(nrow(cb$values[[1]]), 0L)
  out <- render_card(cb)
  expect_match(out, "continuous or range-only")
  # The year is covered, so nothing may imply otherwise.
  expect_no_match(out, "labels cover")
})

test_that("an empty value set outside coverage names the catalog's own start", {
  dir <- local_brfss_cache(2023, catalog = TRUE)
  write_codebook_catalog(dir)
  cb <- brfss_codebook("OLDVAR", download = FALSE)
  out <- render_card(cb)
  # The fixture catalog starts at 2022, so a hard-coded 1998 would show.
  expect_match(out, "labels cover 2022 on")
  expect_no_match(out, "continuous or range-only")
})

test_that("a crosswalk integrity failure aborts instead of dropping family", {
  local_brfss_cache(2023, catalog = TRUE, crosswalk = FALSE)
  local_mocked_bindings(
    download_to_cache = function(url, ...) {
      cli::cli_abort(
        "sha256 mismatch",
        class = c("brfssdata_checksum_error", "brfssdata_download_error")
      )
    }
  )
  expect_error(
    brfss_codebook("GENHLTH"),
    class = "brfssdata_checksum_error"
  )
})

test_that("an unreadable cached crosswalk aborts instead of dropping family", {
  dir <- local_brfss_cache(2023, catalog = TRUE)
  writeLines("not a parquet file", file.path(dir, "brfss_crosswalk.parquet"))
  expect_error(
    brfss_codebook("GENHLTH", download = FALSE),
    class = "brfssdata_corrupt_cache"
  )
})

test_that("an ordinary crosswalk failure says so and still returns a card", {
  local_brfss_cache(2023, catalog = TRUE, crosswalk = FALSE)
  local_mocked_bindings(
    download_to_cache = function(url, ...) {
      stop("network is down")
    }
  )
  expect_message(
    cb <- brfss_codebook("GENHLTH"),
    class = "brfssdata_manifest_note"
  )
  expect_true(is.na(cb$concept))
  expect_identical(cb$related[[1]], character(0))
})

test_that("malformed years are rejected with the years class", {
  # Inf used to slip past the trunc guard, empty the catalog, and then
  # blame the variable with a misleading brfssdata_bad_var.
  local_brfss_cache(2023)
  expect_error(
    brfss_codebook("GENHLTH", years = "recent"),
    class = "brfssdata_bad_years_arg"
  )
  expect_error(
    brfss_codebook("GENHLTH", years = 2023.5),
    class = "brfssdata_bad_years_arg"
  )
  expect_error(
    brfss_codebook("GENHLTH", years = Inf),
    class = "brfssdata_bad_years_arg"
  )
})

test_that("a year-shaped vars argument gets the years hint", {
  err <- expect_error(brfss_codebook(2023), class = "brfssdata_bad_vars_arg")
  expect_match(conditionMessage(err), "years = ")
  err <- expect_error(brfss_codebook(1:2), class = "brfssdata_bad_vars_arg")
  expect_no_match(conditionMessage(err), "years = ")
  err <- expect_error(brfss_codebook(), class = "brfssdata_bad_vars_arg")
  expect_no_match(conditionMessage(err), "years = ")
})

test_that("printing caps the cards and points at n = Inf", {
  local_brfss_cache(2023, catalog = TRUE)
  cb <- brfss_codebook(c("GENHLTH", "SMOKE100"), download = FALSE)
  capped <- gsub(
    "\\s+",
    " ",
    paste(cli::cli_fmt(print(cb, n = 1)), collapse = " ")
  )
  expect_match(capped, "GENHLTH")
  expect_no_match(capped, "SMOKE100")
  expect_match(capped, "1 more variable")
  expect_match(capped, "n = Inf")

  full <- gsub(
    "\\s+",
    " ",
    paste(cli::cli_fmt(print(cb, n = Inf)), collapse = " ")
  )
  expect_match(full, "GENHLTH")
  expect_match(full, "SMOKE100")
  expect_no_match(full, "more variable")

  # Under the cap there is no footer at all.
  default <- gsub(
    "\\s+",
    " ",
    paste(cli::cli_fmt(print(cb)), collapse = " ")
  )
  expect_match(default, "SMOKE100")
  expect_no_match(default, "more variable")

  expect_error(print(cb, n = 0), class = "brfssdata_bad_n_arg")
  expect_error(print(cb, n = "all"), class = "brfssdata_bad_n_arg")
})
