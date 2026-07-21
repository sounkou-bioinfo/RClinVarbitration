fixture <- system.file("extdata", "VCV_XML_VCV000091629.xml.gz", package = "RClinVarbitration")
expect_true(nzchar(fixture))
expect_true(file.exists(fixture))

supported_versions <- paste0("v1.5.", 0:4)
artifact_paths <- vapply(supported_versions, rclinvarbitration_extension_path, character(1))
expect_equal(basename(dirname(artifact_paths)), supported_versions)
expect_true(all(file.exists(artifact_paths)))
expect_error(rclinvarbitration_extension_path("v1.4.3"), "no artifact")

con <- DBI::dbConnect(duckdb::duckdb(config = list(allow_unsigned_extensions = "true")))
rclinvarbitration_enable(con)
fixture_sql <- as.character(DBI::dbQuoteString(con, fixture))

entities <- DBI::dbGetQuery(con, paste0(
  "SELECT * FROM clinvar_xml_entities(", fixture_sql, ") ORDER BY entity_ordinal"
))
expect_true(nrow(entities) > 50L)
expect_true(nrow(entities) < 500L)
expect_false(any(grepl("clinvar:xml", entities$entity_id, fixed = TRUE)))
expect_equal(unique(entities$vcv_accession), "VCV000091629")
expect_equal(sum(entities$entity_type == "variation"), 1L)
expect_equal(sum(entities$entity_type == "rcv_assertion"), 4L)
expect_equal(sum(entities$entity_type == "scv_assertion"), 6L)
expect_true(all(grepl("^\\{.*\\}$", entities$fields_json)))

selected_fields <- DBI::dbGetQuery(con, paste0(
  "SELECT entity_type, json_extract_string(fields_json, '$.classification') AS classification, ",
  "json_extract_string(fields_json, '$.value') AS value ",
  "FROM clinvar_xml_entities(", fixture_sql, ")"
))
expect_true(any(selected_fields$entity_type == "scv_assertion" & selected_fields$classification == "Pathogenic", na.rm = TRUE))
expect_true(any(selected_fields$entity_type == "text" & grepl("splice", selected_fields$value, ignore.case = TRUE), na.rm = TRUE))
expect_false(any(grepl("^CREATE INDEX", rclinvarbitration_schema_sql())))

# Rows from a process terminated before writing its completion marker are
# removed before a fresh import of the same release identifier.
rclinvarbitration_init(con)
DBI::dbExecute(con, "
  INSERT INTO clinvar_variants (release_id, record_ordinal, vcv_accession)
  VALUES ('fixture-vcv', 999, 'STALE')
")
counts <- rclinvarbitration_import_xml(con, fixture, release_id = "fixture-vcv")
expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM clinvar_variants WHERE vcv_accession = 'STALE'")$n, 0)
expect_equal(counts[["variants"]], 1)
expect_equal(counts[["alleles"]], 1)
expect_equal(counts[["rcv_assertions"]], 4)
expect_equal(counts[["scv_assertions"]], 6)
expect_equal(counts[["observations"]], 6)
expect_true(counts[["conditions"]] >= 10)
expect_true(counts[["citations"]] > 10)
expect_true(counts[["text"]] > 10)
expect_false("clinvar_statements" %in% DBI::dbListTables(con))

variant <- DBI::dbGetQuery(con, "
  SELECT vcv_accession, vcv_version, variation_id, variation_name,
         aggregate_classification, aggregate_review_status
  FROM clinvar_variants
")
expect_equal(variant$vcv_accession, "VCV000091629")
expect_equal(variant$vcv_version, 19L)
expect_equal(variant$variation_id, 91629)
expect_equal(variant$aggregate_classification, "Pathogenic/Likely pathogenic")
expect_equal(variant$aggregate_review_status, "criteria provided, multiple submitters, no conflicts")

alleles <- DBI::dbGetQuery(con, "
  SELECT allele_id, variation_id, canonical_spdi
  FROM clinvar_alleles
")
expect_equal(alleles$allele_id, 97106)
expect_equal(alleles$variation_id, 91629)
expect_equal(alleles$canonical_spdi, "NC_000017.11:43082401:A:C")

locations <- DBI::dbGetQuery(con, "
  SELECT assembly, chromosome, position_vcf, reference, alternate
  FROM clinvar_normalized_alleles ORDER BY assembly
")
expect_equal(locations$assembly, c("GRCh37", "GRCh38"))
expect_equal(locations$chromosome, c("17", "17"))
expect_equal(locations$position_vcf, c(41234419, 43082402))
expect_equal(locations$reference, c("A", "A"))
expect_equal(locations$alternate, c("C", "C"))

scvs <- DBI::dbGetQuery(con, "
  SELECT scv_accession, submitter_name, classification, review_status
  FROM clinvar_scv_assertions ORDER BY scv_accession
")
expect_equal(nrow(scvs), 6L)
expect_true("SCV003995313" %in% scvs$scv_accession)
expect_true(all(scvs$classification %in% c("Pathogenic", "Likely pathogenic")))
expect_true(any(scvs$submitter_name == "Ambry Genetics"))

disease_aggregates <- DBI::dbGetQuery(con, "
  SELECT rcv_accession, disease_database, disease_identifier,
         disease_name, aggregate_classification
  FROM clinvar_disease_aggregates ORDER BY rcv_accession
")
expect_equal(nrow(disease_aggregates), 4L)
expect_equal(disease_aggregates$disease_database, rep("MedGen", 4L))
expect_equal(
  disease_aggregates$disease_identifier,
  c("C2676676", "C3661900", "C0027672", "C0677776")
)
expect_true(all(nzchar(disease_aggregates$disease_name)))
expect_true(all(nzchar(disease_aggregates$aggregate_classification)))

disease_submissions <- DBI::dbGetQuery(con, "
  SELECT scv_accession, disease_database, disease_identifier, classification
  FROM clinvar_disease_submissions ORDER BY scv_accession
")
expect_equal(nrow(disease_submissions), 6L)
expect_equal(length(unique(disease_submissions$scv_accession)), 6L)
expect_true(any(disease_submissions$disease_identifier == "C0027672", na.rm = TRUE))

text <- DBI::dbGetQuery(con, "
  SELECT s.scv_accession, t.section, t.text
  FROM clinvar_text t
  LEFT JOIN clinvar_scv_assertions s
    ON s.release_id = t.release_id AND s.assertion_entity_id = t.scv_entity_id
")
expect_true(any(text$scv_accession == "SCV003995313" & grepl("splice", text$text, ignore.case = TRUE)))
expect_true(any(grepl("condition_name", text$section, fixed = TRUE)))
expect_true(all(text$text == trimws(text$text)))

expect_error(rclinvarbitration_import_xml(con, fixture, release_id = "fixture-vcv"), "already exists")
replaced <- rclinvarbitration_import_xml(con, fixture, release_id = "fixture-vcv", replace = TRUE)
expect_equal(replaced[["variants"]], 1)
expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM clinvar_releases")$n, 1)

DBI::dbDisconnect(con, shutdown = TRUE)
