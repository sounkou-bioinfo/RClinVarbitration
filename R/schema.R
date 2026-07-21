#' ClinVar relational schema SQL
#'
#' Returns DuckDB DDL for the focused ClinVar schema. Public identifiers and
#' domain relations are retained directly: VCV variants, alleles and assembly
#' locations, genes, RCV aggregates, SCV submissions, conditions, observations,
#' citations, attributes, and attributable discovery text. XML parser nodes are
#' not persisted. The release catalogue enforces its small primary key; the
#' release-scale analytical tables expose logical key columns without DuckDB
#' ART indexes so complete imports remain memory-bounded.
#'
#' @return A named character vector of SQL statements.
#' @export
rclinvarbitration_schema_sql <- function() {
  c(
    releases = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_releases (",
      "release_id TEXT PRIMARY KEY, source_path TEXT NOT NULL,",
      "imported_at TIMESTAMP NOT NULL DEFAULT current_timestamp)"
    ),
    variants = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_variants (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, vcv_version UINTEGER, variation_id UBIGINT,",
      "variation_name TEXT, variation_type TEXT, record_type TEXT, record_status TEXT,",
      "species TEXT, date_created DATE, date_last_updated DATE, most_recent_submission DATE,",
      "number_of_submissions UINTEGER, number_of_submitters UINTEGER,",
      "aggregate_classification TEXT, aggregate_review_status TEXT,",
      "aggregate_date_last_evaluated DATE)"
    ),
    alleles = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_alleles (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, allele_entity_id TEXT NOT NULL,",
      "parent_allele_entity_id TEXT, allele_id UBIGINT, variation_id UBIGINT,",
      "name TEXT, variant_type TEXT, canonical_spdi TEXT)"
    ),
    locations = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_locations (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, allele_entity_id TEXT NOT NULL, location_id TEXT NOT NULL,",
      "assembly TEXT, assembly_accession_version TEXT, assembly_status TEXT,",
      "chromosome TEXT, sequence_accession TEXT, start UBIGINT, stop UBIGINT,",
      "position_vcf UBIGINT, reference_allele_vcf TEXT, alternate_allele_vcf TEXT,",
      "for_display BOOLEAN)"
    ),
    genes = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_genes (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, allele_entity_id TEXT NOT NULL, gene_entity_id TEXT NOT NULL,",
      "gene_id UBIGINT, symbol TEXT, hgnc_id TEXT, full_name TEXT,",
      "relationship_type TEXT, source TEXT)"
    ),
    rcvs = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_rcv_assertions (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, rcv_accession TEXT NOT NULL, rcv_version UINTEGER,",
      "title TEXT, classification TEXT, review_status TEXT,",
      "date_last_evaluated DATE, submission_count UINTEGER)"
    ),
    scvs = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_scv_assertions (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL, source_ordinal UBIGINT,",
      "vcv_accession TEXT NOT NULL, assertion_entity_id TEXT NOT NULL, assertion_id UBIGINT,",
      "scv_accession TEXT, scv_version UINTEGER, submitter_name TEXT, submitter_id UBIGINT,",
      "organization_category TEXT, organization_abbreviation TEXT, local_key TEXT,",
      "submitted_assembly TEXT, submission_title TEXT, assertion_type TEXT, record_status TEXT,",
      "classification TEXT, review_status TEXT, date_last_evaluated DATE,",
      "submission_date DATE, date_created DATE, date_last_updated DATE,",
      "contributes_to_aggregate_classification BOOLEAN)"
    ),
    scv_source_ordinal = "ALTER TABLE clinvar_scv_assertions ADD COLUMN IF NOT EXISTS source_ordinal UBIGINT",
    conditions = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_conditions (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, rcv_entity_id TEXT, scv_entity_id TEXT,",
      "condition_id TEXT NOT NULL, context_type TEXT NOT NULL, context_id TEXT NOT NULL,",
      "trait_id TEXT, trait_type TEXT, trait_set_id TEXT, trait_set_type TEXT,",
      "preferred_name TEXT, database_name TEXT, database_id TEXT,",
      "contributes_to_aggregate_classification BOOLEAN)"
    ),
    condition_names = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_condition_names (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, rcv_entity_id TEXT, scv_entity_id TEXT,",
      "condition_id TEXT NOT NULL, name_id TEXT NOT NULL, name_type TEXT, name TEXT NOT NULL)"
    ),
    xrefs = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_xrefs (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, rcv_entity_id TEXT, scv_entity_id TEXT,",
      "context_type TEXT NOT NULL, context_id TEXT NOT NULL, xref_id TEXT NOT NULL,",
      "database_name TEXT, database_id TEXT, xref_type TEXT)"
    ),
    observations = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_observations (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, scv_entity_id TEXT NOT NULL, observation_id TEXT NOT NULL,",
      "origin TEXT, species TEXT, affected_status TEXT, number_tested UINTEGER, method_type TEXT)"
    ),
    citations = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_citations (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, rcv_entity_id TEXT, scv_entity_id TEXT,",
      "citation_id TEXT NOT NULL, context_type TEXT NOT NULL, context_id TEXT NOT NULL,",
      "citation_type TEXT, abbreviation TEXT, url TEXT)"
    ),
    citation_identifiers = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_citation_identifiers (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, rcv_entity_id TEXT, scv_entity_id TEXT,",
      "citation_id TEXT NOT NULL, identifier_entity_id TEXT NOT NULL,",
      "source TEXT, identifier TEXT NOT NULL)"
    ),
    attributes = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_attributes (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, rcv_entity_id TEXT, scv_entity_id TEXT,",
      "attribute_id TEXT NOT NULL, context_type TEXT NOT NULL, context_id TEXT NOT NULL,",
      "attribute_type TEXT, integer_value BIGINT, value TEXT)"
    ),
    text = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_text (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL, ordinal UBIGINT NOT NULL,",
      "document_id TEXT NOT NULL, vcv_accession TEXT NOT NULL,",
      "rcv_entity_id TEXT, scv_entity_id TEXT, context_type TEXT NOT NULL, context_id TEXT NOT NULL,",
      "section TEXT NOT NULL, text TEXT NOT NULL)"
    ),
    policy_profiles = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_policy_profiles (",
      "policy_version TEXT NOT NULL, profile_id TEXT NOT NULL, description TEXT,",
      "PRIMARY KEY (policy_version, profile_id))"
    ),
    policy_exclusions = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_policy_submitter_exclusions (",
      "policy_version TEXT NOT NULL, profile_id TEXT NOT NULL,",
      "submitter_name TEXT NOT NULL, classification_bin TEXT, reason TEXT)"
    ),
    default_policy_profile = paste0(
      "INSERT INTO clinvar_policy_profiles ",
      "SELECT '", rclinvarbitration_policy_version(), "', 'default', ",
      "'CPG ClinVarbitration 2.2.11 defaults, adapted per disease' ",
      "WHERE NOT EXISTS (SELECT 1 FROM clinvar_policy_profiles WHERE policy_version = '",
      rclinvarbitration_policy_version(), "' AND profile_id = 'default')"
    ),
    normalized_alleles = paste(
      "CREATE OR REPLACE VIEW clinvar_normalized_alleles AS SELECT",
      "a.release_id, a.vcv_accession, a.allele_id, a.variation_id,",
      "l.assembly, l.chromosome, l.position_vcf,",
      "l.reference_allele_vcf AS reference, l.alternate_allele_vcf AS alternate,",
      "a.canonical_spdi FROM clinvar_alleles a JOIN clinvar_locations l",
      "ON l.release_id = a.release_id AND l.allele_entity_id = a.allele_entity_id",
      "WHERE l.position_vcf IS NOT NULL AND l.reference_allele_vcf IS NOT NULL",
      "AND l.alternate_allele_vcf IS NOT NULL"
    ),
    disease_aggregates = paste(
      "CREATE OR REPLACE VIEW clinvar_disease_aggregates AS SELECT",
      "r.release_id, r.vcv_accession, v.variation_id, a.allele_id,",
      "r.rcv_accession, r.rcv_version, r.title AS rcv_title,",
      "c.condition_id, c.trait_set_id, c.database_name AS disease_database,",
      "c.database_id AS disease_identifier, c.preferred_name AS disease_name,",
      "CASE WHEN c.database_name IS NOT NULL AND c.database_id IS NOT NULL",
      "THEN lower(trim(c.database_name)) || ':' || trim(c.database_id)",
      "WHEN c.trait_set_id IS NOT NULL THEN 'clinvar-trait-set:' || c.trait_set_id",
      "WHEN c.preferred_name IS NOT NULL THEN 'name:' || lower(trim(c.preferred_name))",
      "ELSE 'condition:' || c.condition_id END AS disease_key,",
      "r.classification AS aggregate_classification,",
      "r.review_status AS aggregate_review_status,",
      "r.date_last_evaluated AS aggregate_date_last_evaluated,",
      "r.submission_count FROM clinvar_rcv_assertions r",
      "JOIN clinvar_variants v USING (release_id, vcv_accession)",
      "LEFT JOIN clinvar_alleles a ON a.release_id = r.release_id",
      "AND a.vcv_accession = r.vcv_accession AND a.parent_allele_entity_id IS NULL",
      "LEFT JOIN clinvar_conditions c ON c.release_id = r.release_id",
      "AND c.context_type = 'rcv_assertion' AND c.context_id = r.rcv_accession"
    ),
    disease_submissions = paste(
      "CREATE OR REPLACE VIEW clinvar_disease_submissions AS WITH names AS (",
      "SELECT release_id, condition_id,",
      "coalesce(max(name) FILTER (WHERE lower(name_type) = 'preferred'), max(name)) AS disease_name",
      "FROM clinvar_condition_names GROUP BY release_id, condition_id),",
      "canonical_xrefs AS (SELECT release_id, context_id, database_name, database_id",
      "FROM clinvar_xrefs WHERE context_type = 'condition' AND lower(database_name) IN",
      "('medgen', 'mondo', 'omim', 'orphanet', 'mesh', 'umls', 'omim phenotypic series')",
      "QUALIFY row_number() OVER (PARTITION BY release_id, context_id ORDER BY",
      "CASE lower(database_name) WHEN 'medgen' THEN 0 WHEN 'mondo' THEN 1",
      "WHEN 'omim' THEN 2 WHEN 'orphanet' THEN 3 WHEN 'mesh' THEN 4",
      "WHEN 'umls' THEN 5 ELSE 6 END, database_name, database_id, xref_id) = 1),",
      "linked AS (SELECT s.release_id, s.vcv_accession, v.variation_id, a.allele_id,",
      "s.assertion_entity_id, s.scv_accession, s.scv_version, s.assertion_id, s.source_ordinal,",
      "s.submitter_name, s.submitter_id, s.classification, s.review_status,",
      "s.date_last_evaluated, s.submission_date, s.contributes_to_aggregate_classification,",
      "c.condition_id, c.trait_set_id,",
      "coalesce(c.database_name, x.database_name) AS disease_database,",
      "coalesce(c.database_id, x.database_id) AS disease_identifier,",
      "coalesce(c.preferred_name, n.disease_name) AS disease_name",
      "FROM clinvar_scv_assertions s JOIN clinvar_variants v USING (release_id, vcv_accession)",
      "LEFT JOIN clinvar_alleles a ON a.release_id = s.release_id",
      "AND a.vcv_accession = s.vcv_accession AND a.parent_allele_entity_id IS NULL",
      "JOIN clinvar_conditions c ON c.release_id = s.release_id",
      "AND c.context_type = 'scv_assertion' AND c.context_id = s.assertion_entity_id",
      "LEFT JOIN names n ON n.release_id = c.release_id AND n.condition_id = c.condition_id",
      "LEFT JOIN canonical_xrefs x ON x.release_id = c.release_id AND x.context_id = c.condition_id)",
      "SELECT linked.*, CASE WHEN disease_database IS NOT NULL AND disease_identifier IS NOT NULL",
      "THEN lower(trim(disease_database)) || ':' || trim(disease_identifier)",
      "WHEN trait_set_id IS NOT NULL THEN 'clinvar-trait-set:' || trait_set_id",
      "WHEN disease_name IS NOT NULL THEN 'name:' || lower(trim(disease_name))",
      "ELSE 'condition:' || condition_id END AS disease_key FROM linked"
    ),
    rclinvarbitration_policy_sql()
  )
}

