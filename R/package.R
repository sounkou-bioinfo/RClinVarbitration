#' RClinVarbitration: relational ClinVar evidence in DuckDB
#'
#' A DuckDB-native, XML-first ClinVar store. Its package-owned native extension
#' streams official `.xml.gz` VCV releases through libxml2 in one pass. SQL
#' materializes VCV, allele, location, gene, RCV, SCV, condition, observation,
#' citation, attribute, and evidence-text relations; versioned
#' ClinVarbitration policy is deliberately derived from those source records.
#'
#' @keywords internal
"_PACKAGE"
