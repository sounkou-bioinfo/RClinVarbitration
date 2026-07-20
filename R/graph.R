#' ClinVar semantic graph SQL
#'
#' Returns the DuckDB DDL for the canonical source graph. XML elements are
#' nodes, parent/child relations are edges, and every XML attribute or text
#' value is a literal. `clinvar_text` is a first-class discovery projection,
#' not a lossy annotation field.
#'
#' @return A named character vector of SQL statements.
#' @export
rclinvarbitration_graph_sql <- function() {
  c(
    statements = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_statements (",
      "release_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "subject_id TEXT NOT NULL, predicate TEXT NOT NULL,",
      "object_id TEXT, object_value TEXT, object_kind TEXT NOT NULL,",
      "ordinal UBIGINT NOT NULL)"
    ),
    nodes = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_nodes (",
      "release_id TEXT NOT NULL, node_id TEXT NOT NULL, kind TEXT NOT NULL,",
      "record_ordinal UBIGINT NOT NULL, PRIMARY KEY (release_id, node_id))"
    ),
    edges = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_edges (",
      "release_id TEXT NOT NULL, subject_id TEXT NOT NULL, predicate TEXT NOT NULL,",
      "object_id TEXT NOT NULL, record_ordinal UBIGINT NOT NULL, ordinal UBIGINT NOT NULL)"
    ),
    literals = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_literals (",
      "release_id TEXT NOT NULL, subject_id TEXT NOT NULL, predicate TEXT NOT NULL,",
      "value TEXT NOT NULL, record_ordinal UBIGINT NOT NULL, ordinal UBIGINT NOT NULL)"
    ),
    text = paste(
      "CREATE TABLE IF NOT EXISTS clinvar_text (",
      "release_id TEXT NOT NULL, document_id TEXT NOT NULL, subject_id TEXT NOT NULL,",
      "predicate TEXT NOT NULL, text TEXT NOT NULL, record_ordinal UBIGINT NOT NULL,",
      "ordinal UBIGINT NOT NULL, PRIMARY KEY (release_id, document_id))"
    ),
    statement_subject_index = "CREATE INDEX IF NOT EXISTS clinvar_statements_subject_idx ON clinvar_statements (release_id, subject_id, predicate)",
    edge_subject_index = "CREATE INDEX IF NOT EXISTS clinvar_edges_subject_idx ON clinvar_edges (release_id, subject_id, predicate)",
    literal_subject_index = "CREATE INDEX IF NOT EXISTS clinvar_literals_subject_idx ON clinvar_literals (release_id, subject_id, predicate)",
    text_subject_index = "CREATE INDEX IF NOT EXISTS clinvar_text_subject_idx ON clinvar_text (release_id, subject_id, predicate)"
  )
}

#' Initialize a ClinVar semantic graph
#'
#' @param con A DuckDB DBI connection.
#' @return `con`, invisibly.
#' @export
rclinvarbitration_init <- function(con) {
  for (statement in unname(rclinvarbitration_graph_sql())) DBI::dbExecute(con, statement)
  invisible(con)
}

#' Stream a ClinVar XML release into semantic DuckDB tables
#'
#' The native table function reads `.xml` and `.xml.gz` files with libxml2's
#' forward reader. It streams `VariationArchive` records and stores XML
#' elements, attributes, and non-whitespace text directly as ordered semantic
#' statements. No XML blob, digest table, or R data-frame materialization is
#' involved.
#'
#' @param con A DuckDB DBI connection.
#' @param path Path to an official ClinVar VCV XML or XML.GZ release.
#' @param release_id User-supplied release label stored with every graph row.
#' @param replace Replace rows already stored for `release_id`?
#' @return A named integer vector with imported statement and text counts.
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
  if (replace) {
    for (table in c("clinvar_text", "clinvar_literals", "clinvar_edges", "clinvar_nodes", "clinvar_statements")) {
      DBI::dbExecute(con, paste0("DELETE FROM ", table, " WHERE release_id = ", release_sql))
    }
  } else {
    existing <- DBI::dbGetQuery(
      con,
      paste0("SELECT count(*) AS n FROM clinvar_statements WHERE release_id = ", release_sql)
    )$n[[1L]]
    if (existing > 0) {
      stop("`release_id` already exists; use `replace = TRUE` to replace it.", call. = FALSE)
    }
  }

  path_sql <- rclinvarbitration_sql_string(normalizePath(path, mustWork = TRUE))
  DBI::dbExecute(
    con,
    paste0(
      "INSERT INTO clinvar_statements ",
      "SELECT ", release_sql, ", record_ordinal, subject_id, predicate, object_id, object_value, object_kind, ordinal ",
      "FROM clinvar_xml_statements(", path_sql, ")"
    )
  )
  DBI::dbExecute(con, paste0(
    "INSERT INTO clinvar_nodes ",
    "SELECT ", release_sql, ", subject_id, object_id, record_ordinal ",
    "FROM clinvar_statements WHERE release_id = ", release_sql,
    " AND predicate = 'rdf:type'"
  ))
  DBI::dbExecute(con, paste0(
    "INSERT INTO clinvar_edges ",
    "SELECT release_id, subject_id, predicate, object_id, record_ordinal, ordinal ",
    "FROM clinvar_statements WHERE release_id = ", release_sql,
    " AND object_kind = 'node' AND predicate <> 'rdf:type'"
  ))
  DBI::dbExecute(con, paste0(
    "INSERT INTO clinvar_literals ",
    "SELECT release_id, subject_id, predicate, object_value, record_ordinal, ordinal ",
    "FROM clinvar_statements WHERE release_id = ", release_sql,
    " AND object_kind = 'literal'"
  ))
  DBI::dbExecute(con, paste0(
    "INSERT INTO clinvar_text ",
    "SELECT release_id, subject_id || ':' || ordinal::VARCHAR, subject_id, predicate, object_value, record_ordinal, ordinal ",
    "FROM clinvar_statements WHERE release_id = ", release_sql,
    " AND predicate IN ('xml:text', 'xml:cdata', 'xml:comment')"
  ))
  c(
    statements = DBI::dbGetQuery(con, paste0("SELECT count(*) AS n FROM clinvar_statements WHERE release_id = ", release_sql))$n[[1L]],
    text = DBI::dbGetQuery(con, paste0("SELECT count(*) AS n FROM clinvar_text WHERE release_id = ", release_sql))$n[[1L]]
  )
}
