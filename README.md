
<!-- README.md is generated from README.Rmd. -->

# RClinVarbitration

`RClinVarbitration` streams the complete official ClinVar VCV XML/XML.GZ
release into focused relational DuckDB tables. It retains public VCV,
RCV, SCV, AlleleID, VariationID, and disease identifiers instead of
exposing XML parser coordinates.

The package-owned native extension uses a libxml2 forward reader. An
import reads the gzip XML exactly once and writes one compact
JSON-backed row per selected ClinVar entity to a disk-backed staging
table. It then projects ordinary ClinVar relations without an EAV pivot
and drops staging. It does not build an XML DOM or R data frame and does
not persist generic XML nodes, edges, or element statements.

Because the extension uses DuckDB’s `C_STRUCT_UNSTABLE` interface, the
package bundles and selects exact-version artifacts for DuckDB `v1.5.0`
through `v1.5.4`. Connections must allow locally built unsigned
extensions.

## Relational schema

| Relation                       | One row per                                                      |
|:-------------------------------|:-----------------------------------------------------------------|
| `clinvar_variants`             | VCV variation archive                                            |
| `clinvar_alleles`              | allele or variation component                                    |
| `clinvar_locations`            | assembly-specific allele location                                |
| `clinvar_genes`                | allele–gene relation                                             |
| `clinvar_rcv_assertions`       | disease-specific RCV aggregate assertion                         |
| `clinvar_scv_assertions`       | submitted SCV assertion                                          |
| `clinvar_conditions`           | condition attached to an RCV or SCV                              |
| `clinvar_condition_names`      | preferred or alternate condition name                            |
| `clinvar_observations`         | SCV observation                                                  |
| `clinvar_citations`            | SCV-attributable citation                                        |
| `clinvar_citation_identifiers` | PMID, DOI, or other citation identifier                          |
| `clinvar_attributes`           | typed SCV source attribute retained with its context             |
| `clinvar_text`                 | attributable assertion comment, condition name, or evidence text |
| `clinvar_normalized_alleles`   | assembly/locus/ref/alt join view                                 |
| `clinvar_disease_aggregates`   | VCV/allele × RCV × disease aggregate                             |
| `clinvar_disease_submissions`  | VCV/allele × SCV × disease submission                            |

The release-scale tables retain explicit logical key columns but do not
create DuckDB ART indexes: those indexes must remain memory-resident and
are a poor fit for a complete analytical release. The small
`clinvar_releases` completion catalogue retains its primary key.

The executable README requires the complete local
`ClinVarVCVRelease_00-latest.xml.gz`, selected with
`CLINVAR_VCV_XML_FILE`, and an explicit immutable release label in
`CLINVAR_RELEASE_ID`. It does not substitute the bundled one-record
regression fixture. A **file-backed** DuckDB holds the complete import
so every following query reuses the same data rather than rescanning
XML. Set `CLINVAR_DUCKDB_FILE` to retain and reuse a completed import
across renders; otherwise the executable document uses a temporary
database.

