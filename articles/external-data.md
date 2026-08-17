# Merging BRFSS with external data

BRFSS measures individuals, but health behavior is shaped by where
people live. A question like “is fair or poor health more common in
states that expanded Medicaid?” needs two tables, respondent records on
one side and state characteristics on the other, joined on something
they share. In the public-use files that something is `_STATE`, the
state FIPS code carried on every respondent record. It is the bridge to
state policy databases, American Community Survey estimates, other
surveillance systems, and anything else published by state.

`_STATE` is also nearly the only geographic identifier the recent files
carry. A search of the variable catalog for 2023 turns up the FIPS code
and a pair of coarse metropolitan-status flags, nothing finer.

``` r

library(brfssdata)
library(dplyr)
library(srvyr)

brfss_vars("state fips|metropolitan status", years = 2023)
#> # A tibble: 3 × 3
#>   variable label                    years
#>   <chr>    <chr>                    <chr>
#> 1 MSCODE   METROPOLITAN STATUS CODE 2023 
#> 2 _METSTAT METROPOLITAN STATUS      2023 
#> 3 _STATE   STATE FIPS CODE          2023
```

## Building the state lookup from the package

`_STATE` arrives as a number. The label catalog that ships with the data
releases already knows what those numbers mean, so there is no need to
type out a crosswalk or download one.

``` r

brfss_labels("_STATE", years = 2023)
#> # A tibble: 54 × 5
#>     year variable  code label                complete
#>    <int> <chr>    <int> <chr>                <lgl>   
#>  1  2023 _STATE       1 Alabama              TRUE    
#>  2  2023 _STATE       2 Alaska               TRUE    
#>  3  2023 _STATE       4 Arizona              TRUE    
#>  4  2023 _STATE       5 Arkansas             TRUE    
#>  5  2023 _STATE       6 California           TRUE    
#>  6  2023 _STATE       8 Colorado             TRUE    
#>  7  2023 _STATE       9 Connecticut          TRUE    
#>  8  2023 _STATE      10 Delaware             TRUE    
#>  9  2023 _STATE      11 District of Columbia TRUE    
#> 10  2023 _STATE      12 Florida              TRUE    
#> # ℹ 44 more rows
```

The catalog returns one row per code in whatever order the CDC format
library stored them, with the `year`, `variable`, and `complete` columns
that every label query carries. Two columns and a sort give a lookup
table.

``` r

states <- brfss_labels("_STATE", years = 2023) |>
  select(state_fips = code, state_name = label) |>
  arrange(state_fips)

states
#> # A tibble: 54 × 2
#>    state_fips state_name          
#>         <int> <chr>               
#>  1          1 Alabama             
#>  2          2 Alaska              
#>  3          4 Arizona             
#>  4          5 Arkansas            
#>  5          6 California          
#>  6          8 Colorado            
#>  7          9 Connecticut         
#>  8         10 Delaware            
#>  9         11 District of Columbia
#> 10         12 Florida             
#> # ℹ 44 more rows
```

Fifty-four codes appear, covering the fifty states, the District of
Columbia, and three territories. The catalog describes what the CDC
format library defines, not what a particular year contains, so check
the codes against the data before assuming full coverage.

## Attaching Census regions

Base R ships `state.name` and `state.region`, two parallel vectors that
classify the fifty states into Census regions. Pairing them gives a
region table that can be joined on the state name.

``` r

regions <- tibble::tibble(
  state_name = state.name,
  region = as.character(state.region)
)

states <- states |>
  left_join(regions, by = join_by(state_name))
```

The join will not match everything, and the honest first step is to look
at what failed.

``` r

states |>
  filter(is.na(region))
#> # A tibble: 4 × 3
#>   state_fips state_name           region
#>        <int> <chr>                <chr> 
#> 1         11 District of Columbia NA    
#> 2         66 Guam                 NA    
#> 3         72 Puerto Rico          NA    
#> 4         78 Virgin Islands       NA
```

Four codes have no region because `state.name` holds fifty states and
nothing else. The District of Columbia and the territories are in BRFSS
but not in that vector. The Census Bureau places the District of
Columbia in the South Atlantic division of the South region, so it can
be assigned directly; Guam, Puerto Rico, and the Virgin Islands sit
outside the four-region scheme entirely and are better kept as their own
category than forced into one.

``` r

states <- states |>
  mutate(
    region = case_when(
      !is.na(region) ~ region,
      state_name == "District of Columbia" ~ "South",
      .default = "Territory"
    )
  )

states |>
  count(region)
#> # A tibble: 5 × 2
#>   region            n
#>   <chr>         <int>
#> 1 North Central    12
#> 2 Northeast         9
#> 3 South            17
#> 4 Territory         3
#> 5 West             13
```

