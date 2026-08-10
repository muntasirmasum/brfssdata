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
    "fair or poor",
    # The rule-B guards: a "missing ..." flag with no don't-know/refused
    # token must stay substantive, and a word merely starting with the
    # letters must not ride the prefix rule.
    "Missing Fruit Responses",
    "Not Included - Missing Fruit Responses",
    "Included - Not Missing Fruit Responses",
    "No missing fruit responses",
    "Mississippi",
    "Missouri"
  )
  expect_false(any(is_missing_label(labels)))
})

test_that("calculated-variable buckets with trailing nouns match", {
  # The real CDC wordings (acute-apostrophe and mojibake variants
  # included) that the whole-token rule alone rejected, leaving 51,087
  # code-9 rows uncleared in _FRTLT1A 2021 alone under na = TRUE.
  labels <- c(
    "Don´t know, refused or missing values",
    "DonÂ´t know, refused or missing insurance response",
    "Don´t know, refused or missing insurance response",
    "Don´t know, refused or missing work limited",
    "Don´t know, refused or missing usual activities limited",
    "Don´t know, refused or missing social activities limited",
    "Do not know/Refused/Missing (_BMI2 = 9999)",
    # The audited allowlist: CDC's "component question" wordings on the
    # RACE2 family.
    "Do not know/Not sure/Refused component question",
    "Do not know/Not sure/Refused Missing component question"
  )
  expect_true(all(is_missing_label(labels)))
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

test_that("CDC's 1998-2001 abbreviations match", {
  # The older format libraries abbreviate the same answers. Left
  # unmatched, these cover 786 catalog rows over 370 variables, so
  # na = TRUE was leaving don't-know and refused codes (including
  # _DRNKMO 9999 on 117,351 rows of the 1998 file) in the data for
  # years the catalog nominally covers.
  labels <- c(
    "UNK/REF",
    "unk/ref",
    "UNK",
    "REF",
    "UNKNOWN",
    "Unknown",
    "N/A",
    "N/A,REF",
    # The abbreviations compose with the existing tokens and rules.
    "UNK/REF/Missing",
    "Refused or UNK"
  )
  expect_true(all(is_missing_label(labels)))
})

test_that("substantive labels near the abbreviations never match", {
  # "not applicable" spelled out is a scale position in later years
  # (GETHIV code 5, next to "NONE"), so only the bare "N/A" placeholder
  # counts; and the abbreviations stay whole-token like every other
  # rule here.
  labels <- c(
    "Not applicable",
    "NOT APPLICABLE",
    "Not applicable (Blind)",
    "N/A or none",
    "Unknown provider",
    "REFERRED BY DR.",
    "Referred",
    "Other/do not know/refused",
    "02-REFUSED",
    # The three real catalog labels that carry one of the abbreviations
    # as a bare substring. They are the whole reason matching is on
    # whole tokens: "India(n/A)laskan" and "DEPRESSIO(N/A)NXIETY" both
    # contain "n/a", and a substring rule would blank the American
    # Indian race category and the depression answer outright.
    "American Indian/Alaskan Native, Non-Hispanic",
    "DEPRESSION/ANXIETY/EMOTIONAL PROB",
    "IUD, type unknown"
  )
  expect_false(any(is_missing_label(labels)))
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

test_that("a trailing-noun bucket is cleared end to end", {
  local_brfss_cache(
    2023,
    add_cols = list("2023" = list(FRUITVAR = c(1, 2, 9)))
  )
  dat <- read_brfss(2023, vars = "FRUITVAR", quiet = TRUE, na = TRUE)
  expect_false(any(dat$FRUITVAR %in% 9, na.rm = TRUE))
  expect_true(anyNA(dat$FRUITVAR))
  out <- brfss_missing_codes("FRUITVAR", years = 2023)
  expect_identical(out$code, 9L)
})

test_that("an abbreviated missing label is cleared end to end", {
  dir <- local_brfss_cache(2023)
  write_fixture_parquet(
    data.frame(
      year = 2023L,
      variable = "GENHLTH",
      code = c(7L, 9L),
      label = c("UNK", "N/A,REF"),
      complete = TRUE,
      stringsAsFactors = FALSE
    ),
    file.path(dir, "brfss_labels.parquet")
  )
  write_fixture_manifest(dir, 2023)
  dat <- read_brfss(2023, vars = "GENHLTH", quiet = TRUE, na = TRUE)
  expect_false(any(dat$GENHLTH %in% c(7, 9), na.rm = TRUE))
  expect_true(anyNA(dat$GENHLTH))
  out <- brfss_missing_codes("GENHLTH", years = 2023)
  expect_setequal(out$code, c(7L, 9L))
})

test_that("codes at the scientific-notation threshold are cleared", {
  # as.character(1e5) is "1e+05" while as.character(100000L) is
  # "100000", so the old paste()-based match silently skipped any round
  # code at or above 1e5. No such code ships today (777777/999999
  # format fixed); this pins the numeric match against the day one
  # does.
  local_brfss_cache(
    2023,
    add_cols = list("2023" = list(BIGCODE = c(1, 100000)))
  )
  dat <- read_brfss(2023, vars = "BIGCODE", quiet = TRUE, na = TRUE)
  expect_false(any(dat$BIGCODE %in% 100000, na.rm = TRUE))
  expect_true(anyNA(dat$BIGCODE))
})

test_that("labels = TRUE converts codes at the notation threshold", {
  local_brfss_cache(
    2023,
    add_cols = list("2023" = list(BIGCODE = c(1, 100000)))
  )
  dat <- read_brfss(2023, vars = "BIGCODE", quiet = TRUE, labels = TRUE)
  expect_s3_class(dat$BIGCODE, "factor")
  expect_identical(levels(dat$BIGCODE), c("Yes", "Refused"))
  # The 100000 rows must land on "Refused", not NA: integer levels
  # would stringify as "100000" while the double data stringifies as
  # "1e+05".
  expect_false(anyNA(dat$BIGCODE))
})

test_that("na = TRUE warns when years have no catalog at all", {
  # Warning-grade, not a note: na = TRUE was a complete no-op for the
  # year, so estimates still contain CDC's 77/99-style codes.
  local_brfss_cache(1993)
  expect_warning(
    dat <- read_brfss(1993, na = TRUE),
    class = "brfssdata_na_coverage_warning"
  )
  # and the values really do pass through unchanged
  raw <- read_brfss(1993, quiet = TRUE)
  expect_identical(dat$GENHLTH, raw$GENHLTH)
})

test_that("na = TRUE says so when a year's catalog is mostly gaps", {
  # 1998's real catalog covers under a quarter of the file; the fixture
  # mirrors that with one catalogued column (GENHLTH) out of three
  # loaded (GENHLTH, PHYSHLTH, MYSTVAR).
  local_brfss_cache(1998, extra = list("1998" = "MYSTVAR"))
  expect_message(
    read_brfss(1998, na = TRUE),
    class = "brfssdata_na_coverage_note"
  )
})

test_that("the partial-coverage note survives quiet = TRUE", {
  local_brfss_cache(1998, extra = list("1998" = "MYSTVAR"))
  expect_message(
    read_brfss(1998, na = TRUE, quiet = TRUE),
    class = "brfssdata_na_coverage_note"
  )
})

test_that("fully covered years emit no coverage note", {
  local_brfss_cache(2023)
  expect_no_message(
    read_brfss(2023, vars = "GENHLTH", na = TRUE),
    class = "brfssdata_na_coverage_note"
  )
})

test_that("quiet = TRUE does not hide the coverage warning", {
  local_brfss_cache(1993)
  expect_warning(
    read_brfss(1993, quiet = TRUE, na = TRUE),
    class = "brfssdata_na_coverage_warning"
  )
})

test_that("brfss_design() inherits the coverage warning under quiet", {
  local_brfss_cache(1993)
  expect_warning(
    brfss_design(1993, vars = "GENHLTH", quiet = TRUE),
    class = "brfssdata_na_coverage_warning"
  )
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

test_that("a malformed years argument names brfss_missing_codes()", {
  # Validated before the brfss_labels() delegation, so the error is
  # attributed to the function the user called.
  local_brfss_cache(2023)
  err <- expect_error(
    brfss_missing_codes("GENHLTH", years = Inf),
    class = "brfssdata_bad_years_arg"
  )
  expect_match(conditionMessage(err), "years")
})
