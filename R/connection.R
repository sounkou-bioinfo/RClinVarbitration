rclinvarbitration_sql_string <- function(x) {
  paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
}

rclinvarbitration_normalize_duckdb_version <- function(version) {
  version <- as.character(version)
  if (length(version) != 1L || is.na(version) ||
      !grepl("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", version)) {
    stop("DuckDB engine version must be an exact release such as 'v1.5.3'.", call. = FALSE)
  }
  if (startsWith(version, "v")) version else paste0("v", version)
}

rclinvarbitration_connection_version <- function(con) {
  version <- DBI::dbGetQuery(con, "SELECT version() AS version")$version
  if (length(version) != 1L || is.na(version)) {
    stop("could not determine the DuckDB engine version.", call. = FALSE)
  }
  rclinvarbitration_normalize_duckdb_version(version)
}

rclinvarbitration_bundled_duckdb_versions <- function(root) {
  versions <- list.files(root, pattern = "^v[0-9]+\\.[0-9]+\\.[0-9]+$")
  versions <- versions[file.exists(file.path(root, versions, "rclinvarbitration.duckdb_extension"))]
  if (!length(versions)) return(character())
  paste0("v", as.character(sort(numeric_version(sub("^v", "", versions)))))
}

#' Locate a version-matched RClinVarbitration DuckDB extension
#'
#' The package uses DuckDB's unstable C extension ABI for its streaming table
#' function, so it bundles one artifact per supported exact engine release.
#'
#' @param duckdb_version Exact DuckDB version, with or without a `v` prefix.
#'   `NULL` selects the version reported by the installed `duckdb` package.
#' @return An absolute extension path.
#' @export
rclinvarbitration_extension_path <- function(duckdb_version = NULL) {
  if (is.null(duckdb_version)) {
    if (!requireNamespace("duckdb", quietly = TRUE)) {
      stop("supply `duckdb_version` or install the duckdb package.", call. = FALSE)
    }
    namespace <- asNamespace("duckdb")
    getter <- get0("get_duckdb_version", envir = namespace, mode = "function", inherits = FALSE)
    version <- if (!is.null(getter)) getter() else get0("duckdb_version", envir = namespace, inherits = FALSE)
    if (is.null(version)) stop("could not determine the installed DuckDB version.", call. = FALSE)
    duckdb_version <- version
  }
  duckdb_version <- rclinvarbitration_normalize_duckdb_version(duckdb_version)
  root <- system.file("rclinvarbitration_extension", "build", package = "RClinVarbitration", mustWork = TRUE)
  path <- file.path(root, duckdb_version, "rclinvarbitration.duckdb_extension")
  if (!file.exists(path)) {
    bundled <- rclinvarbitration_bundled_duckdb_versions(root)
    stop(
      "RClinVarbitration has no artifact for DuckDB ", duckdb_version,
      ". Bundled versions: ", if (length(bundled)) paste(bundled, collapse = ", ") else "none",
      ". Install a release that supports this exact engine version.",
      call. = FALSE
    )
  }
  normalizePath(path, mustWork = TRUE)
}

#' Enable native ClinVar XML scanning on a DuckDB connection
#'
#' Loads the package-owned `rclinvarbitration` extension. Its native
#' `clinvar_xml_entities(path)` table function is the compact, ClinVar-specific
#' one-pass staging surface used by [rclinvarbitration_import_xml()]. The connection must have been
#' created with `duckdb::duckdb(config = list(allow_unsigned_extensions =
#' "true"))`, as for any locally built DuckDB extension.
#'
#' @param con A DuckDB DBI connection.
#' @param extension_path Optional explicit exact-version extension path.
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
