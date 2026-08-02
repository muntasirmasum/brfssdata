# Survey-weighted logistic regression with BRFSS

A standard epidemiologic question: how does the probability of reporting
fair or poor general health vary by sex, age group, and education?
Answering it properly with BRFSS requires the complex sampling design,
the final weights, strata, and primary sampling units, or every standard
error will be wrong. This article walks the full path with brfssdata:
one call for a design object, familiar srvyr and survey verbs for the
analysis.

## Data

[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
returns a srvyr design with the era-correct weight applied. Recodes
below work from the numeric codes, the way most epidemiologic BRFSS
analyses do;
[`brfss_labels()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_labels.md)
is the codebook that documents what each code means.

``` r

library(brfssdata)
library(dplyr)
library(srvyr)
library(survey)

des <- brfss_design(
  2023,
  vars = c("GENHLTH", "SEXVAR", "_AGE_G", "EDUCA"),
  quiet = TRUE
)

brfss_labels("EDUCA", years = 2023)
#> # A tibble: 7 × 5
#>    year variable  code label                                            complete
#>   <int> <chr>    <int> <chr>                                            <lgl>   
#> 1  2023 EDUCA        2 Grades 1 through 8 (Elementary)                  TRUE    
#> 2  2023 EDUCA        4 Grade 12 or GED (High school graduate)           TRUE    
#> 3  2023 EDUCA        1 Never attended school or only kindergarten       TRUE    
#> 4  2023 EDUCA        3 Grades 9 through 11 (Some high school)           TRUE    
#> 5  2023 EDUCA        6 College 4 years or more (College graduate)       TRUE    
#> 6  2023 EDUCA        5 College 1 year to 3 years (Some college or tech… TRUE    
#> 7  2023 EDUCA        9 Refused                                          TRUE
```

## Recoding

The outcome is fair or poor self-rated health (codes 4 and 5);
don’t-know (7) and refused (9) become missing. Education collapses to
three levels. Everything here is ordinary dplyr on the design object;
srvyr keeps the design attached.

``` r

des <- des |>
  mutate(
    fairpoor = case_when(
      GENHLTH %in% 4:5 ~ 1,
      GENHLTH %in% 1:3 ~ 0,
      .default = NA
    ),
    sex = factor(SEXVAR, 1:2, c("Male", "Female")),
    edu3 = case_when(
      EDUCA %in% 1:3 ~ "Less than high school",
      EDUCA %in% 4:5 ~ "High school or some college",
      EDUCA == 6 ~ "College graduate",
      .default = NA
    ) |> factor(levels = c(
      "College graduate",
      "High school or some college",
      "Less than high school"
    )),
    age_g = factor(`_AGE_G`, 1:6, c(
      "18-24", "25-34", "35-44", "45-54", "55-64", "65+"
    ))
  )
```

## Weighted prevalence

``` r

des |>
  filter(!is.na(fairpoor)) |>
  group_by(edu3) |>
  summarize(prev = survey_mean(fairpoor, vartype = "ci")) |>
  na.omit()
#> # A tibble: 3 × 4
#>   edu3                          prev prev_low prev_upp
#>   <fct>                        <dbl>    <dbl>    <dbl>
#> 1 College graduate            0.0974   0.0945    0.100
#> 2 High school or some college 0.203    0.199     0.207
#> 3 Less than high school       0.406    0.394     0.418
```

## Model

[`svyglm()`](https://rdrr.io/pkg/survey/man/svyglm.html) accepts the
design object directly. The quasibinomial family is the standard choice
with survey weights.

``` r

fit <- svyglm(
  fairpoor ~ sex + age_g + edu3,
  design = des,
  family = quasibinomial()
)

# Odds ratios with design-based confidence intervals
or <- exp(cbind(OR = coef(fit), confint(fit)))
round(or[-1, ], 2)
#>                                   OR 2.5 % 97.5 %
#> sexFemale                       1.11  1.07   1.15
#> age_g25-34                      1.37  1.25   1.50
#> age_g35-44                      1.59  1.46   1.74
#> age_g45-54                      2.11  1.94   2.30
#> age_g55-64                      2.72  2.50   2.95
#> age_g65+                        2.82  2.61   3.04
#> edu3High school or some college 2.50  2.40   2.60
#> edu3Less than high school       6.78  6.38   7.21
```

The education gradient is the headline: relative to college graduates,
the odds of fair or poor health are substantially higher at lower
education levels, net of sex and age, a pattern consistent across BRFSS
years and one reason self-rated health is a workhorse outcome in health
disparities research.

## Notes for real analyses

- Multi-year designs pool with `brfss_design(2019:2023)`; weights are
  averaged across years and strata become year-by-stratum interactions.
- Requests spanning 2011 fail on purpose; see the getting-started
  vignette for the redesign details.
- `brfss_labels("EDUCA")` documents every code, including the special
  values (9 is Refused here) that should usually become `NA`.
- Cite the data as CDC recommends; see the package README.
