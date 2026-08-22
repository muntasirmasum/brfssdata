# Record upstream provenance for the downloaded CDC source files into
# data-raw/provenance.csv, one row per annual zip in data-raw/raw/. The
# CSV is committed (the zips are not), so the manifest and the year
# inventory can tie every published parquet back to the CDC file that
# produced it. Run from the package root after 01_download.R, and again
# whenever a year's zip is re-downloaded.
#
# Re-runs are additive: a zip whose sha256 already matches its recorded
# row keeps that row untouched, preserving the recorded download date
# and any hand-curated cdc_release label. A new or changed zip gets a
# fresh row with the file's mtime as the download date and an empty
# cdc_release, to be filled by hand when CDC's annual-data page names a
# revision ("data updated ..." notes and the like).

source("data-raw/01_download.R") # for brfss_zip_url(); downloads only run
# from that script's commented usage block, so sourcing is inert.

prov_path <- "data-raw/provenance.csv"

zips <- list.files(raw_dir, pattern = "^brfss_[0-9]{4}\\.zip$", full.names = TRUE)
stopifnot(length(zips) > 0)

existing <- if (file.exists(prov_path)) {
  utils::read.csv(prov_path, colClasses = "character")
} else {
  NULL
}

rows <- lapply(zips, function(path) {
  year <- as.integer(sub("^brfss_([0-9]{4})\\.zip$", "\\1", basename(path)))
  sha <- cli::hash_file_sha256(path)
  old <- existing[existing$year == as.character(year), , drop = FALSE]
  if (nrow(old) == 1 && identical(old$source_sha256, sha)) {
    return(old)
  }
  url <- brfss_zip_url(year)
  data.frame(
    year = as.character(year),
    source_file = basename(url),
    source_url = url,
    source_sha256 = sha,
    source_size = as.character(file.size(path)),
    downloaded = format(as.Date(file.mtime(path))),
    cdc_release = "",
    stringsAsFactors = FALSE
  )
})
prov <- do.call(rbind, rows)
prov <- prov[order(as.integer(prov$year)), ]

utils::write.csv(prov, prov_path, row.names = FALSE)
message("wrote ", prov_path, ": ", nrow(prov), " years")
