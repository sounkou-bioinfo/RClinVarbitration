con <- DBI::dbConnect(duckdb::duckdb())
rclinvarbitration_init(con)

# The public condition identity remains stable when only a package-generated
# condition key and preferred label change between releases.
DBI::dbExecute(con, "
  INSERT INTO clinvar_variants
    (release_id, record_ordinal, vcv_accession, variation_id)
  VALUES ('release-old', 1, 'VCV000000101', 101),
         ('release-new', 1, 'VCV000000101', 101)
")
DBI::dbExecute(con, "
  INSERT INTO clinvar_alleles
    (release_id, record_ordinal, vcv_accession, allele_entity_id, allele_id)
  VALUES ('release-old', 1, 'VCV000000101', 'old-allele', 201),
         ('release-new', 1, 'VCV000000101', 'new-allele', 201)
")
DBI::dbExecute(con, "
  INSERT INTO clinvar_scv_assertions
    (release_id, record_ordinal, source_ordinal, vcv_accession,
     assertion_entity_id, scv_accession, scv_version, classification,
     review_status, date_last_evaluated)
  VALUES ('release-old', 1, 1, 'VCV000000101', 'old-assertion',
          'SCV000000101', 1, 'Pathogenic',
          'criteria provided, single submitter', DATE '2020-01-01'),
         ('release-new', 1, 1, 'VCV000000101', 'new-assertion',
          'SCV000000101', 2, 'Pathogenic',
          'criteria provided, single submitter', DATE '2024-01-01')
")
DBI::dbExecute(con, "
  INSERT INTO clinvar_conditions
    (release_id, record_ordinal, vcv_accession, scv_entity_id, condition_id,
     context_type, context_id, preferred_name)
  VALUES ('release-old', 1, 'VCV000000101', 'old-assertion', 'old-condition',
          'scv_assertion', 'old-assertion', 'Old disease label'),
         ('release-new', 1, 'VCV000000101', 'new-assertion', 'new-condition',
          'scv_assertion', 'new-assertion', 'Updated disease label')
")
DBI::dbExecute(con, "
  INSERT INTO clinvar_xrefs
    (release_id, record_ordinal, vcv_accession, scv_entity_id, context_type,
     context_id, xref_id, database_name, database_id)
  VALUES ('release-old', 1, 'VCV000000101', 'old-assertion', 'condition',
          'old-condition', 'old-xref', 'OMIM', '123456'),
         ('release-new', 1, 'VCV000000101', 'new-assertion', 'condition',
          'new-condition', 'new-xref', 'OMIM', '123456')
")
stable_keys <- DBI::dbGetQuery(con, "
  SELECT release_id, disease_key
  FROM clinvar_disease_submissions
  WHERE vcv_accession = 'VCV000000101'
  ORDER BY release_id
")
expect_equal(stable_keys$disease_key, c("omim:123456", "omim:123456"))

# A replacement SCV version is reduced to the highest version for the same
# assertion identity. A withdrawn assertion is present in the old release and
# absent, rather than silently carried forward, in the new release.
DBI::dbExecute(con, "
  INSERT INTO clinvar_variants
    (release_id, record_ordinal, vcv_accession, variation_id)
  VALUES ('versioned', 1, 'VCV000000102', 102),
         ('withdraw-old', 1, 'VCV000000103', 103),
         ('withdraw-new', 1, 'VCV000000103', 103)
")
DBI::dbExecute(con, "
  INSERT INTO clinvar_alleles
    (release_id, record_ordinal, vcv_accession, allele_entity_id, allele_id)
  VALUES ('versioned', 1, 'VCV000000102', 'versioned-allele', 202),
         ('withdraw-old', 1, 'VCV000000103', 'withdraw-old-allele', 203),
         ('withdraw-new', 1, 'VCV000000103', 'withdraw-new-allele', 203)
")
DBI::dbExecute(con, "
  INSERT INTO clinvar_scv_assertions
    (release_id, record_ordinal, source_ordinal, vcv_accession,
     assertion_entity_id, assertion_id, scv_accession, scv_version,
     classification, review_status, date_last_evaluated)
  VALUES ('versioned', 1, 1, 'VCV000000102', 'versioned-assertion', 10201,
          'SCV000000102', 1, 'Pathogenic',
          'criteria provided, single submitter', DATE '2020-01-01'),
         ('versioned', 1, 2, 'VCV000000102', 'versioned-assertion', 10201,
          'SCV000000102', 2, 'Benign',
          'criteria provided, single submitter', DATE '2024-01-01'),
         ('withdraw-old', 1, 1, 'VCV000000103', 'withdraw-assertion', 10301,
          'SCV000000103', 1, 'Pathogenic',
          'criteria provided, single submitter', DATE '2024-01-01')
")
versioned <- DBI::dbGetQuery(con, "
  SELECT policy_classification, retained_scv_count
  FROM clinvar_policy_allele_decisions
  WHERE release_id = 'versioned'
")
expect_equal(versioned$policy_classification, "Benign")
expect_equal(versioned$retained_scv_count, 1)
withdrawn <- DBI::dbGetQuery(con, "
  SELECT release_id
  FROM clinvar_policy_allele_decisions
  WHERE release_id IN ('withdraw-old', 'withdraw-new')
")
expect_equal(withdrawn$release_id, "withdraw-old")

# Compound records attach policy evidence to the top-level allele only; a
# nested component allele must not acquire the parent decision independently.
DBI::dbExecute(con, "
  INSERT INTO clinvar_variants
    (release_id, record_ordinal, vcv_accession, variation_id)
  VALUES ('compound', 1, 'VCV000000104', 104)
")
DBI::dbExecute(con, "
  INSERT INTO clinvar_alleles
    (release_id, record_ordinal, vcv_accession, allele_entity_id,
     parent_allele_entity_id, allele_id)
  VALUES ('compound', 1, 'VCV000000104', 'compound-root', NULL, 204),
         ('compound', 1, 'VCV000000104', 'compound-child', 'compound-root', 205)
")
DBI::dbExecute(con, "
  INSERT INTO clinvar_scv_assertions
    (release_id, record_ordinal, source_ordinal, vcv_accession,
     assertion_entity_id, scv_accession, scv_version, classification,
     review_status, date_last_evaluated)
  VALUES ('compound', 1, 1, 'VCV000000104', 'compound-assertion',
          'SCV000000104', 1, 'Pathogenic',
          'criteria provided, single submitter', DATE '2024-01-01')
")
compound <- DBI::dbGetQuery(con, "
  SELECT allele_id
  FROM clinvar_policy_allele_decisions
  WHERE release_id = 'compound'
")
expect_equal(compound$allele_id, 204)

# GRCh38 mitochondrial source chromosome MT is exported as chrM.
DBI::dbExecute(con, "
  INSERT INTO clinvar_releases (release_id, source_path)
  VALUES ('mitochondrial', 'synthetic-release-fixture')
")
DBI::dbExecute(con, "
  INSERT INTO clinvar_variants
    (release_id, record_ordinal, vcv_accession, variation_id)
  VALUES ('mitochondrial', 1, 'VCV000000105', 105)
")
DBI::dbExecute(con, "
  INSERT INTO clinvar_alleles
    (release_id, record_ordinal, vcv_accession, allele_entity_id, allele_id)
  VALUES ('mitochondrial', 1, 'VCV000000105', 'mitochondrial-allele', 205)
")
DBI::dbExecute(con, "
  INSERT INTO clinvar_locations
    (release_id, record_ordinal, vcv_accession, allele_entity_id, location_id,
     assembly, chromosome, position_vcf, reference_allele_vcf,
     alternate_allele_vcf)
  VALUES ('mitochondrial', 1, 'VCV000000105', 'mitochondrial-allele',
          'mitochondrial-location', 'GRCh38', 'MT', 100, 'A', 'G')
")
DBI::dbExecute(con, "
  INSERT INTO clinvar_scv_assertions
    (release_id, record_ordinal, source_ordinal, vcv_accession,
     assertion_entity_id, scv_accession, scv_version, classification,
     review_status, date_last_evaluated)
  VALUES ('mitochondrial', 1, 1, 'VCV000000105', 'mitochondrial-assertion',
          'SCV000000105', 1, 'Pathogenic',
          'criteria provided, single submitter', DATE '2024-01-01')
")
mitochondrial_path <- tempfile(fileext = ".parquet")
rclinvarbitration_export_clinvarbitration_parquet(
  con, mitochondrial_path, "mitochondrial", "GRCh38"
)
mitochondrial <- DBI::dbGetQuery(
  con,
  paste0(
    "SELECT * FROM read_parquet(",
    as.character(DBI::dbQuoteString(con, mitochondrial_path)), ")"
  )
)
expect_equal(mitochondrial$contig, "chrM")
expect_equal(mitochondrial$position, 100)
unlink(mitochondrial_path)

DBI::dbDisconnect(con, shutdown = TRUE)
