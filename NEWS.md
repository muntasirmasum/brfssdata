# brfssdata (development version)

* The data manifest now records upstream provenance for every annual
  asset: the CDC download URL of the source SAS Transport zip, that
  file's sha256 and size as downloaded, the download and processing
  dates, and the row and column counts of the published parquet. The
  fields are additive within manifest schema 2, so installed versions
  that predate them read the new manifest unchanged (#1).
* `brfss_year_info()` reports the CDC source file behind each year:
  new `source_file`, `source_format`, and `source_sha256` columns plus
  a `downloaded` date, joined from the same build-pipeline provenance
  record as the manifest (#5).

# brfssdata 0.1.0

Initial CRAN release.

## Correctness

* The missing-code matcher now recognizes CDC's calculated-variable
  buckets whose labels carry a trailing noun ("Don't know, refused or
  missing values" and kin, plus the RACE2 family's "component question"
  wordings). Before this, `na = TRUE` (the `brfss_design()` default)
  silently left genuine code-9 don't-know/refused answers in 18
  variable/code combinations, including `_FRTLT1A` (51,087 uncleared
  rows in 2021 alone), `_HLTHPLN`, `_VEGLT1A`, and the `_LMT*` family,
  overstating those denominators by several points. The extension was
  validated against every distinct catalog label: it adds exactly those
  buckets and loses none, and "Doctor refused when asked"-style
  substantive answers still never match.
* Six variables that CDC stored as a number in some years and text in
  others (`SEQNO`, `_RECORD`, `MRACEORG`, `WINDDOWN`, `_MSACODE`,
  `RCVFVCH4`) are now written with one type across every hosted year,
  values unchanged. Multi-year reads previously promoted the numeric
  years to text, so the same MSA appeared as both `"1120"` and
  `"1120.0"` in one column, silently splitting groups and defeating
  missing-code matching. `read_brfss()` additionally refuses to combine
  files whose stored types conflict (`brfssdata_type_conflict`), so a
  stale cache mixed with current releases can never reproduce the bug
  silently; `brfss_cache_clear()` is the named remedy.
* A user-supplied `weight` in `brfss_design()` now subsets to the rows
  the weight covers, with a `brfssdata_weight_subset_note` message. The
  documented child-module call, `brfss_design(2023, weight =
  "_CLLCPWT")`, previously always failed on real data, because a module
  weight is missing outside its module's records (383,782 of 433,323
  rows in 2023) and the design constructor refused missing weights. The
  automatic era weight still aborts on missing values, which there
  indicate a damaged file, and an explicitly named full-sample weight
  (`_LLCPWT`, `_FINALWT`) follows that same rule instead of silently
  subsetting.
* The matcher also recognizes the abbreviations CDC's 1998 to 2001
  format libraries use for don't-know and refused ("UNK/REF", "UNK",
  "REF", "UNKNOWN"), together with the bare "N/A" and "N/A,REF"
  placeholders from the same years. Validated against every row of the
  shipped catalog, this matches 786 rows across 370 variables, all in
  1998 to 2001, and loses none. Without it, `na = TRUE` left those
  codes in the data for years the catalog nominally covers: 145,594
  cells in the 1998 file (`_DRNKMO` code 9999 alone on 117,351 rows)
  and 380,693 in 2001, so any mean or proportion from an affected
  variable was wrong. Spelled-out "not applicable" is deliberately not
  a token, because in later years it names ordinal scale positions such
  as `GETHIV` code 5.
* `na = TRUE` says so when requested years have no value-label catalog
  at all (1985-1997, a classed `brfssdata_na_coverage_warning`) or
  mostly lack it (1998 covers under a quarter of that file's
  variables, a `brfssdata_na_coverage_note`), instead of silently
  changing nothing.
* `labels = TRUE` refuses to convert a variable whose label wording
  changed meaning across the requested years, keeping CDC's numeric
  codes and naming it in a `brfssdata_label_drift_warning`. Applying
  the newest year's labels to every row would restate what earlier
  respondents answered: CDC reused `COLNTES1` and `SIGMTES1` codes 3 to
  5 for different colorectal screening intervals from 2022 on, so
  `read_brfss(2021:2024, vars = "COLNTES1", labels = TRUE)` would
  otherwise return a wrong interval distribution. This matches how
  every other ambiguity gate (incomplete formats, mismatched code sets,
  duplicate codes or labels, uncovered values) already behaves. The
  wording comparison folds `<` and `>` to words before stripping
  punctuation, so CDC's house abbreviation ("anytime < 12 months ago"
  against "anytime less than 12 months ago") counts as cosmetic and
  still converts.
