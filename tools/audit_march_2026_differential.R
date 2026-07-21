#!/usr/bin/env Rscript
# Rebuild the source-row receipts reported in docs/ERRATA.md.
# Prerequisites: an installed source checkout, DuckDB, the three March sources,
# and the XML/flat seven-column Parquet outputs in the cache directory.
suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
  library(RClinVarbitration)
})

cache <- Sys.getenv(
  "RCLINVAR_AUDIT_CACHE",
  file.path(tools::R_user_dir("RClinVarbitration", "cache"))
)
repo <- normalizePath(Sys.getenv("RCLINVAR_AUDIT_REPO", "."), mustWork = TRUE)
audit_dir <- file.path(repo, "inst", "audits")
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
paths <- c(
  xml_source = file.path(cache, "ClinVarVCVRelease_2026-03.xml.gz"),
  submission_source = file.path(cache, "submission_summary_2026-03.txt.gz"),
  variant_source = file.path(cache, "variant_summary_2026-03.txt.gz"),
  xml_output = file.path(cache, "clinvar-vcv-2026-03-clinvarbitration-grch38.parquet"),
  flat_output = file.path(cache, "clinvar-flat-2026-03-clinvarbitration-grch38.parquet")
)
if (any(!file.exists(paths))) {
  stop("Missing audit inputs: ", paste(names(paths)[!file.exists(paths)], collapse = ", "))
}

con <- dbConnect(duckdb(
  dbdir = ":memory:",
  config = list(
    allow_unsigned_extensions = "true", threads = "12", memory_limit = "24GB",
    preserve_insertion_order = "false",
    temp_directory = file.path(cache, "march-2026-audit-tmp")
  )
))
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
rclinvarbitration_enable(con)
q <- function(x) as.character(dbQuoteString(con, x))
key <- "contig, position, reference, alternate, allele_id"

