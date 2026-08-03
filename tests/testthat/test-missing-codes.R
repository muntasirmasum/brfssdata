# The na argument and the missing-code matcher. The matcher rules are
# what stand between "denominator includes Don't know/Refused" and an
# accurate default estimate, so both directions get direct unit tests:
# every observed CDC spelling must match, every substantive answer that
# merely contains one of the words must not.

test_that("na = TRUE sets DK and Refused codes to NA on the numeric path", {
  local_brfss_cache(2023)
  raw <- read_brfss(2023, quiet = TRUE)
  dat <- read_brfss(2023, quiet = TRUE, na = TRUE)
  expect_true(any(raw$GENHLTH %in% c(7, 9)))
  expect_false(any(dat$GENHLTH %in% c(7, 9), na.rm = TRUE))
  expect_true(all(is.na(dat$GENHLTH[raw$GENHLTH %in% c(7, 9)])))
  # 77 and 99 are catalogued missing codes for PHYSHLTH; 88 is "None",
  # an answer of zero, and must survive.
  expect_false(any(dat$PHYSHLTH %in% c(77, 99), na.rm = TRUE))
  expect_true(any(dat$PHYSHLTH %in% 88, na.rm = TRUE))
})

test_that("read_brfss leaves codes alone by default", {
  local_brfss_cache(2023)
  dat <- read_brfss(2023, quiet = TRUE)
  expect_true(any(dat$GENHLTH %in% c(7, 9)))
})

test_that("na = TRUE drops DK and Refused levels on the labeled path", {
  local_brfss_cache(2023)
  dat <- read_brfss(
    2023,
    vars = "GENHLTH",
    quiet = TRUE,
    labels = TRUE,
    na = TRUE
  )
  expect_identical(
    levels(dat$GENHLTH),
    c("Excellent", "Very good", "Good", "Fair", "Poor")
  )
  expect_true(anyNA(dat$GENHLTH))
})

test_that("substantive labels containing the keywords never match", {
  labels <- c(
    "Doctor refused when asked",
    "No, I’ve refused treatment",
    "INSURANCE COMPANY REFUSED COVERAGE",
    "DON'T KNOW WHERE TO GO",
    "zero or missing",
    "No missing values and in accepted range",
    "Multiracial but preferred race not asked",
    "None",
    "fair or poor"
  )
  expect_false(any(is_missing_label(labels)))
})

test_that("every observed spelling of the missing-type labels matches", {
  labels <- c(
    "Don’t know/Not Sure",
    "Don´t Know",
    "DonÂ´t Know",
    "Don't know/Not sure",
    "Dont know/Not Sure",
    "Do not know",
    "DK/NS",
    "REFUSED",
    "Refused",
    "Not asked or Missing",
    "Don’t know/Not Sure Or Refused/Missing",
    "BLANK/Not asked"
  )
  expect_true(all(is_missing_label(labels)))
  expect_false(is_missing_label(NA_character_))
})

test_that("the na step never touches excluded identifier columns", {
  dir <- local_brfss_cache(2023)
  # A hostile catalog labeling an observed _STATE code as "Refused":
  # without the exclusion, na = TRUE would blank out a state.
  write_fixture_parquet(
    data.frame(
      year = 2023L,
      variable = c("_STATE", "GENHLTH", "GENHLTH"),
      code = c(1L, 7L, 9L),
      label = c("Refused", "Dont know/Not Sure", "Refused"),
      complete = TRUE,
      stringsAsFactors = FALSE
    ),
    file.path(dir, "brfss_labels.parquet")
  )
  write_fixture_manifest(dir, 2023)
  dat <- read_brfss(2023, quiet = TRUE, na = TRUE)
  expect_false(anyNA(dat$`_STATE`))
  expect_false(any(dat$GENHLTH %in% c(7, 9), na.rm = TRUE))
})

test_that("the design path's na step never touches identifier columns", {
  # The design route builds its own exclusion list, and na = TRUE is the
  # default there; mutation-verified as a separate surface from the
  # read-path test above.
  dir <- local_brfss_cache(2023)
  write_fixture_parquet(
    data.frame(
      year = 2023L,
      variable = c("_STATE", "GENHLTH", "GENHLTH"),
      code = c(1L, 7L, 9L),
      label = c("Refused", "Dont know/Not Sure", "Refused"),
      complete = TRUE,
      stringsAsFactors = FALSE
    ),
    file.path(dir, "brfss_labels.parquet")
  )
  write_fixture_manifest(dir, 2023)
  des <- brfss_design(2023, quiet = TRUE)
  expect_false(anyNA(des$variables$`_STATE`))
  expect_false(any(des$variables$GENHLTH %in% c(7, 9), na.rm = TRUE))
})

test_that("codes are cleared only in years whose label matched", {
  local_brfss_cache(c(2022, 2023))
  dat <- read_brfss(2022:2023, quiet = TRUE, na = TRUE)
  # The fixture catalogs PHYSHLTH 77 for 2023 only.
  expect_false(any(dat$PHYSHLTH[dat$year == 2023] %in% 77, na.rm = TRUE))
  expect_true(any(dat$PHYSHLTH[dat$year == 2022] %in% 77, na.rm = TRUE))
})

test_that("brfss_missing_codes reports exactly what na = TRUE clears", {
  local_brfss_cache(2023)
  out <- brfss_missing_codes(years = 2023)
  expect_true(all(c("GENHLTH", "PHYSHLTH") %in% out$variable))
  expect_setequal(out$code[out$variable == "GENHLTH"], c(7L, 9L))
  expect_false(88 %in% out$code[out$variable == "PHYSHLTH"])
  expect_false("TRAPVAR" %in% out$variable)
})

test_that("the na note reports counts and the audit trail", {
  local_brfss_cache(2023)
  expect_message(
    read_brfss(2023, quiet = FALSE, na = TRUE),
    class = "brfssdata_na_note"
  )
})

test_that("brfss_design clears missing codes by default; read does not", {
  local_brfss_cache(2023)
  des <- brfss_design(2023, vars = "GENHLTH", quiet = TRUE)
  expect_false(any(des$variables$GENHLTH %in% c(7, 9), na.rm = TRUE))
  raw <- brfss_design(2023, vars = "GENHLTH", quiet = TRUE, na = FALSE)
  expect_true(any(raw$variables$GENHLTH %in% c(7, 9)))
  expect_identical(formals(read_brfss)$na, FALSE)
  expect_identical(formals(brfss_design)$na, TRUE)
})

test_that("a malformed na argument is rejected", {
  local_brfss_cache(2023)
  expect_error(
    read_brfss(2023, quiet = TRUE, na = "yes"),
    class = "brfssdata_bad_na_arg"
  )
  expect_error(
    brfss_design(2023, quiet = TRUE, na = NA),
    class = "brfssdata_bad_na_arg"
  )
})
