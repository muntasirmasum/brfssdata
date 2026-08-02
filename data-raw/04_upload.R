# Publish built parquet files as GitHub release assets and refresh the
# manifest. Requires a GITHUB_PAT with repo scope (gh auth token works).
# The manifest uploads LAST so a partially published year is never
# advertised to users.

out_dir <- "data-raw/parquet"
repo <- "muntasirmasum/brfssdata"

sha256_file <- function(path) {
  sums <- file.path(paste0(path, ".sha256"))
  writeLines(
    paste0(cli::hash_file_sha256(path), "  ", basename(path)),
    sums
  )
  sums
}

release_exists <- function(tag) {
  # pb_list() does not error for a missing tag, so test tag membership
  # directly; genuine API/auth failures should propagate loudly.
  rel <- piggyback::pb_releases(repo = repo, verbose = FALSE)
  isTRUE(tag %in% rel$tag_name)
}

# pb_upload() only warns on HTTP failure (and only when interactive), so
# verify every upload by listing the release assets afterwards.
upload_verified <- function(path, tag) {
  piggyback::pb_upload(path, repo = repo, tag = tag)
  listed <- piggyback::pb_list(repo = repo, tag = tag)$file_name
  if (!basename(path) %in% listed) {
    stop(
      "upload of ", basename(path), " to ", tag,
      " failed verification; not advertising it",
      call. = FALSE
    )
  }
  invisible(path)
}

publish_year <- function(year) {
  parquet <- file.path(out_dir, sprintf("brfss_%d.parquet", year))
  stopifnot(file.exists(parquet))
  tag <- sprintf("data-%d", year)
  if (!release_exists(tag)) {
    piggyback::pb_release_create(
      repo = repo, tag = tag,
      name = sprintf("BRFSS %d data", year),
      body = sprintf(
        paste0(
          "BRFSS %d public-use data as zstd parquet, derived from CDC's ",
          "SAS Transport release. Verify with the .sha256 file."
        ),
        year
      )
    )
    Sys.sleep(2) # give the release API a moment before uploading
  }
  upload_verified(parquet, tag)
  upload_verified(sha256_file(parquet), tag)
  message("published ", tag)
}

publish_meta <- function(years) {
  tag <- "data-meta"
  if (!release_exists(tag)) {
    piggyback::pb_release_create(
      repo = repo, tag = tag, name = "Data manifest and variable catalog"
    )
    Sys.sleep(2)
  }
  catalog <- file.path(out_dir, "brfss_variables.parquet")
  if (file.exists(catalog)) {
    upload_verified(catalog, tag)
  }
  manifest <- file.path(out_dir, "manifest.json")
  jsonlite::write_json(
    list(
      years = sort(as.integer(years)),
      generated = format(Sys.Date())
    ),
    manifest,
    auto_unbox = TRUE, pretty = TRUE
  )
  upload_verified(manifest, tag)
  message("published manifest: ", paste(range(years), collapse = "-"))
}

# Usage (after 02 and 03 have built everything):
# years <- 2011:2024
# purrr::walk(years, publish_year)
# publish_meta(years)
