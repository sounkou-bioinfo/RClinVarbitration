#!/usr/bin/env Rscript

usage <- paste(
  "Usage:",
  "  Rscript tools/compare_clinvarbitration_release.R \\",
  "    --submission submission_summary_YYYY-MM.txt.gz \\",
  "    --variant variant_summary_YYYY-MM.txt.gz \\",
  "    --reference clinvar_decisions.tsv \\",
  "    --output-prefix comparison/output",
  sep = "\n"
)

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) %% 2L || !length(arguments)) stop(usage, call. = FALSE)
arguments <- setNames(arguments[c(FALSE, TRUE)], arguments[c(TRUE, FALSE)])
required <- c("--submission", "--variant", "--reference", "--output-prefix")
if (!all(required %in% names(arguments))) stop(usage, call. = FALSE)

submission_path <- normalizePath(arguments[["--submission"]], mustWork = TRUE)
variant_path <- normalizePath(arguments[["--variant"]], mustWork = TRUE)
reference_path <- normalizePath(arguments[["--reference"]], mustWork = TRUE)
prefix <- normalizePath(arguments[["--output-prefix"]], mustWork = FALSE)
if (!dir.exists(dirname(prefix))) stop("Output-prefix parent directory does not exist.", call. = FALSE)

library(DBI)
library(duckdb)
library(RClinVarbitration)

candidate_path <- paste0(prefix, ".candidate.parquet")
differences_path <- paste0(prefix, ".differences.parquet")
summary_path <- paste0(prefix, ".summary.csv")
if (any(file.exists(c(candidate_path, differences_path, summary_path)))) {
  stop("Refusing to overwrite an existing comparison output.", call. = FALSE)
}
temp_directory <- paste0(prefix, ".duckdb-tmp")
dir.create(temp_directory, recursive = TRUE, showWarnings = FALSE)
con <- dbConnect(duckdb(config = list(memory_limit = "2GB", temp_directory = temp_directory, threads = "2")))
on.exit({
  dbDisconnect(con, shutdown = TRUE)
  unlink(temp_directory, recursive = TRUE, force = TRUE)
}, add = TRUE)

rclinvarbitration_reproduce_clinvarbitration_parquet(
  con,
  submission_path = submission_path,
  variant_path = variant_path,
  path = candidate_path,
  assembly = "GRCh38"
)
quote_path <- function(path) as.character(dbQuoteString(con, path))
invisible(dbExecute(con, paste0("CREATE TEMP TABLE candidate AS SELECT * FROM read_parquet(", quote_path(candidate_path), ")")))
invisible(dbExecute(con, paste0(
  "CREATE TEMP TABLE reference AS SELECT contig, cast(position AS INTEGER) AS position, ",
  "reference, alternate, clinical_significance, cast(gold_stars AS INTEGER) AS gold_stars, ",
  "cast(allele_id AS INTEGER) AS allele_id FROM read_csv(", quote_path(reference_path),
  ", header = true, delim = '\\t')"
)))
key <- "contig, position, reference, alternate, allele_id"
for (table in c("candidate", "reference")) {
  duplicate_count <- dbGetQuery(con, paste0(
    "SELECT count(*) AS n FROM (SELECT ", key, " FROM ", table,
    " GROUP BY ", key, " HAVING count(*) > 1)"
  ))$n[[1L]]
  if (duplicate_count) stop(table, " has duplicate ClinVarbitration keys.", call. = FALSE)
}

invisible(dbExecute(con, paste0(
  "CREATE TEMP TABLE differential AS SELECT ",
  "coalesce(c.contig, r.contig) AS contig, coalesce(c.position, r.position) AS position,",
  "coalesce(c.reference, r.reference) AS reference, coalesce(c.alternate, r.alternate) AS alternate,",
  "coalesce(c.allele_id, r.allele_id) AS allele_id,",
  "c.clinical_significance AS candidate_clinical_significance,",
  "c.gold_stars AS candidate_gold_stars,",
  "r.clinical_significance AS reference_clinical_significance,",
  "r.gold_stars AS reference_gold_stars,",
  "CASE WHEN c.contig IS NULL THEN 'reference_only' WHEN r.contig IS NULL THEN 'candidate_only' ",
  "WHEN c.clinical_significance <> r.clinical_significance OR c.gold_stars <> r.gold_stars ",
  "THEN 'decision_disagreement' ELSE 'equal' END AS comparison ",
  "FROM candidate c FULL OUTER JOIN reference r USING (", key, ")"
)))
summary <- dbGetQuery(con, "
  SELECT
    count(*) FILTER (WHERE comparison = 'equal') AS equal_rows,
    count(*) FILTER (WHERE comparison = 'candidate_only') AS candidate_only,
    count(*) FILTER (WHERE comparison = 'reference_only') AS reference_only,
    count(*) FILTER (WHERE comparison = 'decision_disagreement') AS decision_disagreements
  FROM differential
")
summary$candidate_rows <- dbGetQuery(con, "SELECT count(*) AS n FROM candidate")$n[[1L]]
summary$reference_rows <- dbGetQuery(con, "SELECT count(*) AS n FROM reference")$n[[1L]]
summary <- summary[, c("candidate_rows", "reference_rows", "equal_rows", "candidate_only", "reference_only", "decision_disagreements")]
write.csv(summary, summary_path, row.names = FALSE)
invisible(dbExecute(con, paste0(
  "COPY (SELECT * FROM differential WHERE comparison <> 'equal' ORDER BY contig, position, reference, alternate, allele_id) ",
  "TO ", quote_path(differences_path), " (FORMAT PARQUET, COMPRESSION ZSTD)"
)))
print(summary, row.names = FALSE)
cat("Candidate: ", candidate_path, "\n", sep = "")
cat("Differential: ", differences_path, "\n", sep = "")
cat("Summary: ", summary_path, "\n", sep = "")
