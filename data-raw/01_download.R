# Download CDC BRFSS annual XPT zips into data-raw/raw/.
# Run from the package root. See data-raw/README.md for the Akamai caveat.

raw_dir <- "data-raw/raw"
dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)

# CDC URL for a survey year's XPT zip, by era.
brfss_zip_url <- function(year) {
  base <- sprintf("https://www.cdc.gov/brfss/annual_data/%d/files", year)
  yy <- sprintf("%02d", year %% 100)
  if (year >= 2011) {
    # Extension case varies by year on CDC's pages: .ZIP for 2011-2013.
    ext <- if (year <= 2013) "ZIP" else "zip"
    sprintf("%s/LLCP%dXPT.%s", base, year, ext)
  } else if (year >= 1990) {
    sprintf("%s/CDBRFS%sXPT.zip", base, yy)
  } else {
    # 1984-1989: not on CDC's current index; pattern from lodown's catalog.
    sprintf("%s/CDBRFS%s_XPT.zip", base, yy)
  }
}

# Browser-like headers; Akamai 403s default curl/R user agents.
browser_handle <- function() {
  h <- curl::new_handle(followlocation = TRUE, timeout = 3600)
  curl::handle_setheaders(
    h,
    "User-Agent" = paste0(
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ",
      "AppleWebKit/537.36 (KHTML, like Gecko) ",
      "Chrome/126.0.0.0 Safari/537.36"
    ),
    "Accept" = "*/*",
    "Accept-Language" = "en-US,en;q=0.9",
    "Referer" = "https://www.cdc.gov/brfss/annual_data/annual_data.htm"
  )
  h
}

download_year <- function(year, overwrite = FALSE) {
  dest <- file.path(raw_dir, sprintf("brfss_%d.zip", year))
  if (file.exists(dest) && !overwrite) {
    message(year, ": already downloaded")
    return(invisible(dest))
  }
  # CDC's pages are inconsistent about extension case; try both.
  url <- brfss_zip_url(year)
  urls <- unique(c(
    url,
    sub("\\.zip$", ".ZIP", url),
    sub("\\.ZIP$", ".zip", url)
  ))
  for (u in urls) {
    message(year, ": ", u)
    status <- tryCatch(
      {
        curl::curl_download(u, dest, handle = browser_handle(), quiet = FALSE)
        "ok"
      },
      error = function(e) conditionMessage(e)
    )
    if (identical(status, "ok")) {
      return(invisible(dest))
    }
    unlink(dest)
  }
  warning(year, " failed on all URL variants: ", status, call. = FALSE)
  invisible(NULL)
}

# Usage:
# purrr::walk(2011:2024, download_year)   # LLCP era
# purrr::walk(1990:2010, download_year)   # CDBRFS era
# purrr::walk(1984:1989, download_year)   # probe; may 404/403