One quirk to note: `state.region` uses the older label “North Central”
for the region the Census Bureau renamed Midwest in 1984. The twelve
states are the same, only the name is dated.

With every code resolved, the join onto a respondent-level extract is
routine. Setting `relationship = "many-to-one"` makes dplyr check the
assumption that matters, namely that the lookup holds at most one row
per state.

``` r

dat <- read_brfss(2023, vars = c("GENHLTH", "_STATE"), quiet = TRUE) |>
  left_join(
    states,
    by = join_by(`_STATE` == state_fips),
    relationship = "many-to-one"
  )

dat |>
  count(region)
#> # A tibble: 5 × 2
#>   region             n
#>   <chr>          <int>
#> 1 North Central 119119
#> 2 Northeast      78338
#> 3 South         113273
#> 4 Territory       8217
#> 5 West          114376

sum(is.na(dat$region))
#> [1] 0
```

No unmatched respondents, which is the check to run after every merge.
The reverse check is also informative, since a state can be in the
lookup and still contribute no interviews.

``` r

states |>
  filter(!state_fips %in% unique(dat[["_STATE"]]))
#> # A tibble: 2 × 3
#>   state_fips state_name   region   
#>        <int> <chr>        <chr>    
#> 1         21 Kentucky     South    
#> 2         42 Pennsylvania Northeast
```

Kentucky and Pennsylvania have no records in the 2023 file. That is a
property of the survey year, not of the merge, but a regional estimate
that silently drops two states should say so.

## Regional prevalence with the survey design