``` r
library(DBI)
library(duckdb)
library(RClinVarbitration)

clinvar_xml <- Sys.getenv("CLINVAR_VCV_XML_FILE")
release_id <- Sys.getenv("CLINVAR_RELEASE_ID")
stopifnot(
  nzchar(release_id),
  file.exists(clinvar_xml),
  identical(basename(clinvar_xml), "ClinVarVCVRelease_00-latest.xml.gz")
)

clinvar_db <- Sys.getenv("CLINVAR_DUCKDB_FILE")
persistent_db <- nzchar(clinvar_db)
if (persistent_db) {
  dir.create(dirname(clinvar_db), recursive = TRUE, showWarnings = FALSE)
  clinvar_db <- normalizePath(clinvar_db, mustWork = FALSE)
} else {
  clinvar_db <- tempfile("rclinvarbitration-readme-", fileext = ".duckdb")
}
clinvar_tmp <- paste0(clinvar_db, ".tmp")
con <- dbConnect(duckdb(
  dbdir = clinvar_db,
  config = list(
    allow_unsigned_extensions = "true",
    memory_limit = Sys.getenv("CLINVAR_DUCKDB_MEMORY_LIMIT", "2GB"),
    preserve_insertion_order = "false",
    temp_directory = clinvar_tmp,
    threads = "2"
  )
))
rclinvarbitration_enable(con)
rclinvarbitration_init(con)
release_sql <- as.character(dbQuoteString(con, release_id))
stored_release <- dbGetQuery(con, paste0(
  "SELECT source_path FROM clinvar_releases WHERE release_id = ", release_sql
))
count_relations <- c(
  variants = "clinvar_variants",
  alleles = "clinvar_alleles",
  rcv_assertions = "clinvar_rcv_assertions",
  scv_assertions = "clinvar_scv_assertions",
  conditions = "clinvar_conditions",
  observations = "clinvar_observations",
  citations = "clinvar_citations",
  text = "clinvar_text"
)
if (nrow(stored_release)) {
  stopifnot(identical(stored_release$source_path, normalizePath(clinvar_xml)))
  counts <- vapply(count_relations, function(table) {
    dbGetQuery(con, paste0(
      "SELECT count(*) AS n FROM ", table, " WHERE release_id = ", release_sql
    ))$n[[1L]]
  }, numeric(1))
} else {
  counts <- rclinvarbitration_import_xml(
    con,
    clinvar_xml,
    release_id = release_id
  )
}
knitr::kable(
  data.frame(relation = names(counts), rows = unname(counts)),
  row.names = FALSE
)
```

| relation       |     rows |
|:---------------|---------:|
| variants       |  4531457 |
| alleles        |  4535897 |
| rcv_assertions |  5966166 |
| scv_assertions |  6905758 |
| conditions     | 13815000 |
| observations   |  6961803 |
| citations      |  8241967 |
| text           | 30649367 |

## Disease-specific aggregates

RCVs are the disease-specific ClinVar aggregates. They remain distinct
from the VCV-level aggregate and are joined directly to their classified
condition. This is the primary substrate for reproducing
ClinVarbitration and for deriving alternative disease-aware policies.

``` r
disease_summary <- dbGetQuery(con, "
  SELECT aggregate_classification, aggregate_review_status,
         count(*) AS disease_aggregates,
         count(DISTINCT disease_identifier) AS identified_diseases
  FROM clinvar_disease_aggregates
  GROUP BY aggregate_classification, aggregate_review_status
  ORDER BY disease_aggregates DESC
  LIMIT 20
")
knitr::kable(disease_summary, row.names = FALSE)
```

| aggregate_classification                     | aggregate_review_status                              | disease_aggregates | identified_diseases |
|:---------------------------------------------|:-----------------------------------------------------|-------------------:|--------------------:|
| Uncertain significance                       | criteria provided, single submitter                  |            2994235 |                8562 |
| Likely benign                                | criteria provided, single submitter                  |            1475769 |                5193 |
| NA                                           | no classification provided                           |             379911 |                  81 |
| Pathogenic                                   | criteria provided, single submitter                  |             294922 |                7139 |
| Benign                                       | criteria provided, single submitter                  |             276571 |                5030 |
| Likely pathogenic                            | criteria provided, single submitter                  |             197612 |                7527 |
| Benign                                       | criteria provided, multiple submitters, no conflicts |             106721 |                1823 |
| Uncertain significance                       | criteria provided, multiple submitters, no conflicts |             103463 |                2741 |
| Uncertain significance                       | no assertion criteria provided                       |              96298 |                2790 |
| Likely benign                                | no assertion criteria provided                       |              93928 |                 770 |
| Likely benign                                | criteria provided, multiple submitters, no conflicts |              66802 |                1012 |
| Conflicting classifications of pathogenicity | criteria provided, conflicting classifications       |              65850 |                2412 |
| Pathogenic                                   | no assertion criteria provided                       |              51214 |                7823 |
| Benign/Likely benign                         | criteria provided, multiple submitters, no conflicts |              48194 |                1336 |
| Pathogenic                                   | criteria provided, multiple submitters, no conflicts |              36856 |                2562 |
| Benign                                       | no assertion criteria provided                       |              29266 |                 576 |
| Pathogenic/Likely pathogenic                 | criteria provided, multiple submitters, no conflicts |              24375 |                2412 |
| Likely pathogenic                            | no assertion criteria provided                       |              21963 |                2971 |
| not provided                                 | no classification provided                           |              19087 |                2171 |
| Pathogenic                                   | reviewed by expert panel                             |               9789 |                 106 |

