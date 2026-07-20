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

facts <- DBI::dbGetQuery(con, paste0(
  "SELECT * FROM clinvar_xml_facts(", fixture_sql, ") ORDER BY fact_ordinal"
))
expect_true(nrow(facts) > 100L)
expect_true(nrow(facts) < 2000L)
expect_false(any(grepl("clinvar:xml", facts$entity_id, fixed = TRUE)))
expect_equal(unique(facts$vcv_accession), "VCV000091629")
expect_equal(length(unique(facts$entity_id[facts$entity_type == "variation"])), 1L)
expect_equal(length(unique(facts$entity_id[facts$entity_type == "rcv_assertion"])), 4L)
expect_equal(length(unique(facts$entity_id[facts$entity_type == "scv_assertion"])), 6L)
expect_true(any(facts$entity_type == "scv_assertion" & facts$field == "classification" & facts$value == "Pathogenic"))
expect_true(any(facts$entity_type == "text" & facts$field == "value" & grepl("splice", facts$value, ignore.case = TRUE)))

counts <- rclinvarbitration_import_xml(con, fixture, release_id = "fixture-vcv")
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
