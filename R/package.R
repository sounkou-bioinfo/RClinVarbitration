#' RClinVarbitration: ClinVar XML Semantic Graphs in DuckDB
#'
#' A DuckDB-native, XML-first ClinVar store. Its package-owned native extension
#' streams official `.xml.gz` VCV releases through libxml2 and emits ordered
#' semantic statements. SQL materializes source nodes, edges, literals, and
#' discovery text; versioned ClinVarbitration policy is deliberately a derived
#' layer over those source facts.
#'
#' @keywords internal
"_PACKAGE"
