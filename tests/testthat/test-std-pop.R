# The 2000 projected standard population, and the row-order contract
# the age-adjustment recipe depends on: survey::svystandardize() matches
# its `population` argument to the levels of `by` by position, so a
# reordered adult6 set would standardize to the wrong weights silently.

test_that("the adult6 set is six rows in _AGE_G code order", {
  adult6 <- brfss_std_pop_2000[brfss_std_pop_2000$set == "adult6", ]

  expect_identical(nrow(adult6), 6L)
  expect_identical(
    adult6$age_group,
    c("18-24", "25-34", "35-44", "45-54", "55-64", "65+")
  )
  expect_identical(adult6$age_min, c(18L, 25L, 35L, 45L, 55L, 65L))
  expect_true(all(diff(adult6$age_min) > 0))
})

test_that("the adult6 top group is open-ended and the weights sum to 1", {
  adult6 <- brfss_std_pop_2000[brfss_std_pop_2000$set == "adult6", ]

  expect_identical(adult6$age_max[6], NA_integer_)
  expect_false(anyNA(adult6$age_max[1:5]))
  expect_equal(sum(adult6$std_weight), 1)
  expect_equal(adult6$std_weight, adult6$std_pop / sum(adult6$std_pop))
})

test_that("the age19 set is 19 rows in ascending age order, summing to 1", {
  age19 <- brfss_std_pop_2000[brfss_std_pop_2000$set == "age19", ]

  expect_identical(nrow(age19), 19L)
  expect_true(all(diff(age19$age_min) > 0))
  expect_identical(age19$age_max[19], NA_integer_)
  expect_equal(sum(age19$std_weight), 1)
})

test_that("adult6 collapses onto the published age-adjustment groups", {
  # adult6 is the 2000 standard cut to _AGE_G, a finer partition than
  # anything published: Klein & Schoenborn's distribution #9 combines
  # 45-64, and CDC's BRFSS age-adjustment guide uses three groups. The
  # data documentation tells readers to sum rows to reproduce either,
  # so the sums are pinned here.
  adult6 <- brfss_std_pop_2000[brfss_std_pop_2000$set == "adult6", ]
  w <- stats::setNames(adult6$std_weight, adult6$age_group)

  # Tolerance is the published tables' own rounding, not slack: SEER's
  # single-age rendering aggregates to within about 2e-6 of them.
  expect_equal(unname(w[["45-54"]] + w[["55-64"]]), 0.299194, tolerance = 1e-4)
  expect_equal(
    unname(w[["18-24"]] + w[["25-34"]] + w[["35-44"]]),
    0.530535,
    tolerance = 1e-4
  )
  expect_equal(unname(w[["65+"]]), 0.170271, tolerance = 1e-4)
  expect_equal(unname(w[["18-24"]]), 0.128810, tolerance = 1e-4)
})
