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

# The published .sha256 sidecar for an asset, or NULL when none exists.
published_sha256 <- function(tag, asset) {
  tmp <- tempfile()
  on.exit(unlink(tmp))
  ok <- tryCatch(
    {
      utils::download.file(
        sprintf(
          "https://github.com/%s/releases/download/%s/%s.sha256",
          repo,
          tag,
          asset
        ),
        tmp,
        quiet = TRUE
      )
      TRUE
    },
    error = function(e) FALSE,
    warning = function(w) FALSE
  )
  if (!ok) {
    return(NULL)
  }
  strsplit(trimws(readLines(tmp)[[1]]), "\\s+")[[1]][[1]]
}

# Uploads go through the gh CLI: piggyback 0.1.5 memoizes its release
# listings so aggressively that releases created moments earlier are
# invisible to pb_upload. Verification reads the GitHub API directly.
# Assets already present are not re-uploaded unless force = TRUE. The
# name-based skip cannot see content changes, so before trusting it the
# local bytes are compared against the published .sha256 sidecar: a
# local rebuild that differs from the hosted asset must stop the
# publish, or publish_meta() would advertise manifest hashes no
# download can ever satisfy.
upload_verified <- function(path, tag, force = FALSE) {
  present <- basename(path) %in% release_assets(tag)
  if (!force && present && !endsWith(path, ".sha256")) {
    published <- published_sha256(tag, basename(path))
    local <- cli::hash_file_sha256(path)
    if (!is.null(published) && !identical(published, local)) {
      stop(
        basename(path),
        " differs from the published copy on ",
        tag,
        "; local rebuilds of published years must not be skipped ",
        "silently. Re-upload deliberately with force = TRUE (and its ",
        "sidecar), or restore the published bytes.",
        call. = FALSE
      )
    }
  }
  if (force || !present) {
    status <- system2(
      "gh",
      c("release", "upload", tag, path, "--repo", repo, "--clobber")
    )
    if (status != 0) {
      stop("gh release upload failed for ", basename(path), call. = FALSE)
    }
  }
  # The releases endpoint is eventually consistent and has been observed
  # serving stale reads well past ten seconds after an upload; back off
  # for up to a minute before declaring failure.
  for (i in 1:10) {
    if (basename(path) %in% release_assets(tag)) {
      return(invisible(path))
    }
    Sys.sleep(i)
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
  years <- sort(as.integer(years))

  # The manifest is rewritten from `years` alone, so an argument that
  # omits a hosted year would delist it for every user whose manifest
  # refreshes. Cross-check against the release tags actually hosted.
  hosted <- system2(
    "gh",
    c(
      "api",
      sprintf("repos/%s/releases", repo),
      "--paginate",
      "--jq",
      shQuote(".[].tag_name")
    ),
    stdout = TRUE
  )
  hosted_years <- as.integer(sub("^data-", "", grep("^data-\\d{4}$", hosted, value = TRUE)))
  delisted <- setdiff(hosted_years, years)
  if (length(delisted) > 0) {
    stop(
      "publish_meta(years) omits hosted year(s) ",
      paste(sort(delisted), collapse = ", "),
      "; publishing this manifest would delist them for every user. ",
      "Pass every hosted year (see data-raw/README.md).",
      call. = FALSE
    )
  }
  catalogs <- file.path(
    out_dir,
    c("brfss_variables.parquet", "brfss_labels.parquet")
  )
  for (catalog in catalogs[file.exists(catalogs)]) {
    upload_verified(catalog, tag, force = TRUE)
    upload_verified(sha256_file(catalog), tag, force = TRUE)
  }

  # Manifest schema v2: a per-asset sha256/size map that the package
  # verifies at download time. An advertised year whose parquet is not on
  # this machine gets no entry, and the package falls back to an
  # unverified download for it, so warn rather than fail.
  assets <- c(file.path(out_dir, sprintf("brfss_%d.parquet", years)), catalogs)
  missing <- assets[!file.exists(assets)]
  if (length(missing) > 0) {
    warning(
      "no local copy to hash; these will be advertised unverified: ",
      paste(basename(missing), collapse = ", "),
      call. = FALSE
    )
  }
  assets <- assets[file.exists(assets)]
  files <- lapply(assets, function(path) {
    list(sha256 = cli::hash_file_sha256(path), size = file.size(path))
  })
  names(files) <- basename(assets)

  manifest_body <- list(
    schema_version = 2L,
    generated = format(Sys.Date()),
    years = years,
    files = files
  )
  manifest <- file.path(out_dir, "manifest.json")
  jsonlite::write_json(manifest_body, manifest, auto_unbox = TRUE, pretty = TRUE)

  # The bundled fallback ships the same content from the same code path,
  # so it always carries hashes too (plus a note on its role).
  bundled <- c(
    manifest_body[c("schema_version", "generated")],
    list(
      note = paste(
        "Bundled fallback snapshot. The live manifest is published as a",
        "release asset (tag data-meta) and is the source of truth for",
        "currently hosted years."
      )
    ),
    manifest_body[c("years", "files")]
  )
  jsonlite::write_json(
    bundled,
    "inst/extdata/manifest.json",
    auto_unbox = TRUE,
    pretty = TRUE
  )

  upload_verified(manifest, tag, force = TRUE)
  message("published manifest: ", paste(range(years), collapse = "-"))
}

# Usage (after 02, 03, and 05 have built everything). publish_meta()
# rewrites the manifest from exactly the years passed and aborts if that
# would delist a hosted year, so pass the FULL hosted range:
# years <- 1985:2024
# purrr::walk(years, publish_year)
# publish_meta(years)
