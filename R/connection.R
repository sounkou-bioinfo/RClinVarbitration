rclinvarbitration_sql_string <- function(x) {
  paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
}

rclinvarbitration_connection_version <- function(con) {
  version <- DBI::dbGetQuery(con, "SELECT version() AS version")$version
  if (length(version) != 1L || is.na(version)) {
    stop("could not determine the DuckDB engine version.", call. = FALSE)
  }
  as.character(version)
}

#' Locate the exact-version RClinVarbitration DuckDB extension
#'
#' The extension uses DuckDB's version-coupled C extension ABI. It is never
#' loaded into a different engine release.
#'
#' @param duckdb_version Exact DuckDB version, with or without a `v` prefix.
#' @return An absolute extension path.
#' @export
rclinvarbitration_extension_path <- function(duckdb_version = "v1.5.3") {
  duckdb_version <- as.character(duckdb_version)
  if (length(duckdb_version) != 1L || is.na(duckdb_version) ||
      !grepl("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", duckdb_version)) {
    stop("`duckdb_version` must be an exact version such as 'v1.5.3'.", call. = FALSE)
  }
  if (!startsWith(duckdb_version, "v")) duckdb_version <- paste0("v", duckdb_version)
  path <- system.file(
    "rclinvarbitration_extension", "build", duckdb_version,
    "rclinvarbitration.duckdb_extension", package = "RClinVarbitration"
  )
  if (!nzchar(path) || !file.exists(path)) {
    stop(
      "RClinVarbitration has no extension artifact for DuckDB ", duckdb_version,
      ". Install a package build that supports this exact engine release.",
      call. = FALSE
    )
  }
  normalizePath(path, mustWork = TRUE)
}

#' Enable native ClinVar XML scanning on a DuckDB connection
#'
#' Loads the package-owned `rclinvarbitration` extension, whose canonical SQL
#' entry point is `clinvar_xml_statements(path)`. The connection must have been
#' created with `duckdb::duckdb(config = list(allow_unsigned_extensions =
#' "true"))`, as for any locally built DuckDB extension.
#'
#' @param con A DuckDB DBI connection.
#' @param extension_path Optional explicit version-matched extension path.
#' @return `con`, invisibly.
#' @export
rclinvarbitration_enable <- function(con, extension_path = NULL) {
  version <- rclinvarbitration_connection_version(con)
  if (is.null(extension_path)) extension_path <- rclinvarbitration_extension_path(version)
  if (!is.character(extension_path) || length(extension_path) != 1L ||
      is.na(extension_path) || !nzchar(extension_path)) {
    stop("`extension_path` must be NULL or a non-empty character scalar.", call. = FALSE)
  }
  extension_path <- normalizePath(extension_path, mustWork = TRUE)
  DBI::dbExecute(con, paste("LOAD", rclinvarbitration_sql_string(extension_path)))
  invisible(con)
}