#' Initialize the ClinVar relational schema
#'
#' @param con A DuckDB DBI connection.
#' @return `con`, invisibly.
#' @export
rclinvarbitration_init <- function(con) {
  for (statement in unname(rclinvarbitration_schema_sql())) DBI::dbExecute(con, statement)
  invisible(con)
}

rclinvarbitration_entity_insert_sql <- function(table, entity_type, select_sql) {
  paste0(
    "INSERT INTO ", table, " ", select_sql,
    " FROM rclinvarbitration_import_entities WHERE entity_type = '", entity_type, "'"
  )
}

rclinvarbitration_import_statements <- function(release_sql) {
  field <- function(name) paste0("json_extract_string(fields_json, '$.", name, "')")
  c(
    variants = rclinvarbitration_entity_insert_sql(
      "clinvar_variants", "variation",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession,",
        "try_cast(", field("version"), " AS UINTEGER),",
        "try_cast(", field("variation_id"), " AS UBIGINT),",
        field("variation_name"), ",", field("variation_type"), ",",
        field("record_type"), ",", field("record_status"), ",", field("species"), ",",
        "try_cast(", field("date_created"), " AS DATE),",
        "try_cast(", field("date_last_updated"), " AS DATE),",
        "try_cast(", field("most_recent_submission"), " AS DATE),",
        "try_cast(", field("number_of_submissions"), " AS UINTEGER),",
        "try_cast(", field("number_of_submitters"), " AS UINTEGER),",
        field("classification"), ",", field("review_status"), ",",
        "try_cast(", field("date_last_evaluated"), " AS DATE)"
      )
    ),
    alleles = rclinvarbitration_entity_insert_sql(
      "clinvar_alleles", "allele",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, entity_id,",
        "CASE WHEN parent_type = 'allele' THEN parent_id END,",
        "try_cast(", field("allele_id"), " AS UBIGINT),",
        "try_cast(", field("variation_id"), " AS UBIGINT),",
        field("name"), ",", field("variant_type"), ",", field("canonical_spdi")
      )
    ),
    locations = rclinvarbitration_entity_insert_sql(
      "clinvar_locations", "location",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, parent_id, entity_id,",
        field("assembly"), ",", field("assembly_accession_version"), ",",
        field("assembly_status"), ",", field("chr"), ",", field("accession"), ",",
        "try_cast(", field("start"), " AS UBIGINT), try_cast(", field("stop"), " AS UBIGINT),",
        "try_cast(", field("position_vcf"), " AS UBIGINT),",
        field("reference_allele_vcf"), ",", field("alternate_allele_vcf"), ",",
        "try_cast(", field("for_display"), " AS BOOLEAN)"
      )
    ),
    genes = rclinvarbitration_entity_insert_sql(
      "clinvar_genes", "gene",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, parent_id, entity_id,",
        "try_cast(", field("gene_id"), " AS UBIGINT),", field("symbol"), ",",
        field("hgnc_id"), ",", field("full_name"), ",",
        field("relationship_type"), ",", field("source")
      )
    ),
    rcvs = rclinvarbitration_entity_insert_sql(
      "clinvar_rcv_assertions", "rcv_assertion",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, entity_id,",
        "try_cast(", field("version"), " AS UINTEGER),", field("title"), ",",
        field("classification"), ",", field("review_status"), ",",
        "try_cast(", field("date_last_evaluated"), " AS DATE),",
        "try_cast(", field("submission_count"), " AS UINTEGER)"
      )
    ),
    scvs = rclinvarbitration_entity_insert_sql(
      "clinvar_scv_assertions", "scv_assertion",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, entity_ordinal, vcv_accession, entity_id,",
        "try_cast(", field("id"), " AS UBIGINT),", field("scv_accession"), ",",
        "try_cast(", field("scv_version"), " AS UINTEGER),", field("submitter_name"), ",",
        "try_cast(", field("submitter_id"), " AS UBIGINT),", field("organization_category"), ",",
        field("organization_abbreviation"), ",", field("local_key"), ",",
        field("submitted_assembly"), ",", field("submission_title"), ",",
        field("assertion_type"), ",", field("record_status"), ",",
        field("classification"), ",", field("review_status"), ",",
        "try_cast(", field("date_last_evaluated"), " AS DATE),",
        "try_cast(", field("submission_date"), " AS DATE),",
        "try_cast(", field("date_created"), " AS DATE),",
        "try_cast(", field("date_last_updated"), " AS DATE),",
        "try_cast(", field("contributes_to_aggregate_classification"), " AS BOOLEAN)"
      )
    ),
    conditions = rclinvarbitration_entity_insert_sql(
      "clinvar_conditions", "condition",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id,",
        "entity_id, parent_type, parent_id,", field("id"), ",", field("type"), ",",
        field("trait_set_id"), ",", field("trait_set_type"), ",",
        field("preferred_name"), ",", field("db"), ",", field("id"), ",",
        "try_cast(", field("contributes_to_aggregate_classification"), " AS BOOLEAN)"
      )
    ),
    condition_names = rclinvarbitration_entity_insert_sql(
      "clinvar_condition_names", "condition_name",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id,",
        "parent_id, entity_id,", field("type"), ",", field("value")
      )
    ),
    xrefs = rclinvarbitration_entity_insert_sql(
      "clinvar_xrefs", "xref",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id,",
        "parent_type, parent_id, entity_id,", field("db"), ",", field("id"), ",", field("type")
      )
    ),
    observations = rclinvarbitration_entity_insert_sql(
      "clinvar_observations", "observation",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, scv_entity_id, entity_id,",
        field("origin"), ",", field("species"), ",", field("affected_status"), ",",
        "try_cast(", field("number_tested"), " AS UINTEGER),", field("method_type")
      )
    ),
    citations = rclinvarbitration_entity_insert_sql(
      "clinvar_citations", "citation",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id,",
        "entity_id, parent_type, parent_id,", field("type"), ",", field("abbrev"), ",", field("url")
      )
    ),
    citation_identifiers = rclinvarbitration_entity_insert_sql(
      "clinvar_citation_identifiers", "citation_identifier",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id,",
        "parent_id, entity_id,", field("source"), ",", field("identifier")
      )
    ),
    attributes = rclinvarbitration_entity_insert_sql(
      "clinvar_attributes", "attribute",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id,",
        "entity_id, parent_type, parent_id,", field("type"), ",",
        "try_cast(", field("integer_value"), " AS BIGINT),", field("value")
      )
    ),
    text_elements = rclinvarbitration_entity_insert_sql(
      "clinvar_text", "text",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, entity_ordinal, entity_id, vcv_accession,",
        "rcv_entity_id, scv_entity_id, parent_type, parent_id,",
        "coalesce(", field("section"), ", 'text'),", field("value")
      )
    ),
    text_condition_names = paste0(
      "INSERT INTO clinvar_text SELECT release_id, record_ordinal, 0, name_id, vcv_accession,",
      "rcv_entity_id, scv_entity_id, 'condition', condition_id,",
      "'condition_name:' || coalesce(name_type, 'unspecified'), name ",
      "FROM clinvar_condition_names WHERE release_id = ", release_sql
    ),
    text_condition_preferred = paste0(
      "INSERT INTO clinvar_text SELECT release_id, record_ordinal, 0, condition_id || '#preferred_name',",
      "vcv_accession, rcv_entity_id, scv_entity_id, context_type, context_id,",
      "'condition_preferred_name', preferred_name FROM clinvar_conditions WHERE preferred_name IS NOT NULL ",
      "AND release_id = ", release_sql
    ),
    text_attributes = paste0(
      "INSERT INTO clinvar_text SELECT release_id, record_ordinal, 0, attribute_id, vcv_accession,",
      "rcv_entity_id, scv_entity_id, context_type, context_id,",
      "'attribute:' || coalesce(attribute_type, 'unspecified'), value ",
      "FROM clinvar_attributes WHERE value IS NOT NULL AND release_id = ", release_sql
    )
  )
}