* The pooled state-participation warning
  (`brfssdata_pooled_states_warning`) counts participation over the
  rows a user-supplied `weight` covers, the population the design
  actually estimates, not over the whole annual file. Counting over the
  file names states the design never contained, and goes silent when
  the files agree on coverage but the weight's domain does not, which
  is exactly the case for 2022 pooled with 2023 under `_CLLCPWT`.
* Blank SAS character fields are stored as missing values, not `""`,
  and code matching is proof against R's scientific notation, so a
  future round code at or above 100,000 cannot be skipped.
* The label-catalog builder reads two SAS syntaxes it used to
  misread, so the shipped catalog gains rows it had been dropping and
  loses rows it had invented. A comma-separated code list
  (`77,99 = 'UNK/REF'`, CDC's style through 2001) previously kept only
  the last code, which is why the whole 7, 77, and 777 don't-know
  family was missing from 1998 to 2001 and `na = TRUE` left those codes
  in place: a 2000 `PHYSHLTH` mean computed the documented way was 4.41
  days against 3.34 once the don't-know answers are cleared. A range
  written `244-<777` previously matched its bare endpoint, so the
  catalog claimed `WEIGHT` code 777 meant "244 +" when 777 is the
  don't-know sentinel, and 2,736 respondents in 2000 alone carried it.
  Ranges now emit no code and mark their format incomplete, which keeps
  factor conversion refused where it always should have been.
* Four label errors CDC published are corrected in the catalog, each
  recorded with the source that justifies it. CDC's 2002 library
  assigns one generic format to 17 variables and labels its code 88
  "Never smoked regularly", so `PHYSHLTH`, `MENTHLTH`, `POORHLTH` and
  a dozen others carried a smoking label on a code that means None
  there; the smoking items keep CDC's wording. `DISPCODE` 1999 code 2
  read "REFUSED", which the missing-code matcher took for a missing
  bucket although it names an interview disposition, and now reads
  "02-REFUSED" as CDC wrote it from 2000. `_IMPNPH` 2002 code 7 no
  longer inherits a don't-know label from the raw question's format.
  The builder now also reports every code whose missing or substantive
  status flips between adjacent years, so this class of error cannot
  ship unnoticed again.
* `TYPEARTH` code 88 is now read as CDC labeled it in 1998 and 1999,
  where their format libraries group it with 77 and 99 as unknown or
  refused; CDC splits it out as "NEVER SAW A DOCTOR" from 2000 on.
  Under `na = TRUE` this clears 11 rows in 1998 and 49 in 1999 that
  previously survived. The package reports each year's published
  labels and does not reinterpret one year's codebook with another's.
* The rename crosswalk covers the personal-doctor family (`PERSDOC`,
  `PERSDOC2`, `PERSDOC3`), one of CDC's flagship healthcare-access
  measures. Reading `PERSDOC3` across 2019 to 2023 returned 820,226
  silently empty rows for 2019 and 2020 with no rename note, and
  `brfss_crosswalk("PERSDOC3")` reported that the variable had kept one
  name throughout, which was false. The zero-match message no longer
  makes that claim for any variable.
* Pooled designs no longer dilute totals through a year that
  contributed nothing. `brfss_design(2022:2023, states = "KY")` built a
  design of 2022 rows alone, Kentucky having collected no 2023 data,
  yet divided every weight by the two requested years, so
  `survey_total()` reported half the state's adult population. The
  participation check now treats a requested year with no in-scope rows
  as an empty year rather than skipping it. Means and proportions were
  never affected, because the rescaling cancels.
* A cached year whose checksum fails verification can no longer be
  served silently for the rest of the session. The daily recheck marked
  every due file as checked before the repair was attempted, so a
  failed re-download (offline, or a 404) left the memo in place and the
  next call in the same session returned the unverified file with no
  message, while `brfss_cache_info(verify = TRUE)` reported it as
  failing. Only files that pass are marked.
* `read_brfss()` checks that the years it read are the years asked
  for. A parquet file carrying the wrong year under the right filename,
  which a botched hand-copy of a cache produces, was served as a
  plausible tibble of the wrong survey year under `download = FALSE`.
* `na = TRUE` warns, rather than merely noting, when the catalog covers
  none of the variables loaded for a year. The grade was keyed on
  whether the year had any catalog entries at all, so a 1998 request
  for six uncatalogued variables recoded nothing and said so only in a
  message, which `message = FALSE` in a report suppresses entirely.
* Every `TRUE`/`FALSE` argument is now validated at entry with a
  classed error naming the argument and the value it received. Half of
  them reached base R's `&&` and failed with "invalid 'y' type in 'x &&
  y'", which named nothing and carried no condition class, and
  `verify` and `catalogs` accepted anything at all: `brfss_cache_info(
  verify = "yes")` hashed nothing while reading, to the person who
  typed it, as a request to hash everything.
* `brfss_design()` sets `options(survey.lonely.psu = "adjust")` only
  when the design it built actually contains a single-PSU stratum. It
  previously wrote the option on every call, including for years that
  have none (1995 and 2003 have no such stratum; 2023 has 101 of
  2,146), so an unrelated survey analysis later in the session
  inherited the adjustment in place of survey's fail-fast default. A
  pinned `brfssdata.lonely_psu` is still honored unconditionally.
* A design variable missing from a damaged or foreign cached file now
  raises `brfssdata_bad_design_var`, the class the conditions page
  documents for it, and points at the cache remedy instead of at
  variable search. A weight the caller named is not treated as such:
  `_LLCPWT2` exists in 2014 and 2016 but not 2015, and asking for it in
  2015 reports a missing variable rather than accusing an intact file
  of corruption and advising its deletion.
* `_AGEG_` reads as CDC's aggregate age groups in 1999 and 2000.
  CDC's assignment files for those years point the column at `AGEGFMT`,
  whose six codes stop at 65+ and read 7 and 9 as unknown, while the
  column actually holds the twelve codes of `_AGEGFMT`, which both
  libraries define and which CDC assigns correctly from 2001. Codes 7
  and 9 are the aggregates 18-34 and 55+, and 0, 8, 10, and 11 had no
  labels at all. Under the wrong format `na = TRUE` deleted the age
  group of 2,956 respondents whose age is known, every one of the 1,512
  at code 7 in 2000 being aged 18 to 34.
* A cached file holding another year's data is caught even when that
  other year was also requested. Comparing the combined result against
  the whole request could not see the likeliest hand-copy error of all,
  one file copied over another's name, because every row's year was
  inside the request and the year simply counted twice; each file is
  now judged against its own name.
* A failed catalog refresh no longer marks the catalog checked. The
  daily recheck memo was corrected on the data path in this release,
  and the value-label and crosswalk catalogs had the identical defect,
  where one failed refresh served a catalog known not to match the
  manifest for the rest of the session.
* A cache directory that cannot be written to keeps its
  `brfssdata_download_error` class. The message naming the directory
  was assembled as a template and rendered in a frame that had no such
  directory to name, so the error died inside its own construction with
  a bare coercion failure carrying no class, and with it every fallback that
  subscribes to that class, including the bundled-snapshot degradation.
* The stale-download sweep no longer matches files a user keeps.
  A dated snapshot such as `manifest-2024.json` is hex by accident, and
  the pattern that recognized this package's own staged manifests
  recognized those too and deleted them silently.
* `na = TRUE` says which named variables the catalog does not cover,
  rather than reporting a ratio. A 1999 read of `PHYSHLTH` beside
  `GENHLTH` sat at exactly one covered variable of two, just inside a
  threshold that required fewer than half, and said nothing at all
  while `PHYSHLTH` kept its 77s. A year that never asked a loaded
  question is no longer named either: an all-NA column carries no codes
  to leave behind.
* `download = FALSE` no longer withholds the prefetch command for a
  year that is merely missing from this machine's manifest. An
  air-gapped cache copied before the newest release is the documented
  workflow, and it made the package assert that a published year does
  not exist. Only a year in the future is refused outright.

## Discovery and metadata

* A `brfss_vars()` search that matches nothing says so
  (`brfssdata_empty_result`) and suggests near misses: variables whose
  name or label is a small edit away, variables matching every word of
  a multi-word pattern in any order, and, under a `years` filter,
  matches that exist only in other years. Unknown-variable errors from
  `read_brfss()` and `brfss_codebook()` likewise name the years that
  do carry the variable and offer a did-you-mean for close names.
* `brfss_crosswalk()` reports CDC's trailing-digit rename families
  (`_DRNKWK1` to `_DRNKWK3`). A `status` column records how far human
  review of each family has gone (mechanically proposed families ship
  as `"candidate"`), and `comparable`/`note` record the reviewed
  verdict per generation pair. When a requested variable is empty in
  years a sibling generation covers, `read_brfss()` says so
  (`brfssdata_rename_note`); combining generations stays the analyst's
  decision.
* `read_brfss()` and `brfss_design()` gain `states =` (FIPS, postal
  abbreviation, or name), pushed into the DuckDB query so other states'
  rows never reach R. For states this pre-filtering is variance-exact,
  because BRFSS strata nest within state. A requested state absent from
  a year warns (`brfssdata_state_coverage_warning`).
* `brfss_codebook()` renders a per-variable card: label history, value
  labels with missing-type codes flagged, year availability, and the
  rename family. A card whose variable has no coded values says which
  of the two reasons applies, either that the requested years sit
  outside the catalog's span or that CDC's format for the variable is
  continuous or range-only (`_BMI5`), and a card built from a range
  format (`PHYSHLTH`, cataloged only as 77, 88, and 99) says that
  ordinary in-range values are valid and are not listed, so a truncated
  code list cannot read as the whole value set. Cards carry codes and
  labels only, with no units, scale factor, or valid range; those live
  in CDC's codebook, named per year by `brfss_year_info()$codebook_url`.
  A cache-integrity failure while reading the rename crosswalk aborts,
  as it does everywhere else in the package, rather than quietly
  returning a card with no concept family. `brfss_year_info()` lists
  respondents, variables, states, hosted size, and CDC's documentation
  page per year. `brfss_citation()` returns per-year `bibentry`
  citations, each with a stable BibTeX key (`brfss2023` and the like,
  and `brfssdata` for the package), so `toBibtex()` output drops into a
  `.bib` file unedited.
* `brfss_labels()` and `brfss_crosswalk()` say so when only some
  requested variables match (`brfssdata_partial_match_note`), naming
  the ones with no entries, instead of silently returning rows for the
  rest. A miss can be legitimate (continuous variables have no label
  entries; most variables belong to no rename family), which is
  exactly why it deserves a note rather than silence: without one, a
  legitimate absence and a typo look identical.
  `brfss_missing_codes()` inherits the note.
* `brfss_citation(integer(0))` errors with `brfssdata_bad_years_arg`
  instead of returning a malformed, data-free citation list with no
  signal that nothing was cited.
* New package data: `brfss_states` (FIPS, names, abbreviations, Census
  regions for all 56 BRFSS jurisdictions) and `brfss_std_pop_2000` (the
  2000 projected U.S. standard population, all-ages and `_AGE_G`-
  matched adult groupings, for `survey::svystandardize()`).
* The variable, label, and crosswalk catalogs ship as bundled snapshots,
  so metadata functions work on first use with no network; a snapshot
  is never served silently (`brfssdata_bundled_fallback_note`).
* A `brfss_vars()` search that matches nothing keeps its single-word
  hint even when it has close matches to offer, and a search token now
  also reaches a variable through its name stem. Searching CDC's own
  questionnaire wording, "personal doctor", previously matched nothing
  and suggested five caregiving variables, none of them the
  personal-doctor question. The help now says that searches run over
  CDC's 40-character SAS labels, whose wording differs from the
  questionnaire and is sometimes cut mid-word.
* `brfss_labels()` returns codes in ascending order within a variable
  and year, the order a codebook reads in and the order
  `brfss_codebook()` already used.
* Codebook cards say that a column may also be blank, from a question
  that was not asked or an interview that ended early, so the first
  `mean()` returning `NA` has an explanation on the card.

## Access

* `read_brfss()` returns respondent-level BRFSS microdata for any of the
  40 published survey years (1985-2024) as a tibble. Each year is
  downloaded once from the package's data releases, verified against a
  published sha256 checksum, and cached under `tools::R_user_dir()`;
  queries run locally through DuckDB, so selecting a handful of
  variables from a 300-plus column survey stays fast and repeat use
  works offline.
* `read_brfss()` with no `vars` selection says it is loading every
  column before anything is read (`brfssdata_full_load_note`): a bare
  `read_brfss(2024)` materializes 302 columns and about 1.1 GB where a
  one-column projection is about 5 MB. The note names `vars = c(...)`
  as the remedy; it previously fired only from `brfss_design()`, which
  now inherits it from `read_brfss()`.
* `brfss_design()` builds a srvyr survey-design object with the
  era-correct final weight (`_FINALWT` through 2010, `_LLCPWT` from
  2011), strata, and primary sampling units. Requests that pool years
  across the 2011 redesign fail unless `allow_break = TRUE` is set,
  because CDC states estimates are not comparable across that boundary.
  Files through 2000 carry genuine multi-respondent PSUs and keep the
  clustered variance estimator; from 2001 on each respondent is their
  own PSU, and the design drops the nominal cluster term for identical
  estimates at a fraction of the cost. A `weight` argument selects
  another final weight, such as the child weight `_CLLCPWT`, when CDC's
  documentation calls for it. Module analyses that require CDC's
  questionnaire-version datasets and their `_LCPWTV1` to `_LCPWTV3`
  final weights are not supported by the hosted annual files.
* By default, `brfss_design()` sets the codes CDC uses for don't-know,
  refused, and missing-type answers to `NA` (`na = TRUE`), so means and
  proportions cover substantive answers; `read_brfss()` defaults to
  `na = FALSE` and returns the file as published. The exported
  `brfss_missing_codes()` lists exactly which codes are affected.
* `brfss_design(weight = )` accepts CDC's final analysis weights only:
  `_FINALWT` (1985-2010) and `_LLCPWT` (2011 on) for the full sample,
  the domain weights `_CLLCPWT`, `_CHILDWT`, and `_HOUSEWT`, and the
  2007 questionnaire-version weights `_FINALQ1`, `_FINALQ2`,
  `_CHILDQ1`, and `_CHILDQ2`. Anything else, an intermediate pipeline
  stage or an arbitrary column, is a classed error
  (`brfssdata_unrecognized_weight`) unless `unsafe_weight = TRUE` says
  it is deliberate, and the override still warns. Previously only five
  modern intermediates drew a warning and everything else passed
  silently: the review built designs with `weight = "GENHLTH"` (female
  share shifted 1.8 points) and the 1985-2000 design weight `_WT1`
  (fair/poor health shifted 0.95 points) without a signal. Weight
  values must now be positive and finite, a final weight requested
  outside its published span fails before anything downloads, and an
  explicitly named full-sample weight obeys the same completeness rule
  as the automatic path: missing values abort as a damaged file
  instead of silently subsetting the design. All weight columns, final
  and intermediate, are excluded from labeling and `na` recoding on
  every path.
* `brfss_design()` detects the reverse weight mistake too: a requested
  variable whose answers sit almost entirely inside a module weight's
  records (95% or more in every requested year) while the design uses
  a full-sample weight draws a `brfssdata_module_weight_warning`
  naming the weight to consider. The live case: 2023 child asthma
  (`CASTHDX2`, 99.7% confined to `_CLLCPWT`'s records) under the
  default `_LLCPWT` estimated 10.86% against the correct 10.36%, with
  no signal. It warns rather than fails because state-optional modules
  that CDC assigns to the core weight produce the same confinement
  shape; `options(brfssdata.module_weight_check = FALSE)` disables it.
* `quiet = TRUE` governs progress and housekeeping output only:
  download progress, cache notes, the full-load hint, and the recode
  tally. Signals about what the data mean fire regardless of `quiet`:
  the rename note, the missing-code coverage signals, and the
  weight-domain subset note. Previously all three were suppressed by
  `quiet = TRUE`, which every article passed, so a
  `brfss_design(weight = "_CLLCPWT", quiet = TRUE)` call could
  silently estimate a different population. Requesting `na = TRUE`
  for years before 1998, where no value-label catalog exists, is now
  a classed warning (`brfssdata_na_coverage_warning`) rather than a
  message: nothing was cleared there, and a 1993 `PHYSHLTH` mean with
  the 77/99 codes left in is materially wrong. Silence any of these
  by class, e.g.
  `suppressMessages(..., classes = "brfssdata_rename_note")`.
* `brfss_labels()` exposes CDC's value-label catalog (1998-2024), and
  `labels = TRUE` converts variables with safe one-to-one maps to
  factors; ambiguous maps keep their numeric codes. `labels = "both"`
  keeps the code in the level text so it survives conversion.
* `brfss_vars()` searches variable names and labels across years;
  `brfss_years()` lists the published years. Variable names match
  case-insensitively everywhere, and returned columns keep CDC's
  canonical spelling.
* `brfss_download()` prefetches years and the metadata catalogs for
  offline use; `brfss_cache_dir()`, `brfss_cache_info()`, and
  `brfss_cache_clear()` manage the cache. A cached file that fails
  integrity checks is re-downloaded automatically or named in a classed
  error with its remedy.
* Downloads fail instead of hanging on a dead network: the transfer
  aborts if a connection takes more than a minute to establish or an
  established transfer sits below 100 bytes/s for five minutes, since
  libcurl sets no ceiling of its own. When curl reports a classed
  transport error, the `brfssdata_download_error` message names the
  likely cause, distinguishing an unreachable GitHub (offline or
  blocked network) from a proxy or TLS-interception failure, a stalled
  connection, and a rejected request, each with its remedy. Failures
  the transport cannot classify keep the generic wording.
* Cached survey years are re-verified against the manifest's checksums
  at most once a day per session, the same cadence the metadata
  catalogs already use. A cached file whose hash no longer matches is
  treated like a damaged one: announced (`brfssdata_cache_note`) and
  re-downloaded verified, with the old file kept until a verified
  replacement lands. Previously only file size was compared after the
  initial download, so a same-size corrupted copy was accepted without
  a condition. On that same path, a fully cached `read_brfss()` with
  `download = TRUE` now lets the manifest refresh on its daily
  cadence, so a user who cached a year before a corrected republish is
  told within a day; when the refresh fails (offline), the cached
  manifest is used with a `brfssdata_manifest_note` and the read
  proceeds as before. `download = FALSE` checks nothing, downloads
  nothing, and never deletes anything.
* `brfss_cache_info(verify = TRUE)` adds a `verified` column: `TRUE`
  when a cached file's sha256 matches the manifest entry, `FALSE` on a
  mismatch, `NA` where the manifest has no entry to compare against.
  Off by default because hashing reads every byte, roughly two seconds
  for the full 40-year, 737 MB cache, and `brfss_download()` lists the
  cache on every call.
* A cached manifest that is present but unreadable does not count as
  fresh. The manifest is the one asset fetched without an expected
  hash, and any non-empty payload is accepted, so a captive-portal or
  proxy error page served with HTTP 200 could otherwise sit in the
  cache looking new. For a day after that, `brfss_years()` would return
  `integer(0)` and every checksum lookup would return `NULL`, so
  downloads would proceed unverified. Freshness now reads the content,
  the bundled copy wins over an unusable cache with a
  `brfssdata_manifest_note` naming `brfss_years(refresh = TRUE)` as the
  repair, and a downloaded manifest reaches the cache only once its
  payload parses.
* A request whose `states` filter leaves no rows aborts with a classed
  `brfssdata_no_eligible_rows` error naming the states, years, and
  weight, instead of failing inside the survey package with "group
  length is 0 but data length > 0". Kentucky and Pennsylvania in 2023
  are the live cases. `read_brfss()` still returns the zero-row tibble,
  which is a usable answer where a zero-row design is not.
* Every error, warning, and message carries a documented condition
  class; see `?brfssdata-conditions`.

## Performance and ergonomics

* Metadata reads are served from a session memo. The label catalog was
  previously read from parquet, through its own DuckDB connection, on
  every call that used it, twice per `brfss_design()` with defaults;
  the manifest JSON was re-parsed up to three times per read and about
  fifteen times per `brfss_download(catalogs = TRUE)`. Each is now
  parsed once per file state (the memo invalidates when the on-disk
  file changes), and the missing-code matcher runs only on the
  requested years' catalog rows. Results are byte-identical; repeat
  calls in a session skip the parquet and JSON work entirely.
* A `vars` typo no longer costs a download: when a requested year is
  not yet cached, `read_brfss()` and `brfss_design()` first check the
  requested variables against the variable catalog (cached or bundled,
  never fetched for this purpose) and abort with the same
  `brfssdata_bad_var` error the query would raise, before any
  20-30 MB year file transfers. Years the catalog does not cover skip
  the check, so a stale catalog can never block a valid read.
* The "Did you mean `years = ...`?" hint for a year-shaped first
  argument, previously only in `brfss_labels()`, now also fires in
  `brfss_crosswalk()`, `brfss_codebook()`, and
  `brfss_missing_codes()`.
* `print()` on a `brfss_codebook` caps at 10 cards and says how many
  more there are; `print(x, n = Inf)` renders everything. A codebook
  of the full catalog previously printed thousands of cards.
* `brfss_cache_clear()` called with no `years` argument in an
  interactive session now asks before deleting every cached year.
  Scripts, tests, and rendered documents are never prompted, and an
  explicit `years = NULL` keeps the old clear-everything behavior
  without a question.
* Every session option the package reads is documented in one place,
  `?brfssdata-options`, including the previously undocumented
  `brfssdata.repo`.
* A cache directory that cannot be created or written to is reported as
  the permission problem it is. The failure previously arrived as a
  download error suggesting the user might be offline, and a failed
  directory creation was followed by a note saying where downloads
  would be cached, which is the one population the package documents
  restricted-network workarounds for.
* `brfssdata.cache_dir` is validated where it is read, so a mistyped
  path in `.Rprofile` fails immediately instead of reporting an empty
  cache. Partial downloads left behind by a killed session are swept,
  while files the package did not write are still never touched.
  `brfss_cache_info()` lists regular files only.
* `quiet = TRUE` suppresses the first-run cache-directory note, which
  reached the console through the manifest refresh whatever the caller
  asked for. A re-download caused by a failed integrity check now
  reports itself even under `quiet = TRUE`, being an integrity event
  rather than progress narration.
* The `duckdb (>= 1.5.5)` requirement is checked when a connection is
  opened, not only at install time. duckdb loads lazily and is not in
  the package's imports for version purposes, so a downgrade or a
  shadowing site library silently removed the guard that keeps duckdb
  from writing to the user's home directory.
* `brfss_years()` takes `download` and `quiet`, the vocabulary the
  other exports use, so a strictly offline call is expressible.
* srvyr's `survey_mean()`, `survey_prop()`, `survey_total()`,
  `unweighted()`, and `as_survey_design()` are re-exported, so the
  README's three-line estimate runs with `library(brfssdata)` and
  dplyr alone. Forgetting `library(srvyr)` previously let the design
  build and `group_by()` succeed, then failed at the last verb with a
  bare "could not find function" and no mention of srvyr.

## Documentation

* A *Value labels and missing codes* article walks the `labels` and
  `na` workflow end to end: what converts and what deliberately does
  not, the split defaults, auditing with `brfss_missing_codes()`, the
  88-means-"None" recode, why `%in%` misreads NA-cleared data, and
  silencing signals by condition class.
* The *Age-adjusted prevalence* article passes the outcome to
  `survey::svystandardize()`, as `excluding.missing = ~ fair_poor +
  age_group`. `svystandardize()` filters on `excluding.missing` before
  it calibrates, so naming only the age variable leaves the age weights
  calibrated over respondents that `na.rm = TRUE` discards afterwards,
  returning the age-group means weighted by standard share times
  weighted response rate instead of by standard share alone. The two
  agree only when item nonresponse is flat across age, which it is not.
  The recipe also labels the age factor from `brfss_std_pop_2000` and
  asserts the level order, because `svystandardize()` matches
  `population` to the levels of `by` by position without checking
  names. `brfss_std_pop_2000` now documents that ordering contract.
* The articles no longer call a whole-file estimate national. The 2023
  public-use file covers 52 reporting areas, 48 states plus the
  District of Columbia, Guam, Puerto Rico, and the U.S. Virgin Islands,
  with Kentucky and Pennsylvania absent.
* The age-adjustment article states which standard reproduces CDC's
  published tables. CDC age-adjusts most BRFSS questions with three
  age groups, 18 to 44, 45 to 64, and 65 and over, and the article
  previously presented its six-group result as the number CDC's tables
  report, which it is not: 2023 Florida came out 0.26 points below
  CDC's published figure. The three-group recipe, obtainable by summing
  the shipped standard-population rows, matches to rounding, and six
  groups are shown as the finer alternative. `?brfss_std_pop_2000` no
  longer claims the six-group set is what CDC uses.
* The Stata section no longer promises that value labels carry CDC's
  codes through `haven::write_dta()`. Factor export renumbers values to
  level positions, so code 7 arrives as 6 and a "Never" answer coded 8
  arrives as 5, and a code-based recode in Stata silently misses the
  answers it names. The article gives routes that keep the codes.
* The Korn-Graubard interval in the validation article returns a number.
  It was demonstrated without `na.rm = TRUE` on a design that recodes
  missing values, so the published page showed `NA NA NA` for the
  method the section recommends.
* Corrected doc claims: a modern survey year runs to 45 MB, not 35;
  DuckDB accepts unquoted underscore-prefixed identifiers, so quoting
  them is portability advice and not a syntax requirement; the
  `data-meta` tag hosts nine assets, including the crosswalk and year
  inventory a mirror needs; srvyr's `filter()` on a design deletes rows
  and estimates the domain through each stratum's recorded PSU count,
  rather than keeping respondents at zero weight; `labels = TRUE` alone
  signals nothing on pre-1998 years and the recode tally is governed by
  `quiet`. The articles also note how a degenerate subgroup behaves,
  which variables are stored as text, and how to keep don't-know and
  refused apart, the distinction R's single `NA` cannot hold.
* `?brfss_design` and the vignette no longer say flatly that primary
  sampling units are applied. From 2001 on they are not, deliberately,
  and a design built for those years prints `ids: 1`, which reads as a
  dropped design feature to anyone auditing against a Stata `svyset`
  line. The era rule was documented only under the *Choosing a weight*
  heading, where nobody looking for it would find it; it now has its own
  section, *Why some years have no PSU term*, which states the numbers:
  on 2023 the estimate, the standard error, and the degrees of freedom
  are identical to the last bit of a double with and without the cluster
  term, while on 1995, where PSUs are shared, the two specifications
  genuinely differ.

## Known limitations

* Upstream provenance is not recorded yet: `brfss_year_info()` carries
  no CDC source URL, retrieval date, or hash of the upstream SAS
  Transport file, so the package cannot say which CDC revision of a
  year the hosted copy was built from. The published checksums cover
  the hosted copies. Provenance columns are planned for 0.1.1, which
  requires a data republish.
* Calculated variables keep CDC's stored scaling. `_BMI5` and
  `_DRNKWK2` carry two implied decimals (a stored 2704 in `_BMI5` is a
  BMI of 27.04), and neither the files nor the catalogs record scale
  factors, units, or valid ranges. Codebook cards say so and point to
  CDC's per-year codebook (`brfss_year_info()$codebook_url`). Curated
  scale metadata is 0.2.0 work.
* No value-label catalog exists before 1998, so `na = TRUE` has
  nothing to consult there and warns instead of guessing; special
  codes in 1985 to 1997 must be recoded by hand from CDC's codebooks.
  This is a deliberate policy of signaling over hand-curation.
* Coverage inside 1998 to 2001 is uneven for the same reason. CDC's
  1999 library defines no format for the variables its assignment file
  points at, `PHYSHLTH` and `MENTHLTH` among them, so those columns
  have no catalog entries that year and `na = TRUE` cannot clear their
  77s. A read that touches them says how many of the loaded variables
  the catalog covered.
* Module analyses that require CDC's questionnaire-version datasets
  and their `_LCPWTV1` to `_LCPWTV3` final weights are unsupported;
  the hosted annual files do not include those weights. The
  module-weight confinement check covers the reachable cases; curated
  module-to-weight metadata is 0.2.0 work.
* Data releases are not immutable snapshots. A corrected year replaces
  the published bytes under the same tag; the manifest checksum and
  the daily cache recheck notice the change, but an analysis cannot
  yet pin itself to an exact prior snapshot. Versioned snapshots are
  0.2.0 work.
