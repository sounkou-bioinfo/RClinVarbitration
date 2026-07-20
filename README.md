
<!-- README.md is generated from README.Rmd. -->

# RClinVarbitration

`RClinVarbitration` streams official ClinVar VCV XML/XML.GZ into focused
relational DuckDB tables. It retains public VCV, RCV, SCV, AlleleID, and
VariationID identifiers instead of exposing XML parser coordinates.

The package-owned native extension uses a libxml2 forward reader. An
import reads the XML exactly once into a compact temporary semantic-fact
table, projects ordinary ClinVar relations, and drops the temporary
table. It does not build an XML DOM or R data frame and does not persist
generic XML nodes, edges, or element statements.

Because the extension uses DuckDB’s `C_STRUCT_UNSTABLE` interface, the
package bundles and selects exact-version artifacts for DuckDB `v1.5.0`
through `v1.5.4`. Connections must allow locally built unsigned
extensions.

## Relational schema

| Relation                       | One row per                                                               |
|:-------------------------------|:--------------------------------------------------------------------------|
| `clinvar_variants`             | VCV variation archive                                                     |
| `clinvar_alleles`              | allele or variation component                                             |
| `clinvar_locations`            | assembly-specific allele location                                         |
| `clinvar_genes`                | allele–gene relation                                                      |
| `clinvar_rcv_assertions`       | RCV aggregate assertion                                                   |
| `clinvar_scv_assertions`       | submitted SCV assertion                                                   |
| `clinvar_conditions`           | condition attached to a VCV, RCV, or SCV                                  |
| `clinvar_condition_names`      | preferred or alternate condition name                                     |
| `clinvar_observations`         | SCV observation                                                           |
| `clinvar_citations`            | attributable citation                                                     |
| `clinvar_citation_identifiers` | PMID, DOI, or other citation identifier                                   |
| `clinvar_attributes`           | typed source attribute retained with its context                          |
| `clinvar_text`                 | attributable comment, definition, condition name, or other discovery text |
| `clinvar_normalized_alleles`   | assembly/locus/ref/alt join view                                          |

The source package includes one **unaltered official NCBI VCV XML.GZ
record** for a fast executable smoke test. It is not synthetic data and
is not presented as a full-release benchmark. Full releases use the same
import call against `ClinVarVCVRelease_00-latest.xml.gz`; they belong in
a file-backed DuckDB and are intentionally not reparsed whenever this
README is rendered.

``` r
library(DBI)
library(duckdb)
library(RClinVarbitration)

con <- dbConnect(duckdb(config = list(allow_unsigned_extensions = "true")))
rclinvarbitration_enable(con)
clinvar_xml <- system.file(
  "extdata", "VCV_XML_VCV000091629.xml.gz",
  package = "RClinVarbitration", mustWork = TRUE
)
counts <- rclinvarbitration_import_xml(
  con,
  clinvar_xml,
  release_id = "ncbi-vcv-91629"
)
knitr::kable(
  data.frame(relation = names(counts), rows = unname(counts)),
  row.names = FALSE
)
```

| relation       | rows |
|:---------------|-----:|
| variants       |    1 |
| alleles        |    1 |
| rcv_assertions |    4 |
| scv_assertions |    6 |
| conditions     |   14 |
| observations   |    6 |
| citations      |   79 |
| text           |   59 |

The normalized allele view is the join surface for downstream
Rduckhts/DuckHTS work. RClinVarbitration does not duplicate VEP or PM5.

``` r
alleles <- dbGetQuery(con, "
  SELECT vcv_accession, allele_id, variation_id, assembly,
         chromosome, position_vcf, reference, alternate, canonical_spdi
  FROM clinvar_normalized_alleles
  ORDER BY assembly
")
knitr::kable(alleles, row.names = FALSE)
```

| vcv_accession | allele_id | variation_id | assembly | chromosome | position_vcf | reference | alternate | canonical_spdi            |
|:--------------|----------:|-------------:|:---------|:-----------|-------------:|:----------|:----------|:--------------------------|
| VCV000091629  |     97106 |        91629 | GRCh37   | 17         |     41234419 | A         | C         | NC_000017.11:43082401:A:C |
| VCV000091629  |     97106 |        91629 | GRCh38   | 17         |     43082402 | A         | C         | NC_000017.11:43082401:A:C |

