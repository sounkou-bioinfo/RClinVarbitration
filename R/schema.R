#' ClinVar relational schema SQL
#'
#' Returns DuckDB DDL for the focused ClinVar schema. Public identifiers and
#' domain relations are retained directly: VCV variants, alleles and assembly
#' locations, genes, RCV aggregates, SCV submissions, conditions, observations,
#' citations, attributes, and attributable discovery text. XML parser nodes are
#' not persisted.
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
      "aggregate_date_last_evaluated DATE,",
      "PRIMARY KEY (release_id, vcv_accession))"
    ),
    alleles = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_alleles (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, allele_entity_id TEXT NOT NULL,",
      "parent_allele_entity_id TEXT, allele_id UBIGINT, variation_id UBIGINT,",
      "name TEXT, variant_type TEXT, canonical_spdi TEXT,",
      "PRIMARY KEY (release_id, allele_entity_id))"
    ),
    locations = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_locations (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, allele_entity_id TEXT NOT NULL, location_id TEXT NOT NULL,",
      "assembly TEXT, assembly_accession_version TEXT, assembly_status TEXT,",
      "chromosome TEXT, sequence_accession TEXT, start UBIGINT, stop UBIGINT,",
      "position_vcf UBIGINT, reference_allele_vcf TEXT, alternate_allele_vcf TEXT,",
      "for_display BOOLEAN,",
      "PRIMARY KEY (release_id, location_id))"
    ),
    genes = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_genes (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, allele_entity_id TEXT NOT NULL, gene_entity_id TEXT NOT NULL,",
      "gene_id UBIGINT, symbol TEXT, hgnc_id TEXT, full_name TEXT,",
      "relationship_type TEXT, source TEXT,",
      "PRIMARY KEY (release_id, gene_entity_id))"
    ),
    rcvs = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_rcv_assertions (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, rcv_accession TEXT NOT NULL, rcv_version UINTEGER,",
      "title TEXT, classification TEXT, review_status TEXT,",
      "date_last_evaluated DATE, submission_count UINTEGER,",
      "PRIMARY KEY (release_id, rcv_accession))"
    ),
    scvs = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_scv_assertions (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, assertion_entity_id TEXT NOT NULL, assertion_id UBIGINT,",
      "scv_accession TEXT, scv_version UINTEGER, submitter_name TEXT, submitter_id UBIGINT,",
      "organization_category TEXT, organization_abbreviation TEXT, local_key TEXT,",
      "submitted_assembly TEXT, submission_title TEXT, assertion_type TEXT, record_status TEXT,",
      "classification TEXT, review_status TEXT, date_last_evaluated DATE,",
      "submission_date DATE, date_created DATE, date_last_updated DATE,",
      "contributes_to_aggregate_classification BOOLEAN,",
      "PRIMARY KEY (release_id, assertion_entity_id))"
    ),
    conditions = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_conditions (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, rcv_entity_id TEXT, scv_entity_id TEXT,",
      "condition_id TEXT NOT NULL, context_type TEXT NOT NULL, context_id TEXT NOT NULL,",
      "trait_id TEXT, trait_type TEXT, trait_set_id TEXT, trait_set_type TEXT,",
      "preferred_name TEXT, database_name TEXT, database_id TEXT,",
      "contributes_to_aggregate_classification BOOLEAN,",
      "PRIMARY KEY (release_id, condition_id))"
    ),
    condition_names = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_condition_names (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, rcv_entity_id TEXT, scv_entity_id TEXT,",
      "condition_id TEXT NOT NULL, name_id TEXT NOT NULL, name_type TEXT, name TEXT NOT NULL,",
      "PRIMARY KEY (release_id, name_id))"
    ),
    xrefs = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_xrefs (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, rcv_entity_id TEXT, scv_entity_id TEXT,",
      "context_type TEXT NOT NULL, context_id TEXT NOT NULL, xref_id TEXT NOT NULL,",
      "database_name TEXT, database_id TEXT, xref_type TEXT,",
      "PRIMARY KEY (release_id, xref_id))"
    ),
    observations = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_observations (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, scv_entity_id TEXT NOT NULL, observation_id TEXT NOT NULL,",
      "origin TEXT, species TEXT, affected_status TEXT, number_tested UINTEGER, method_type TEXT,",
      "PRIMARY KEY (release_id, observation_id))"
    ),
    citations = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_citations (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, rcv_entity_id TEXT, scv_entity_id TEXT,",
      "citation_id TEXT NOT NULL, context_type TEXT NOT NULL, context_id TEXT NOT NULL,",
      "citation_type TEXT, abbreviation TEXT, url TEXT,",
      "PRIMARY KEY (release_id, citation_id))"
    ),
    citation_identifiers = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_citation_identifiers (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, rcv_entity_id TEXT, scv_entity_id TEXT,",
      "citation_id TEXT NOT NULL, identifier_entity_id TEXT NOT NULL,",
      "source TEXT, identifier TEXT NOT NULL,",
      "PRIMARY KEY (release_id, identifier_entity_id))"
    ),
    attributes = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_attributes (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "vcv_accession TEXT NOT NULL, rcv_entity_id TEXT, scv_entity_id TEXT,",
      "attribute_id TEXT NOT NULL, context_type TEXT NOT NULL, context_id TEXT NOT NULL,",
      "attribute_type TEXT, integer_value BIGINT, value TEXT,",
      "PRIMARY KEY (release_id, attribute_id))"
    ),
    text = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_text (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL, ordinal UBIGINT NOT NULL,",
      "document_id TEXT NOT NULL, vcv_accession TEXT NOT NULL,",
      "rcv_entity_id TEXT, scv_entity_id TEXT, context_type TEXT NOT NULL, context_id TEXT NOT NULL,",
      "section TEXT NOT NULL, text TEXT NOT NULL,",
      "PRIMARY KEY (release_id, document_id))"
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
    variant_id_index = "CREATE INDEX IF NOT EXISTS clinvar_variants_variation_idx ON clinvar_variants (release_id, variation_id)",
    allele_id_index = "CREATE INDEX IF NOT EXISTS clinvar_alleles_id_idx ON clinvar_alleles (release_id, allele_id)",
    location_index = "CREATE INDEX IF NOT EXISTS clinvar_locations_locus_idx ON clinvar_locations (release_id, assembly, chromosome, position_vcf)",
    scv_index = "CREATE INDEX IF NOT EXISTS clinvar_scv_vcv_idx ON clinvar_scv_assertions (release_id, vcv_accession, classification)",
    condition_index = "CREATE INDEX IF NOT EXISTS clinvar_conditions_context_idx ON clinvar_conditions (release_id, context_type, context_id)",
    text_index = "CREATE INDEX IF NOT EXISTS clinvar_text_context_idx ON clinvar_text (release_id, scv_entity_id, section)"
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

rclinvarbitration_pivot_sql <- function(table, release_sql, entity_type, select_sql) {
  paste0(
    "INSERT INTO ", table, " ", select_sql,
    " FROM rclinvarbitration_import_facts WHERE entity_type = '", entity_type, "' ",
    "GROUP BY record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id, entity_id, parent_type, parent_id"
  )
}

rclinvarbitration_import_statements <- function(release_sql) {
  max_field <- function(field) paste0("max(value) FILTER (WHERE field = '", field, "')")
  c(
    variants = rclinvarbitration_pivot_sql(
      "clinvar_variants", release_sql, "variation",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession,",
        "try_cast(", max_field("version"), " AS UINTEGER),",
        "try_cast(", max_field("variation_id"), " AS UBIGINT),",
        max_field("variation_name"), ",", max_field("variation_type"), ",",
        max_field("record_type"), ",", max_field("record_status"), ",", max_field("species"), ",",
        "try_cast(", max_field("date_created"), " AS DATE),",
        "try_cast(", max_field("date_last_updated"), " AS DATE),",
        "try_cast(", max_field("most_recent_submission"), " AS DATE),",
        "try_cast(", max_field("number_of_submissions"), " AS UINTEGER),",
        "try_cast(", max_field("number_of_submitters"), " AS UINTEGER),",
        max_field("classification"), ",", max_field("review_status"), ",",
        "try_cast(", max_field("date_last_evaluated"), " AS DATE)"
      )
    ),
    alleles = rclinvarbitration_pivot_sql(
      "clinvar_alleles", release_sql, "allele",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, entity_id,",
        "CASE WHEN parent_type = 'allele' THEN parent_id END,",
        "try_cast(", max_field("allele_id"), " AS UBIGINT),",
        "try_cast(", max_field("variation_id"), " AS UBIGINT),",
        max_field("name"), ",", max_field("variant_type"), ",", max_field("canonical_spdi")
      )
    ),
    locations = rclinvarbitration_pivot_sql(
      "clinvar_locations", release_sql, "location",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, parent_id, entity_id,",
        max_field("assembly"), ",", max_field("assembly_accession_version"), ",",
        max_field("assembly_status"), ",", max_field("chr"), ",", max_field("accession"), ",",
        "try_cast(", max_field("start"), " AS UBIGINT), try_cast(", max_field("stop"), " AS UBIGINT),",
        "try_cast(", max_field("position_vcf"), " AS UBIGINT),",
        max_field("reference_allele_vcf"), ",", max_field("alternate_allele_vcf"), ",",
        "try_cast(", max_field("for_display"), " AS BOOLEAN)"
      )
    ),
    genes = rclinvarbitration_pivot_sql(
      "clinvar_genes", release_sql, "gene",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, parent_id, entity_id,",
        "try_cast(", max_field("gene_id"), " AS UBIGINT),", max_field("symbol"), ",",
        max_field("hgnc_id"), ",", max_field("full_name"), ",",
        max_field("relationship_type"), ",", max_field("source")
      )
    ),
    rcvs = rclinvarbitration_pivot_sql(
      "clinvar_rcv_assertions", release_sql, "rcv_assertion",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, entity_id,",
        "try_cast(", max_field("version"), " AS UINTEGER),", max_field("title"), ",",
        max_field("classification"), ",", max_field("review_status"), ",",
        "try_cast(", max_field("date_last_evaluated"), " AS DATE),",
        "try_cast(", max_field("submission_count"), " AS UINTEGER)"
      )
    ),
    scvs = rclinvarbitration_pivot_sql(
      "clinvar_scv_assertions", release_sql, "scv_assertion",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, entity_id,",
        "try_cast(", max_field("id"), " AS UBIGINT),", max_field("scv_accession"), ",",
        "try_cast(", max_field("scv_version"), " AS UINTEGER),", max_field("submitter_name"), ",",
        "try_cast(", max_field("submitter_id"), " AS UBIGINT),", max_field("organization_category"), ",",
        max_field("organization_abbreviation"), ",", max_field("local_key"), ",",
        max_field("submitted_assembly"), ",", max_field("submission_title"), ",",
        max_field("assertion_type"), ",", max_field("record_status"), ",",
        max_field("classification"), ",", max_field("review_status"), ",",
        "try_cast(", max_field("date_last_evaluated"), " AS DATE),",
        "try_cast(", max_field("submission_date"), " AS DATE),",
        "try_cast(", max_field("date_created"), " AS DATE),",
        "try_cast(", max_field("date_last_updated"), " AS DATE),",
        "try_cast(", max_field("contributes_to_aggregate_classification"), " AS BOOLEAN)"
      )
    ),
    conditions = rclinvarbitration_pivot_sql(
      "clinvar_conditions", release_sql, "condition",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id,",
        "entity_id, parent_type, parent_id,", max_field("id"), ",", max_field("type"), ",",
        max_field("trait_set_id"), ",", max_field("trait_set_type"), ",",
        max_field("preferred_name"), ",", max_field("db"), ",", max_field("id"), ",",
        "try_cast(", max_field("contributes_to_aggregate_classification"), " AS BOOLEAN)"
      )
    ),
    condition_names = rclinvarbitration_pivot_sql(
      "clinvar_condition_names", release_sql, "condition_name",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id,",
        "parent_id, entity_id,", max_field("type"), ",", max_field("value")
      )
    ),
    xrefs = rclinvarbitration_pivot_sql(
      "clinvar_xrefs", release_sql, "xref",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id,",
        "parent_type, parent_id, entity_id,", max_field("db"), ",", max_field("id"), ",", max_field("type")
      )
    ),
    observations = rclinvarbitration_pivot_sql(
      "clinvar_observations", release_sql, "observation",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, scv_entity_id, entity_id,",
        max_field("origin"), ",", max_field("species"), ",", max_field("affected_status"), ",",
        "try_cast(", max_field("number_tested"), " AS UINTEGER),", max_field("method_type")
      )
    ),
    citations = rclinvarbitration_pivot_sql(
      "clinvar_citations", release_sql, "citation",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id,",
        "entity_id, parent_type, parent_id,", max_field("type"), ",", max_field("abbrev"), ",", max_field("url")
      )
    ),
    citation_identifiers = rclinvarbitration_pivot_sql(
      "clinvar_citation_identifiers", release_sql, "citation_identifier",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id,",
        "parent_id, entity_id,", max_field("source"), ",", max_field("identifier")
      )
    ),
    attributes = rclinvarbitration_pivot_sql(
      "clinvar_attributes", release_sql, "attribute",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, vcv_accession, rcv_entity_id, scv_entity_id,",
        "entity_id, parent_type, parent_id,", max_field("type"), ",",
        "try_cast(", max_field("integer_value"), " AS BIGINT),", max_field("value")
      )
    ),
    text_elements = rclinvarbitration_pivot_sql(
      "clinvar_text", release_sql, "text",
      paste0(
        "SELECT ", release_sql, ", record_ordinal, min(fact_ordinal), entity_id, vcv_accession,",
        "rcv_entity_id, scv_entity_id, parent_type, parent_id,",
        "coalesce(", max_field("section"), ", 'text'),", max_field("value")
      )
    ),
    text_condition_names = paste0(
      "INSERT INTO clinvar_text SELECT release_id, record_ordinal, 0, name_id, vcv_accession,",
      "rcv_entity_id, scv_entity_id, 'condition', condition_id,",
      "'condition_name:' || coalesce(name_type, 'unspecified'), name ",
      "FROM clinvar_condition_names"
    ),
    text_condition_preferred = paste0(
      "INSERT INTO clinvar_text SELECT release_id, record_ordinal, 0, condition_id || '#preferred_name',",
      "vcv_accession, rcv_entity_id, scv_entity_id, context_type, context_id,",
      "'condition_preferred_name', preferred_name FROM clinvar_conditions WHERE preferred_name IS NOT NULL"
    ),
    text_attributes = paste0(
      "INSERT INTO clinvar_text SELECT release_id, record_ordinal, 0, attribute_id, vcv_accession,",
      "rcv_entity_id, scv_entity_id, context_type, context_id,",
      "'attribute:' || coalesce(attribute_type, 'unspecified'), value ",
      "FROM clinvar_attributes WHERE value IS NOT NULL"
    )
  )
}