#' Stream a ClinVar VCV XML release into relational DuckDB tables
#'
#' The native extension reads `.xml` and `.xml.gz` with a libxml2 forward
#' reader. One compact JSON-backed row per selected ClinVar entity is written to
#' a disk-backed staging table in one XML pass, projected into the public
#' ClinVar relations without an EAV pivot, and dropped. No XML DOM, XML blob,
#' generic parser-node graph, or R data-frame materialization is used. Each
#' public relation is committed independently, the release catalogue row marks
#' completion, and failed imports remove partial rows for `release_id`.
#'
#' @param con A DuckDB DBI connection.
#' @param path Path to an official ClinVar VCV XML or XML.GZ release.
#' @param release_id User-supplied release label stored with every row.
#' @param replace Replace rows already stored for `release_id`?
#' @return A named numeric vector with imported entity counts.
#' @export
rclinvarbitration_import_xml <- function(con, path, release_id, replace = FALSE) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path)) {
    stop("`path` must name an existing ClinVar XML or XML.GZ file.", call. = FALSE)
  }
  if (!is.character(release_id) || length(release_id) != 1L || is.na(release_id) || !nzchar(release_id)) {
    stop("`release_id` must be a non-empty character scalar.", call. = FALSE)
  }
  if (!is.logical(replace) || length(replace) != 1L || is.na(replace)) {
    stop("`replace` must be TRUE or FALSE.", call. = FALSE)
  }
  rclinvarbitration_init(con)
  release_sql <- rclinvarbitration_sql_string(release_id)
  source_path <- normalizePath(path, mustWork = TRUE)
  path_sql <- rclinvarbitration_sql_string(source_path)
  existing <- DBI::dbGetQuery(
    con,
    paste0("SELECT count(*) AS n FROM clinvar_releases WHERE release_id = ", release_sql)
  )$n[[1L]]
  if (existing > 0 && !replace) {
    stop("`release_id` already exists; use `replace = TRUE` to replace it.", call. = FALSE)
  }

  tables <- c(
    "clinvar_text", "clinvar_attributes", "clinvar_citation_identifiers", "clinvar_citations",
    "clinvar_observations", "clinvar_xrefs", "clinvar_condition_names", "clinvar_conditions",
    "clinvar_scv_assertions", "clinvar_rcv_assertions", "clinvar_genes", "clinvar_locations",
    "clinvar_alleles", "clinvar_variants", "clinvar_releases"
  )
  staging_table <- "rclinvarbitration_import_entities"
  import_started <- FALSE
  import_complete <- FALSE
  delete_release <- function() {
    for (table in tables) {
      DBI::dbExecute(con, paste0("DELETE FROM ", table, " WHERE release_id = ", release_sql))
    }
  }
  on.exit({
    if (import_started && !import_complete) {
      for (table in tables) {
        try(
          DBI::dbExecute(con, paste0("DELETE FROM ", table, " WHERE release_id = ", release_sql)),
          silent = TRUE
        )
      }
    }
    try(DBI::dbExecute(con, paste("DROP TABLE IF EXISTS", staging_table)), silent = TRUE)
  }, add = TRUE)

  # Materialize before mutating an existing release. On a file-backed
  # connection this keeps the potentially large staging relation on disk.
  DBI::dbExecute(con, paste("DROP TABLE IF EXISTS", staging_table))
  DBI::dbExecute(
    con,
    paste0("CREATE TABLE ", staging_table, " AS SELECT * FROM clinvar_xml_entities(", path_sql, ")")
  )

  # Each projection commits independently. A release catalogue row is written
  # only after every relation succeeds, and the on-exit cleanup removes partial
  # rows after an error. This avoids retaining an entire ClinVar release in one
  # DuckDB transaction.
  import_started <- TRUE
  # Clear both a complete replaced release and any rows left by a process that
  # was terminated before its release catalogue marker could be written.
  delete_release()
  for (statement in rclinvarbitration_import_statements(release_sql)) DBI::dbExecute(con, statement)
  DBI::dbExecute(
    con,
    paste0("INSERT INTO clinvar_releases (release_id, source_path) VALUES (", release_sql, ", ", path_sql, ")")
  )
  import_complete <- TRUE
  DBI::dbExecute(con, paste("DROP TABLE", staging_table))

  count_tables <- c(
    variants = "clinvar_variants",
    alleles = "clinvar_alleles",
    rcv_assertions = "clinvar_rcv_assertions",
    scv_assertions = "clinvar_scv_assertions",
    conditions = "clinvar_conditions",
    observations = "clinvar_observations",
    citations = "clinvar_citations",
    text = "clinvar_text"
  )
  vapply(count_tables, function(table) {
    DBI::dbGetQuery(
      con,
      paste0("SELECT count(*) AS n FROM ", table, " WHERE release_id = ", release_sql)
    )$n[[1L]]
  }, numeric(1))
}