SCV classifications remain separate from ClinVar’s VCV and RCV
aggregates, so later policy SQL can filter submitters and dates without
reconstructing assertions from XML paths.

``` r
assertions <- dbGetQuery(con, "
  SELECT scv_accession, submitter_name, classification,
         review_status, date_last_evaluated
  FROM clinvar_scv_assertions
  ORDER BY scv_accession
")
knitr::kable(assertions, row.names = FALSE)
```

| scv_accession | submitter_name                               | classification    | review_status                       | date_last_evaluated |
|:--------------|:---------------------------------------------|:------------------|:------------------------------------|:--------------------|
| SCV000108943  | Sharing Clinical Reports Project (SCRP)      | Pathogenic        | no assertion criteria provided      | 2012-09-24          |
| SCV000145071  | Breast Cancer Information Core (BIC) (BRCA1) | Pathogenic        | no assertion criteria provided      | 1999-06-22          |
| SCV000569301  | GeneDx                                       | Pathogenic        | criteria provided, single submitter | 2016-08-16          |
| SCV000688489  | Color Diagnostics, LLC DBA Color Health      | Likely pathogenic | criteria provided, single submitter | 2022-02-09          |
| SCV000827729  | Labcorp Genetics (formerly Invitae), Labcorp | Pathogenic        | criteria provided, single submitter | 2022-10-28          |
| SCV003995313  | Ambry Genetics                               | Pathogenic        | criteria provided, single submitter | 2023-05-19          |

Long assertion explanations are queried as attributable text. The README
selects and truncates them in SQL so knitr never prints a data frame
padded to the width of the longest ClinVar comment.

``` r
evidence <- dbGetQuery(con, "
  SELECT s.scv_accession,
         left(t.text, 180) || CASE WHEN length(t.text) > 180 THEN '…' ELSE '' END AS excerpt
  FROM clinvar_text t
  JOIN clinvar_scv_assertions s
    ON s.release_id = t.release_id
   AND s.assertion_entity_id = t.scv_entity_id
  WHERE t.section = 'comment'
  ORDER BY s.scv_accession
")
knitr::kable(evidence, row.names = FALSE)
```

| scv_accession | excerpt                                                                                                                                                                                  |
|:--------------|:-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| SCV000569301  | This variant is denoted BRCA1 c.4357+2T\>G or IVS12+2T\>G and consists of a T\>G nucleotide substitution at the +2 position of intron 12 of the BRCA1 gene. Using alternate nomenclatur… |
| SCV000688489  | This variant causes a T to G nucleotide substitution at the +2 position of intron 12 of the BRCA1 gene. This variant is also known as IVS13+2T\>G based on Breast Cancer Information …   |
| SCV000827729  | For these reasons, this variant has been classified as Pathogenic. Studies have shown that disruption of this splice site alters mRNA splicing and is expected to lead to the loss o…    |
| SCV003995313  | The c.4357+2T\>G intronic pathogenic mutation results from a T to G substitution two nucleotides after coding exon 11 in the BRCA1 gene. This alteration has been observed in ovarian…   |

``` r
DBI::dbDisconnect(con, shutdown = TRUE)
```

For a full release, open a file-backed connection and pass the local
official XML.GZ path to `rclinvarbitration_import_xml()`. The import is
one forward XML pass; the resulting DuckDB relations are queried
repeatedly without reparsing the gzip file.

ClinVarbitration decision rules are intentionally a later versioned SQL
layer over `clinvar_scv_assertions`. P/LP policy outputs will join
`clinvar_normalized_alleles` by assembly, chromosome, position,
reference, and alternate allele.

## Acknowledgement

[Teague Sterling’s DuckDB Webbed
extension](https://github.com/teaguesterling/duckdb_webbed) informed the
initial assessment of SQL-native XML ingestion. RClinVarbitration does
not vendor or execute Webbed: its package-owned libxml2 scan handles the
official gzip VCV release and is built against each supported exact
DuckDB engine version.
