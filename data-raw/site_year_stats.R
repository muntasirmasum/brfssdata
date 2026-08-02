# Per-year statistics for the "The datasets" pkgdown article.
# Reads only the parquet footers of the hosted release assets (via the
# DuckDB httpfs extension), plus the variable catalog, and writes
# vignettes/articles/brfss_year_stats.csv. Re-run after publishing new
# data years.

library(brfssdata)

years <- brfss_years()

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "INSTALL httpfs; LOAD httpfs;")

stats <- lapply(years, function(year) {
  url <- sprintf(
    "https://github.com/muntasirmasum/brfssdata/releases/download/data-%d/brfss_%d.parquet",
    year,
    year
  )
  meta <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT any_value(num_rows) AS rows,
              any_value(footer_size) AS footer
       FROM parquet_file_metadata('%s')",
      url
    )
  )
  cols <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT count(*) AS n FROM parquet_schema('%s')
       WHERE num_children IS NULL OR num_children = 0",
      url
    )
  )
  cat(sprintf("%d: %d rows\n", year, meta$rows))
  data.frame(year = year, respondents = meta$rows, variables = cols$n)
})
stats <- do.call(rbind, stats)

# Asset sizes from the GitHub API (no download).
sizes <- vapply(
  years,
  function(year) {
    out <- system2(
      "gh",
      c(
        "api",
        sprintf("repos/muntasirmasum/brfssdata/releases/tags/data-%d", year),
        "--jq",
        shQuote(sprintf(
          '.assets[] | select(.name == "brfss_%d.parquet") | .size',
          year
        ))
      ),
      stdout = TRUE
    )
    as.numeric(out[[1]])
  },
  numeric(1)
)
stats$size_mb <- round(sizes / 1024^2, 1)

write.csv(
  stats,
  file.path("vignettes", "articles", "brfss_year_stats.csv"),
  row.names = FALSE
)
