rclinvarbitration_validate_profile <- function(con, profile_id) {
  version_sql <- rclinvarbitration_sql_string(rclinvarbitration_policy_version())
  profile_sql <- rclinvarbitration_sql_string(profile_id)
  n_profile <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT count(*) AS n FROM clinvar_policy_profiles WHERE policy_version = ",
      version_sql, " AND profile_id = ", profile_sql
    )
  )$n[[1L]]
  if (n_profile != 1) {
    stop("`profile_id` is not a configured ClinVarbitration policy profile.", call. = FALSE)
  }
  invisible(NULL)
}

rclinvarbitration_compatibility_select_sql <- function(
    release_sql, assembly_sql, profile_sql, policy_query = NULL) {
  policy_source <- if (is.null(policy_query)) {
    "clinvar_policy_allele_decisions p "
  } else {
    paste0("(", policy_query, ") p ")
  }
  paste0(
    "SELECT DISTINCT ",
    "CASE WHEN l.assembly = 'GRCh38' THEN ",
    "CASE WHEN l.chromosome IN ('M', 'MT') THEN 'chrM' ELSE 'chr' || l.chromosome END ",
    "ELSE CASE WHEN l.chromosome = 'MT' THEN 'M' ELSE l.chromosome END END AS contig, ",
    "cast(l.position_vcf AS INTEGER) AS position, ",
    "l.reference_allele_vcf AS reference, l.alternate_allele_vcf AS alternate, ",
    "p.policy_classification AS clinical_significance, ",
    "cast(p.gold_stars AS INTEGER) AS gold_stars, cast(p.allele_id AS INTEGER) AS allele_id ",
    "FROM ", policy_source,
    "JOIN clinvar_alleles a ON a.release_id = p.release_id ",
    "AND a.vcv_accession = p.vcv_accession AND a.allele_id = p.allele_id ",
    "AND a.parent_allele_entity_id IS NULL ",
    "JOIN clinvar_locations l ON l.release_id = a.release_id ",
    "AND l.vcv_accession = a.vcv_accession AND l.allele_entity_id = a.allele_entity_id ",
    "WHERE p.release_id = ", release_sql, " AND p.profile_id = ", profile_sql,
    " AND l.assembly = ", assembly_sql,
    " AND l.chromosome IN ('1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', ",
    "'12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', 'X', 'Y', 'M', 'MT') ",
    " AND l.position_vcf IS NOT NULL AND l.reference_allele_vcf IS NOT NULL ",
    "AND l.alternate_allele_vcf IS NOT NULL ",
    "AND lower(l.reference_allele_vcf) <> 'na' AND lower(l.alternate_allele_vcf) <> 'na' ",
    "AND l.reference_allele_vcf <> l.alternate_allele_vcf ",
    "AND length(l.reference_allele_vcf) + length(l.alternate_allele_vcf) <= 40 ",
    "AND regexp_full_match(l.reference_allele_vcf, '^[ACGTN]+$') ",
    "AND regexp_full_match(l.alternate_allele_vcf, '^[ACGTN]+$')"
  )
}

