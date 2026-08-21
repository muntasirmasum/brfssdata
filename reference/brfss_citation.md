# Citations for the package and the survey years an analysis used

Returns ready-to-use
[`utils::bibentry()`](https://rdrr.io/r/utils/bibentry.html) citations:
CDC's recommended citation for each requested survey year's data, plus
the package citation. Print the result for formatted text, or use
[`toBibtex()`](https://rdrr.io/r/utils/toLatex.html) on it for a `.bib`
file. Entirely offline; the years are validated against the cached or
bundled manifest.

## Usage

``` r
brfss_citation(years = NULL)
```

## Arguments

- years:

  Optional integer vector of one or more survey years to cite. `NULL`
  cites the collection's span as a single entry.

## Value

A [`utils::bibentry()`](https://rdrr.io/r/utils/bibentry.html) vector:
one entry per requested year (or one spanning entry when
`years = NULL`), then the package entry. Every entry carries a BibTeX
key, `brfssdata` for the package, `brfss` for the spanning data entry,
and `brfss2023` and the like for each requested year, so
[`toBibtex()`](https://rdrr.io/r/utils/toLatex.html) output drops into a
`.bib` file unedited.

## Examples

``` r
brfss_citation(2023)
#> Centers for Disease Control and Prevention (CDC) (2023). “Behavioral
#> Risk Factor Surveillance System Survey Data, 2023.”
#> <https://www.cdc.gov/brfss/>.
#> 
#> Masum M (2026). _brfssdata: Access CDC Behavioral Risk Factor
#> Surveillance System Data_. doi:10.32614/CRAN.package.brfssdata
#> <https://doi.org/10.32614/CRAN.package.brfssdata>. R package version
#> 0.1.0, <https://muntasirmasum.github.io/brfssdata/>.
toBibtex(brfss_citation(2022:2023))
#> @Misc{brfss2022,
#>   title = {Behavioral Risk Factor Surveillance System Survey Data, 2022},
#>   author = {{Centers for Disease Control and Prevention (CDC)}},
#>   year = {2022},
#>   publisher = {U.S. Department of Health and Human Services, Centers for Disease Control and Prevention},
#>   address = {Atlanta, Georgia},
#>   url = {https://www.cdc.gov/brfss/},
#> }
#> 
#> @Misc{brfss2023,
#>   title = {Behavioral Risk Factor Surveillance System Survey Data, 2023},
#>   author = {{Centers for Disease Control and Prevention (CDC)}},
#>   year = {2023},
#>   publisher = {U.S. Department of Health and Human Services, Centers for Disease Control and Prevention},
#>   address = {Atlanta, Georgia},
#>   url = {https://www.cdc.gov/brfss/},
#> }
#> 
#> @Manual{brfssdata,
#>   title = {{brfssdata}: Access CDC Behavioral Risk Factor Surveillance System Data},
#>   author = {Muntasir Masum},
#>   year = {2026},
#>   note = {R package version 0.1.0},
#>   doi = {10.32614/CRAN.package.brfssdata},
#>   url = {https://muntasirmasum.github.io/brfssdata/},
#> }
```
