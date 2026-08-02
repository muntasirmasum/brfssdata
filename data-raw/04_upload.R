# Publish built parquet files as GitHub release assets and refresh the
# manifest. Requires a GITHUB_PAT with repo scope (gh auth token works).
# The manifest uploads LAST so a partially published year is never
# advertised to users.

out_dir <- "data-raw/parquet"
repo <- "muntasirmasum/brfssdata"

# piggyback memoizes GitHub API reads for 10 minutes by default, which
# makes releases created moments ago invisible to the upload step.
Sys.setenv("piggyback_cache_duration" = "1")

sha256_file <- function(path) {
  sums <- file.path(paste0(path, ".sha256"))
  writeLines(
    paste0(cli::hash_file_sha256(path), "  ", basename(path)),
    sums
  )
  sums
}

release_info <- function(tag) {
  # A 404 means the release does not exist yet; anything else (auth,
  # rate limit) should propagate loudly.
  tryCatch(
    gh::gh(paste0("GET /repos/", repo, "/releases/tags/", tag)),
    http_error_404 = function(e) NULL
  )
}

release_exists <- function(tag) {
  !is.null(release_info(tag))
}

release_assets <- function(tag) {
  rel <- release_info(tag)
  if (is.null(rel) || length(rel$assets) == 0) {
    return(character(0))
  }
  vapply(rel$assets, function(a) a$name, character(1))
}

# Uploads go through the gh CLI: piggyback 0.1.5 memoizes its release
# listings so aggressively that releases created moments earlier are
# invisible to pb_upload. Verification reads the GitHub API directly.
# Assets already present are not re-uploaded.
upload_verified <- function(path, tag) {
  if (!basename(path) %in% release_assets(tag)) {
    status <- system2(
      "gh",
      c("release", "upload", tag, path, "--repo", repo, "--clobber")
    )
    if (status != 0) {
      stop("gh release upload failed for ", basename(path), call. = FALSE)
    }
  }
  # The releases endpoint can serve stale reads for a few seconds after
  # an upload; verify with retries before declaring failure.
  for (i in 1:6) {
    if (basename(path) %in% release_assets(tag)) {
      return(invisible(path))
    }
    Sys.sleep(2)
  }
  stop(
    "upload of ",
    basename(path),
    " to ",
    tag,
    " failed verification; not advertising it",
    call. = FALSE
  )
}

publish_year <- function(year) {
  parquet <- file.path(out_dir, sprintf("brfss_%d.parquet", year))
  stopifnot(file.exists(parquet))
  tag <- sprintf("data-%d", year)
  if (!release_exists(tag)) {
    piggyback::pb_release_create(
      repo = repo,
      tag = tag,
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
      repo = repo,
      tag = tag,
      name = "Data manifest and variable catalog"
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
    auto_unbox = TRUE,
    pretty = TRUE
  )
  upload_verified(manifest, tag)
  message("published manifest: ", paste(range(years), collapse = "-"))
}

# Usage (after 02 and 03 have built everything):
# years <- 2011:2024
# purrr::walk(years, publish_year)
# publish_meta(years)