``` r
disease_aggregates <- dbGetQuery(con, "
  SELECT vcv_accession, rcv_accession,
         disease_database, disease_identifier, disease_name,
         aggregate_classification, aggregate_review_status
  FROM clinvar_disease_aggregates
  WHERE disease_identifier IS NOT NULL
  ORDER BY vcv_accession, rcv_accession
  LIMIT 12
")
knitr::kable(disease_aggregates, row.names = FALSE)
```

| vcv_accession | rcv_accession | disease_database | disease_identifier | disease_name                                        | aggregate_classification | aggregate_review_status                              |
|:--------------|:--------------|:-----------------|:-------------------|:----------------------------------------------------|:-------------------------|:-----------------------------------------------------|
| VCV000000002  | RCV000000012  | MedGen           | C3150901           | Hereditary spastic paraplegia 48                    | Pathogenic               | criteria provided, single submitter                  |
| VCV000000002  | RCV004998069  | MedGen           | C3661900           | not provided                                        | Pathogenic               | criteria provided, single submitter                  |
| VCV000000003  | RCV000000013  | MedGen           | C3150901           | Hereditary spastic paraplegia 48                    | Pathogenic               | no assertion criteria provided                       |
| VCV000000004  | RCV000000014  | MedGen           | C4551772           | Galloway-Mowat syndrome 1                           | Uncertain significance   | no assertion criteria provided                       |
| VCV000000005  | RCV000000015  | MedGen           | C4748791           | Mitochondrial complex I deficiency, nuclear type 19 | Pathogenic               | criteria provided, single submitter                  |
| VCV000000005  | RCV000578659  | MedGen           | C3661900           | not provided                                        | Pathogenic               | criteria provided, multiple submitters, no conflicts |
| VCV000000005  | RCV001194045  | MedGen           | C2931891           | Leigh syndrome                                      | Pathogenic               | criteria provided, single submitter                  |
| VCV000000006  | RCV000000016  | MedGen           | C4748791           | Mitochondrial complex I deficiency, nuclear type 19 | Likely pathogenic        | criteria provided, single submitter                  |
| VCV000000007  | RCV000000017  | MedGen           | C1838979           | Mitochondrial complex I deficiency                  | Pathogenic               | criteria provided, single submitter                  |
| VCV000000007  | RCV000735415  | MedGen           | C4748792           | Mitochondrial complex I deficiency, nuclear type 21 | Likely pathogenic        | criteria provided, single submitter                  |
| VCV000000009  | RCV000000019  | MedGen           | C3469186           | Hemochromatosis type 1                              | Pathogenic               | criteria provided, multiple submitters, no conflicts |
| VCV000000009  | RCV000178096  | MedGen           | C3661900           | not provided                                        | Pathogenic               | criteria provided, multiple submitters, no conflicts |

Individual SCVs retain their disease mappings, submitters, dates, review
status, and contribution flags. Policy SQL can therefore recompute an
aggregate per allele and disease instead of accepting only ClinVar’s
top-line VCV label.

``` r
submission_summary <- dbGetQuery(con, "
  SELECT classification, review_status,
         count(*) AS disease_submissions,
         count(DISTINCT submitter_id) AS submitters
  FROM clinvar_disease_submissions
  GROUP BY classification, review_status
  ORDER BY disease_submissions DESC
  LIMIT 20
")
knitr::kable(submission_summary, row.names = FALSE)
```

| classification         | review_status                       | disease_submissions | submitters |
|:-----------------------|:------------------------------------|--------------------:|-----------:|
| Uncertain significance | criteria provided, single submitter |             3272425 |        885 |
| Likely benign          | criteria provided, single submitter |             1719238 |        323 |
| Benign                 | criteria provided, single submitter |              592918 |        254 |
| NA                     | no classification provided          |              531035 |         44 |
| Pathogenic             | criteria provided, single submitter |              451560 |       1427 |
| Likely pathogenic      | criteria provided, single submitter |              257591 |       1276 |
| Uncertain significance | no assertion criteria provided      |              127780 |        697 |
| Likely benign          | no assertion criteria provided      |              125192 |        208 |
| Pathogenic             | no assertion criteria provided      |               83368 |       1430 |
| Benign                 | no assertion criteria provided      |               57536 |        184 |
| Likely pathogenic      | no assertion criteria provided      |               32892 |       1048 |
| not provided           | no classification provided          |               30904 |        164 |
| Uncertain Significance | criteria provided, single submitter |               29747 |         15 |
| Likely Benign          | criteria provided, single submitter |               16871 |         12 |
| Pathogenic             | reviewed by expert panel            |                9782 |         43 |
| Likely Pathogenic      | criteria provided, single submitter |                5184 |         53 |
| benign                 | criteria provided, single submitter |                3435 |          3 |
| Benign                 | reviewed by expert panel            |                2778 |         41 |
| Uncertain Significance | reviewed by expert panel            |                2699 |         39 |
| pathogenic             | criteria provided, single submitter |                2518 |          9 |

