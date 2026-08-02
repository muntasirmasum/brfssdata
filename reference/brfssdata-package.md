# brfssdata: Access CDC Behavioral Risk Factor Surveillance System Data

Download, cache, and analyze annual microdata from the United States
Centers for Disease Control and Prevention Behavioral Risk Factor
Surveillance System (BRFSS) <https://www.cdc.gov/brfss/>. Survey years
are stored as compact files hosted on public releases and queried lazily
with 'DuckDB' (via the 'duckdb' package), so only the requested years
and variables are transferred. Survey-design helpers construct 'srvyr'
design objects with year-appropriate weights, strata, and primary
sampling units, including explicit handling of the 2011 weighting
methodology change.

## See also

Useful links:

- <https://muntasirmasum.github.io/brfssdata/>

- <https://github.com/muntasirmasum/brfssdata>

- Report bugs at <https://github.com/muntasirmasum/brfssdata/issues>

## Author

**Maintainer**: Muntasir Masum <muntasir.1124@gmail.com>
([ORCID](https://orcid.org/0000-0002-4210-2844)) \[copyright holder\]

Authors:

- Muntasir Masum <muntasir.1124@gmail.com>
  ([ORCID](https://orcid.org/0000-0002-4210-2844)) \[copyright holder\]