#' Export an allele-level ClinVarbitration-compatible Parquet file
#'
#' Writes the seven columns in Centre for Population Genomics ClinVarbitration's
#' `clinvar_decisions.tsv`: `contig`, `position`, `reference`, `alternate`,
#' `clinical_significance`, `gold_stars`, and `allele_id`. The source is the
#' package's allele-level policy view, not the disease-level decision view, so
#' each output row is usable as a locus/alleles annotation record. Both GRCh37
#' and GRCh38 are supported. The output retains every qualifying source locus,
#' including distinct X/Y locations for one AlleleID.
#'
#' The file is schema-compatible with the upstream TSV/Hail decision resource,
#' but is not claimed to be byte-for-byte equivalent: this package derives
#' submissions and locations from VCV XML, whereas upstream uses ClinVar's
#' tab-delimited submission and variant summaries. PM5 is deliberately not
#' exported; Rduckhts/DuckHTS own downstream consequence and PM5 processing.
#'
#' @param con A DuckDB DBI connection initialized with
#'   [rclinvarbitration_init()].
#' @param path New output `.parquet` file path.
#' @param release_id Imported ClinVar release label to export.
#' @param assembly Genome assembly: `"GRCh38"` or `"GRCh37"`.
#' @param profile_id Policy profile identifier, normally `"default"`.
#' @param submitter_exclusions Additional submitter names to exclude from this
#'   export. Matching is case-insensitive and ignores surrounding whitespace.
#'   These exclusions are combined with any exclusions already stored for
#'   `profile_id`; imported source submissions are not deleted.
#' @return A named list describing the written Parquet file, invisibly.
#' @export
rclinvarbitration_export_clinvarbitration_parquet <- function(
    con, path, release_id, assembly = c("GRCh38", "GRCh37"), profile_id = "default",
    submitter_exclusions = character()) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("`path` must be a non-empty output file path.", call. = FALSE)
  }
  if (!is.character(release_id) || length(release_id) != 1L || is.na(release_id) || !nzchar(release_id)) {
    stop("`release_id` must be a non-empty character scalar.", call. = FALSE)
  }
  if (!is.character(profile_id) || length(profile_id) != 1L || is.na(profile_id) || !nzchar(profile_id)) {
    stop("`profile_id` must be a non-empty character scalar.", call. = FALSE)
  }
  submitter_exclusions <- rclinvarbitration_normalize_submitter_exclusions(submitter_exclusions)
  assembly <- match.arg(assembly)
  path <- normalizePath(path, mustWork = FALSE)
  if (!dir.exists(dirname(path))) {
    stop("The parent directory of `path` does not exist.", call. = FALSE)
  }
  if (file.exists(path)) {
    stop("`path` already exists; refuse to overwrite it.", call. = FALSE)
  }

  release_sql <- rclinvarbitration_sql_string(release_id)
  assembly_sql <- rclinvarbitration_sql_string(assembly)
  n_release <- DBI::dbGetQuery(
    con,
    paste0("SELECT count(*) AS n FROM clinvar_releases WHERE release_id = ", release_sql)
  )$n[[1L]]
  if (!identical(n_release, 1)) {
    stop("`release_id` is not an imported ClinVar release.", call. = FALSE)
  }

  rclinvarbitration_validate_profile(con, profile_id)
  profile_sql <- rclinvarbitration_sql_string(profile_id)
  policy_query <- if (length(submitter_exclusions)) {
    exclusion_sql <- paste(
      rclinvarbitration_sql_string(submitter_exclusions), collapse = ", "
    )
    rclinvarbitration_allele_policy_query(
      rclinvarbitration_policy_version(),
      profile_predicate = paste0("p.profile_id = ", profile_sql),
      submitter_exclusion_predicate = paste0(
        "c.submitter_normalized NOT IN (", exclusion_sql, ")"
      )
    )
  } else {
    NULL
  }
  select_sql <- rclinvarbitration_compatibility_select_sql(
    release_sql = release_sql,
    assembly_sql = assembly_sql,
    profile_sql = profile_sql,
    policy_query = policy_query
  )
  n_rows <- DBI::dbGetQuery(con, paste0("SELECT count(*) AS n FROM (", select_sql, ")"))$n[[1L]]
  DBI::dbExecute(
    con,
    paste0(
      "COPY (", select_sql,
      ") TO ", rclinvarbitration_sql_string(path),
      " (FORMAT PARQUET, COMPRESSION ZSTD)"
    )
  )
  invisible(list(
    path = path,
    rows = n_rows,
    release_id = release_id,
    assembly = assembly,
    profile_id = profile_id,
    submitter_exclusions = submitter_exclusions,
    policy_version = rclinvarbitration_policy_version()
  ))
}