## Normalized allele join surface

The normalized allele view is the join surface for downstream
Rduckhts/DuckHTS work. RClinVarbitration does not duplicate VEP or PM5.

``` r
alleles <- dbGetQuery(con, "
  SELECT assembly,
         count(*) AS normalized_alleles,
         count(DISTINCT allele_id) AS allele_ids
  FROM clinvar_normalized_alleles
  GROUP BY assembly
  ORDER BY assembly
")
knitr::kable(alleles, row.names = FALSE)
```

| assembly | normalized_alleles | allele_ids |
|:---------|-------------------:|-----------:|
| GRCh37   |            4445183 |    4439393 |
| GRCh38   |            4445165 |    4439398 |
| NCBI36   |               2779 |       2778 |

Long assertion explanations remain attributable to the source SCV. The
README truncates selected text in SQL so knitr does not pad console
output to the width of the longest ClinVar comment.

``` r
evidence <- dbGetQuery(con, "
  SELECT s.scv_accession, s.submitter_name,
         left(t.text, 180) || CASE WHEN length(t.text) > 180 THEN '…' ELSE '' END AS excerpt
  FROM clinvar_text t
  JOIN clinvar_scv_assertions s
    ON s.release_id = t.release_id
   AND s.assertion_entity_id = t.scv_entity_id
  WHERE t.section = 'comment'
  ORDER BY s.scv_accession
  LIMIT 8
")
knitr::kable(evidence, row.names = FALSE)
```

| scv_accession | submitter_name | excerpt                                                                                                                                                                           |
|:--------------|:---------------|:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| SCV000020146  | OMIM           | Reason: Other                                                                                                                                                                     |
| SCV000020146  | OMIM           | Notes: Flagging candidate with reason of insufficient supporting evidence. This gene has been classified as having a limited gene-disease relationship by a ClinGen Expert Panel. |
| SCV000020162  | OMIM           | Notes: None                                                                                                                                                                       |
| SCV000020162  | OMIM           | Reason: Older and outlier claim with insufficient supporting evidence                                                                                                             |
| SCV000020201  | OMIM           | Notes: None                                                                                                                                                                       |
| SCV000020201  | OMIM           | Reason: Outlier claim with insufficient supporting evidence                                                                                                                       |
| SCV000020580  | OMIM           | Until October, 2023, the haplotype reported in OMIM’s allelic variant 613018.0004 was erroneously represented in ClinVar as a simple allele.                                      |
| SCV000020787  | OMIM           | SCV000020796 was merged into SCV000020787 to remove duplication.                                                                                                                  |

``` r
DBI::dbDisconnect(con, shutdown = TRUE)
if (!persistent_db) {
  unlink(
    c(clinvar_db, paste0(clinvar_db, ".wal"), clinvar_tmp),
    recursive = TRUE,
    force = TRUE
  )
}
```

ClinVarbitration decision rules are a versioned SQL layer over
`clinvar_disease_submissions`. P/LP outputs join
`clinvar_normalized_alleles` by assembly, chromosome, position,
reference, and alternate allele. DuckLake can later retain each merged
release as a snapshot, but XML ingestion and policy semantics remain
explicit here.

## Acknowledgement

[Teague Sterling’s DuckDB Webbed
extension](https://github.com/teaguesterling/duckdb_webbed) informed the
initial assessment of SQL-native XML ingestion. RClinVarbitration does
not vendor or execute Webbed: its package-owned libxml2 scan handles the
official gzip VCV release and is built against each supported exact
DuckDB engine version.