#' Stream a ClinVar VCV XML release into relational DuckDB tables
#'
#' The native extension reads `.xml` and `.xml.gz` with a libxml2 forward
#' reader. A compact semantic-fact staging table is produced in one XML pass,
#' projected into the public ClinVar relations, and dropped. No XML DOM, XML
#' blob, generic parser-node graph, or R data-frame materialization is used.
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
  DBI::dbBegin(con)
  committed <- FALSE
  on.exit({
    if (!committed) try(DBI::dbRollback(con), silent = TRUE)
    try(DBI::dbExecute(con, "DROP TABLE IF EXISTS rclinvarbitration_import_facts"), silent = TRUE)
  }, add = TRUE)
  if (existing > 0) {
    for (table in tables) {
      DBI::dbExecute(con, paste0("DELETE FROM ", table, " WHERE release_id = ", release_sql))
    }
  }
  DBI::dbExecute(con, "DROP TABLE IF EXISTS rclinvarbitration_import_facts")
  DBI::dbExecute(
    con,
    paste0("CREATE TEMP TABLE rclinvarbitration_import_facts AS SELECT * FROM clinvar_xml_facts(", path_sql, ")")
  )
  for (statement in rclinvarbitration_import_statements(release_sql)) DBI::dbExecute(con, statement)
  DBI::dbExecute(
    con,
    paste0("INSERT INTO clinvar_releases (release_id, source_path) VALUES (", release_sql, ", ", path_sql, ")")
  )
  DBI::dbExecute(con, "DROP TABLE rclinvarbitration_import_facts")
  DBI::dbCommit(con)
  committed <- TRUE

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