dbExecute(con, paste0("CREATE TABLE xml_output AS SELECT * FROM read_parquet(", q(paths[["xml_output"]]), ")"))
dbExecute(con, paste0("CREATE TABLE flat_output AS SELECT * FROM read_parquet(", q(paths[["flat_output"]]), ")"))
dbExecute(con, paste0(
  "CREATE TABLE key_audit0 AS ",
  "SELECT 'xml_only' difference_type, x.*, NULL::VARCHAR flat_classification, ",
  "NULL::INTEGER flat_stars FROM xml_output x ANTI JOIN flat_output f USING (", key, ") ",
  "UNION ALL SELECT 'flat_only', f.*, f.clinical_significance, f.gold_stars ",
  "FROM flat_output f ANTI JOIN xml_output x USING (", key, ") ",
  "UNION ALL SELECT 'shared_disagreement', x.*, f.clinical_significance, f.gold_stars ",
  "FROM xml_output x JOIN flat_output f USING (", key, ") ",
  "WHERE x.clinical_significance <> f.clinical_significance OR x.gold_stars <> f.gold_stars"
))
dbExecute(con, paste0(
  "CREATE TABLE variants AS SELECT *, row_number() OVER () source_ordinal ",
  "FROM read_csv(", q(paths[["variant_source"]]),
  ", header=true, delim='\\t', quote='', all_varchar=true)"
))
dbExecute(con, "
  CREATE TABLE key_audit AS
  SELECT k.*, try_cast(v.\"VariationID\" AS UBIGINT) variation_id,
         v.source_ordinal variant_data_row,
         v.source_ordinal + 1 variant_physical_line,
         v.\"Type\" variant_type, v.\"Name\" variant_name
  FROM key_audit0 k
  JOIN variants v
    ON try_cast(v.\"#AlleleID\" AS INTEGER) = k.allele_id
   AND v.\"Assembly\" = 'GRCh38'
   AND try_cast(v.\"PositionVCF\" AS INTEGER) = k.position
   AND v.\"ReferenceAlleleVCF\" = k.reference
   AND v.\"AlternateAlleleVCF\" = k.alternate
   AND CASE WHEN v.\"Chromosome\" = 'MT' THEN 'chrM'
            ELSE 'chr' || v.\"Chromosome\" END = k.contig
")
dbExecute(con, paste0(
  "CREATE TABLE flat_submissions AS SELECT * FROM (SELECT *, row_number() OVER () source_ordinal ",
  "FROM read_csv(", q(paths[["submission_source"]]),
  ", skip=18, header=true, delim='\\t', quote='', all_varchar=true)) ",
  "WHERE try_cast(\"#VariationID\" AS UBIGINT) IN ",
  "(SELECT DISTINCT variation_id FROM key_audit)"
))

target_entities <- file.path(audit_dir, "march-2026-target-xml-entity-receipts.parquet")
if (file.exists(target_entities)) unlink(target_entities)
target_vcvs <- sprintf(
  "VCV%09d",
  dbGetQuery(con, "SELECT DISTINCT variation_id FROM key_audit ORDER BY variation_id")$variation_id
)
target_sql <- paste(vapply(target_vcvs, q, character(1)), collapse = ",")
dbExecute(con, paste0(
  "COPY (SELECT * FROM clinvar_xml_entities(", q(paths[["xml_source"]]), ") ",
  "WHERE vcv_accession IN (", target_sql, ")) TO ", q(target_entities),
  " (FORMAT PARQUET, COMPRESSION ZSTD)"
))
dbExecute(con, paste0("CREATE TABLE entities AS SELECT * FROM read_parquet(", q(target_entities), ")"))
dbExecute(con, "
  CREATE TABLE xml_variants AS
  SELECT vcv_accession,
         try_cast(json_extract_string(fields_json, '$.variation_id') AS UBIGINT) variation_id
  FROM entities WHERE entity_type = 'variation'
")
dbExecute(con, "
  CREATE TABLE xml_scvs AS
  SELECT v.variation_id, e.vcv_accession, e.record_ordinal,
         e.entity_ordinal xml_entity_ordinal, e.entity_id assertion_entity_id,
         json_extract_string(e.fields_json, '$.scv_accession') scv_accession,
         try_cast(json_extract_string(e.fields_json, '$.scv_version') AS INTEGER) scv_version,
         json_extract_string(e.fields_json, '$.classification') xml_classification,
         json_extract_string(e.fields_json, '$.review_status') xml_review_status,
         json_extract_string(e.fields_json, '$.date_last_evaluated') xml_date_last_evaluated,
         json_extract_string(e.fields_json, '$.submitter_name') xml_submitter,
         json_extract_string(e.fields_json, '$.contributes_to_aggregate_classification')
           xml_contributes_to_aggregate_classification,
         e.fields_json xml_fields_json
  FROM entities e JOIN xml_variants v USING (vcv_accession)
  WHERE e.entity_type = 'scv_assertion'
")

key_receipt <- dbGetQuery(con, "
  WITH flat_summary AS (
    SELECT try_cast(\"#VariationID\" AS UBIGINT) variation_id,
           count(*) flat_submission_rows,
           string_agg(cast(source_ordinal + 19 AS VARCHAR), ';' ORDER BY source_ordinal)
             flat_submission_physical_lines,
           string_agg(\"SCV\", ';' ORDER BY source_ordinal) flat_scvs,
           string_agg(\"ClinicalSignificance\", ';' ORDER BY source_ordinal)
             flat_source_classifications,
           string_agg(\"ReviewStatus\", ';' ORDER BY source_ordinal)
             flat_source_review_statuses
    FROM flat_submissions GROUP BY 1
  ), xml_summary AS (
    SELECT variation_id, any_value(vcv_accession) vcv_accession,
           min(record_ordinal) xml_record_ordinal, count(*) xml_scv_rows,
           string_agg(cast(xml_entity_ordinal AS VARCHAR), ';' ORDER BY xml_entity_ordinal)
             xml_scv_entity_ordinals,
           string_agg(scv_accession || '.' || cast(scv_version AS VARCHAR), ';'
                      ORDER BY xml_entity_ordinal) xml_scvs,
           string_agg(coalesce(xml_classification, 'NULL'), ';' ORDER BY xml_entity_ordinal)
             xml_source_classifications,
           string_agg(xml_review_status, ';' ORDER BY xml_entity_ordinal)
             xml_source_review_statuses
    FROM xml_scvs GROUP BY variation_id
  )
  SELECT k.*,
    CASE
      WHEN difference_type = 'flat_only' AND variation_id IN (633845, 633881)
        THEN 'compound_child_location_excluded_by_top_level_allele_export'
      WHEN difference_type = 'flat_only' AND variation_id BETWEEN 6633 AND 6636
        THEN 'source_vocabulary_divergence_flat_pathogenic_xml_affects_unbinned'
      WHEN difference_type = 'flat_only' AND variation_id = 43688
        THEN 'source_vocabulary_divergence_flat_benign_xml_no_known_pathogenicity_unbinned'
      WHEN difference_type = 'shared_disagreement' AND variation_id = 548128
        THEN 'flat_duplicate_same_scv_rows_with_divergent_classifications_xml_single_assertion'
      ELSE 'flat_missing_germline_classification_xml_has_current_classification'
    END audit_classification,
    x.vcv_accession, x.xml_record_ordinal,
    f.* EXCLUDE (variation_id), x.* EXCLUDE (variation_id, vcv_accession, xml_record_ordinal)
  FROM key_audit k
  LEFT JOIN flat_summary f USING (variation_id)
  LEFT JOIN xml_summary x USING (variation_id)
  ORDER BY difference_type, contig, position, allele_id
")
flat_receipt <- dbGetQuery(con, "
  SELECT try_cast(\"#VariationID\" AS UBIGINT) variation_id,
         source_ordinal submission_data_row,
         source_ordinal + 19 submission_physical_line,
         \"ClinicalSignificance\" clinical_significance,
         \"DateLastEvaluated\" date_last_evaluated,
         \"ReviewStatus\" review_status, \"Submitter\" submitter, \"SCV\" scv,
         \"ContributesToAggregateClassification\" contributes_to_aggregate_classification,
         \"SubmittedPhenotypeInfo\" submitted_phenotype_info,
         \"ReportedPhenotypeInfo\" reported_phenotype_info,
         \"CollectionMethod\" collection_method, \"OriginCounts\" origin_counts,
         \"SubmittedGeneSymbol\" submitted_gene_symbol
  FROM flat_submissions ORDER BY variation_id, source_ordinal
")
xml_receipt <- dbGetQuery(con, "SELECT * FROM xml_scvs ORDER BY variation_id, xml_entity_ordinal")
flat_receipt$submission_source_sha256 <- "dfc875bc831292b857d8d0a85eb57157452e12f04fbc3591addbf59208de727f"
xml_receipt$xml_source_sha256 <- "8c369922c38958bdba0c99225d2db794cd02995930b98cfce7a4754faf65f7c8"
write_gzip_csv <- function(data, path) {
  connection <- gzfile(path, "wb")
  on.exit(close(connection), add = TRUE)
  write.csv(data, connection, row.names = FALSE, na = "")
}
write_gzip_csv(key_receipt, file.path(audit_dir, "march-2026-key-difference-receipts.csv.gz"))
write_gzip_csv(flat_receipt, file.path(audit_dir, "march-2026-flat-submission-receipts.csv.gz"))
write_gzip_csv(xml_receipt, file.path(audit_dir, "march-2026-xml-scv-receipts.csv.gz"))
stopifnot(nrow(key_receipt) == 377L, nrow(flat_receipt) == 422L, nrow(xml_receipt) == 438L)
print(with(key_receipt, table(difference_type, audit_classification)))