Prevalence estimates need the design object, not the plain tibble.
[`brfss_design()`](https://muntasirmasum.github.io/brfssdata/reference/brfss_design.md)
returns a srvyr `tbl_svy`, and srvyr implements
[`mutate()`](https://dplyr.tidyverse.org/reference/mutate.html) and
[`filter()`](https://dplyr.tidyverse.org/reference/filter.html) for it
but not the join verbs.

``` r

brfss_design(2023, vars = "_STATE", quiet = TRUE) |>
  left_join(states, by = join_by(`_STATE` == state_fips))
#> Error in `UseMethod()`:
#> ! no applicable method for 'left_join' applied to an object of class "c('tbl_svy', 'survey.design2', 'survey.design')"
```

The workaround is to collapse the joined lookup into a named vector and
index it inside
[`mutate()`](https://dplyr.tidyverse.org/reference/mutate.html). The
design stays intact and the region arrives as one more respondent-level
column.

``` r

region_of <- setNames(states$region, states$state_fips)

des <- brfss_design(2023, vars = c("GENHLTH", "_STATE"), quiet = TRUE) |>
  mutate(
    region = unname(region_of[as.character(`_STATE`)]),
    fairpoor = case_when(
      GENHLTH %in% 4:5 ~ 1,
      GENHLTH %in% 1:3 ~ 0,
      .default = NA
    )
  )

des |>
  filter(!is.na(fairpoor)) |>
  group_by(region) |>
  summarize(
    prev = survey_mean(fairpoor, vartype = "ci"),
    n = unweighted(n())
  )
#> # A tibble: 5 × 5
#>   region         prev prev_low prev_upp      n
#>   <chr>         <dbl>    <dbl>    <dbl>  <int>
#> 1 North Central 0.185    0.181    0.189 118826
#> 2 Northeast     0.165    0.160    0.170  78114
#> 3 South         0.205    0.200    0.211 112879
#> 4 Territory     0.335    0.316    0.353   8198
#> 5 West          0.193    0.187    0.198 114044
```

The gradient runs from the Northeast to the South, with the territories
well above every mainland region. The confidence intervals reflect the
BRFSS sampling design, which the
[`mutate()`](https://dplyr.tidyverse.org/reference/mutate.html) leaves
intact. A merge that dropped back to a plain tibble would have to
rebuild the design before any of these numbers meant anything.

## The general pattern, state by year

State context changes over time, so for anything spanning more than one
survey year the merge key is `_STATE` together with `year`. The external
table needs one row per state-year, and the join names both keys.

The table below is invented for illustration. The values are not real
measures of anything; they exist to show the shape a state-year file
takes.

``` r

# Illustrative only. These numbers are made up.
policy <- tibble::tribble(
  ~state_fips, ~year, ~policy_score,
  6,           2022,  0.42,
  6,           2023,  0.55,
  36,          2022,  0.61,
  36,          2023,  0.64,
  48,          2022,  0.18,
  48,          2023,  0.21
)
```

``` r

pooled <- read_brfss(2022:2023, vars = c("GENHLTH", "_STATE"), quiet = TRUE) |>
  left_join(
    policy,
    by = join_by(`_STATE` == state_fips, year),
    relationship = "many-to-one"
  )

pooled |>
  filter(!is.na(policy_score)) |>
  count(`_STATE`, year, policy_score)
#> # A tibble: 6 × 4
#>   `_STATE`  year policy_score     n
#>      <dbl> <dbl>        <dbl> <int>
#> 1        6  2022         0.42 10952
#> 2        6  2023         0.55 11976
#> 3       36  2022         0.61 17800
#> 4       36  2023         0.64 17349
#> 5       48  2022         0.18 14245
#> 6       48  2023         0.21 10059
```

Because `policy` covers three states, most respondents come back with
`NA`, exactly as a left join should behave. With a real file covering
every state the same code runs unchanged, and
`relationship = "many-to-one"` catches the most common merge bug, a
duplicated state-year row in the external table quietly multiplying
respondent records.

One type mismatch is common. `_STATE` is numeric in BRFSS, while state
FIPS codes elsewhere are often zero-padded character strings such as
`"06"`. Build the padded key explicitly rather than hoping the join
coerces.

``` r

states |>
  mutate(geoid = sprintf("%02d", state_fips)) |>
  slice_head(n = 3)
#> # A tibble: 3 × 4
#>   state_fips state_name region geoid
#>        <int> <chr>      <chr>  <chr>
#> 1          1 Alabama    South  01   
#> 2          2 Alaska     West   02   
#> 3          4 Arizona    West   04
```

## Where to get real state-year data

The American Community Survey is the standard source for state
demographic, economic, and housing characteristics, and the
[tidycensus](https://walker-data.com/tidycensus/) package pulls it
directly into R once you register for a free Census API key. [County
Health Rankings and Roadmaps](https://www.countyhealthrankings.org/)
publishes annual health outcome and health factor measures for states
and counties. [KFF State Health
Facts](https://www.kff.org/state-health-facts/) maintains more than 800
state-level indicators on coverage, Medicaid, spending, and health
status, all downloadable. For policy exposures, the [Correlates of State
Policy
Project](https://ippsr.msu.edu/public-policy/correlates-state-policy)
assembles more than three thousand state-by-year policy variables,
reaching back to the early twentieth century, in a single file with
codebooks.

## Cautions

Recent public-use files carry no county, tract, or ZIP identifier.
Searching the 2023 catalog for one comes back empty, and the
empty-result message points at where the identifiers went: earlier
years.

``` r

brfss_vars("county|census tract|zip", years = 2023)
#> # A tibble: 0 × 3
#> # ℹ 3 variables: variable <chr>, label <chr>, years <chr>
```

Dropping the year restriction lays out that history in full.

``` r

brfss_vars("county|census tract|zip")
#> # A tibble: 5 × 3
#>   variable label                        years    
#>   <chr>    <chr>                        <chr>    
#> 1 CPCOUNTY CELL PHONE PILOT COUNTY NAME 2009-2010
#> 2 CTYCODE  COUNTY CODE                  1988-2010
#> 3 CTYCODE1 COUNTY CODE                  2011-2012
#> 4 ZIPCODE  ZIPCODE OF RESIDENCE         2007     
#> 5 _IMPCTY  IMPUTED COUNTY               2007
```

A county code runs through 2012 and a ZIP code appears in 2007, so the
older files do support a finer merge, though nothing after 2012 does.
Sub-state estimates for recent years come from CDC’s separate SMART city
and county product, which is not part of this package, and every merge
shown above therefore happens at the state level.

Attaching a state characteristic to a respondent record supports
contextual description, not causal inference about place. A state-level
variable joined onto individuals is measured at the wrong level for the
question most people want to ask, since respondents within a state share
that value and are not independent observations of it. Treating the
merged column as an ordinary individual predictor understates the
uncertainty attached to it and encourages reading a state-level
association as though it described individuals. Questions about how
state context shapes individual outcomes belong in a multilevel
framework, with the state as a grouping level and enough states to
estimate variation across them.

The merge also leaves the survey design untouched. Weights, strata, and
primary sampling units are properties of how respondents were sampled,
and adding a column that is constant within state changes none of them.
The design object still describes a respondent-level sample of a state
population, and standard errors from it are design-based standard errors
for respondent-level quantities. If the target of inference is the state
rather than the person, for instance a correlation across fifty state
means, the right approach is to produce weighted state estimates first,
each with its own standard error, and analyze those.
