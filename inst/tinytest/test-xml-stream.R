fixture <- system.file("extdata", "VCV_XML_VCV000091629.xml.gz", package = "RClinVarbitration")
expect_true(nzchar(fixture))
expect_true(file.exists(fixture))

con <- DBI::dbConnect(duckdb::duckdb(config = list(allow_unsigned_extensions = "true")))
rclinvarbitration_enable(con)

fixture_sql <- as.character(DBI::dbQuoteString(con, fixture))
atoms <- DBI::dbGetQuery(con, paste0(
  "SELECT predicate, object_id, object_value FROM clinvar_xml_statements(", fixture_sql, ")"
))
expect_true(nrow(atoms) > 100L)
expect_true(any(atoms$predicate == "rdf:type" & atoms$object_id == "xml:element/VariationArchive"))
expect_true(any(atoms$predicate == "xml:attribute/VariationID" & atoms$object_value == "91629"))
expect_true(any(atoms$predicate == "xml:text" & grepl("pathogenic", atoms$object_value, ignore.case = TRUE)))

counts <- rclinvarbitration_import_xml(con, fixture, release_id = "fixture-vcv")
expect_true(counts[["statements"]] == nrow(atoms))
expect_true(counts[["text"]] > 0L)
expect_equal(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM clinvar_nodes")$n, sum(atoms$predicate == "rdf:type"))
expect_true(DBI::dbGetQuery(con, "SELECT count(*) AS n FROM clinvar_text")$n > 0L)
expect_error(rclinvarbitration_import_xml(con, fixture, release_id = "fixture-vcv"))
DBI::dbDisconnect(con, shutdown = TRUE)
