# RClinVarbitration

[![R-CMD-check](https://github.com/sounkou-bioinfo/RClinVarbitration/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/sounkou-bioinfo/RClinVarbitration/actions/workflows/R-CMD-check.yaml)
[![pkgdown](https://github.com/sounkou-bioinfo/RClinVarbitration/actions/workflows/pkgdown.yaml/badge.svg)](https://sounkou-bioinfo.github.io/RClinVarbitration/)
[![r-universe](https://sounkou-bioinfo.r-universe.dev/badges/:name)](https://sounkou-bioinfo.r-universe.dev/)

`RClinVarbitration` streams official ClinVar VCV XML/XML.GZ releases
into relational DuckDB tables and derives ClinVarbitration-style
decisions from the retained SCV submissions. The import is a single
forward scan: it does not load the XML release into an R data frame or
an in-memory XML tree.

The package bundles exact-version DuckDB extensions for DuckDB `v1.5.0`
through `v1.5.4`. Connections must allow locally built unsigned
extensions.

## Installation and platforms

``` r

install.packages(
  "RClinVarbitration",
  repos = c(
    sounkou = "https://sounkou-bioinfo.r-universe.dev",
    CRAN = "https://cloud.r-project.org"
  )
)
```

Native builds support Linux, macOS, and x86-64 Windows. Linux and macOS
require libxml2, zlib, `pkg-config`, and a C compiler. On Windows,
install a current Rtools release; its target-aware `pkg-config` supplies
the static libxml2 and zlib dependencies. webR is supported separately
through the tested Emscripten build.

## Quick start

``` r

library(DBI)
library(duckdb)
library(RClinVarbitration)

con <- dbConnect(duckdb(config = list(allow_unsigned_extensions = "true")))

rclinvarbitration_enable(con)
rclinvarbitration_init(con)

# Replace this bundled one-record fixture with a complete VCV XML/XML.GZ file.
xml <- system.file(
  "extdata", "VCV_XML_VCV000091629.xml.gz",
  package = "RClinVarbitration"
)
imported <- rclinvarbitration_import_xml(
  con, xml, release_id = "clinvar-example"
)

dbGetQuery(con, "
  SELECT vcv_accession, variation_id, aggregate_classification
  FROM clinvar_variants
")
```

``` R
##   vcv_accession variation_id     aggregate_classification
## 1  VCV000091629        91629 Pathogenic/Likely pathogenic
```

For a complete current or archived release, use the checksum-validating
download cache and a file-backed database:

``` r

release <- "2026-03"
xml <- rclinvarbitration_download_clinvar(release)
# `"latest"` is also accepted, but assign its resolved content an immutable ID.

full_con <- dbConnect(duckdb(
  dbdir = "clinvar.duckdb",
  config = list(
    allow_unsigned_extensions = "true",
    memory_limit = "2GB",
    preserve_insertion_order = "false",
    threads = "2"
  )
))
rclinvarbitration_enable(full_con)
rclinvarbitration_import_xml(
  full_con, xml, release_id = paste0("ncbi-vcv-", release)
)
```

The main query surfaces are:

| Relation | Content |
|:---|:---|
| `clinvar_variants`, `clinvar_alleles`, `clinvar_locations` | VCV records and assembly-specific alleles |
| `clinvar_rcv_assertions`, `clinvar_scv_assertions` | disease aggregates and individual submissions |
| `clinvar_conditions`, `clinvar_observations`, `clinvar_text` | attributable condition, observation, and text evidence |
| `clinvar_disease_submissions` | SCV evidence grouped by disease |
| `clinvar_policy_decisions`, `clinvar_policy_allele_decisions` | disease- and allele-level arbitration |
| `clinvar_gene_summaries` | policy-versioned disease/classification counts by gene |
| `clinvar_hpo_terms`, `clinvar_literature_links` | normalized phenotype and literature links |
| `clinvar_semantic_documents` | attributable text documents for retrieval workflows |

Read the [arbitration
algorithm](https://sounkou-bioinfo.github.io/RClinVarbitration/articles/arbitration-algorithm.html),
[storage and caching
guide](https://sounkou-bioinfo.github.io/RClinVarbitration/articles/storage-cache-and-performance.html),
and [semantic/DuckLake/VariantStory
integration](https://sounkou-bioinfo.github.io/RClinVarbitration/articles/semantic-ducklake-variantstory.html).
The [deviation and differential
audit](https://github.com/sounkou-bioinfo/RClinVarbitration/blob/main/docs/ERRATA.md)
records known differences from upstream ClinVarbitration and ClinVar.

A measured complete 2026-07-02 release (5.42 GiB compressed XML)
imported in 21 minutes 52.5 seconds and produced a 22.33-GiB physical
DuckDB file. The storage guide reports hardware, row counts, peak
memory, and the used/free block split behind that physical high-water
size.

## Submitter exclusions

Imports retain all source submissions. Exclusions are parameters of
decision export, so the evidence remains available for audit and
alternative policies. Names are matched case-insensitively after
trimming whitespace.

``` r

out <- tempfile(fileext = ".parquet")
rclinvarbitration_export_clinvarbitration_parquet(
  con,
  out,
  release_id = "clinvar-example",
  assembly = "GRCh38",
  submitter_exclusions = c("Example laboratory", "Another submitter")
)
```

The argument adds to exclusions already configured for `profile_id`.
Named, reusable profiles can still be stored in
`clinvar_policy_profiles` and `clinvar_policy_submitter_exclusions`.

## Comparison with upstream ClinVarbitration

The policy is pinned to [Centre for Population Genomics
ClinVarbitration](https://github.com/populationgenomics/clinvarbitration)
2.2.11 at commit `658b9f241eb2d43aa11214b153b19c1e18a16337`.

|  | Upstream 2.2.11 | RClinVarbitration |
|:---|:---|:---|
| Primary input | NCBI submission and variant summary files | complete VCV XML/XML.GZ |
| Runtime | Python, Hail, Nextflow, bcftools | R, DuckDB, package-owned C extension |
| Decision scope | allele | allele and disease |
| Main outputs | TSV, Hail Table, VCF, PM5 resource | relational tables/views and Parquet |
| Submitter exclusion | `site_blacklist` / `-b` | `submitter_exclusions` or named profiles |
| PM5 | included | out of scope |

The shared decision rules include the 2016 ACMG date filter,
classification bins, 60/20 majority rule, strong-review precedence, and
star calculation. The XML-derived Parquet export has the upstream
seven-column decision schema, but is not expected to be byte-identical
because its source and grouping differ.

The archived-flat-file reproducer is retained only as a
differential-validation utility; it is redundant for ordinary XML
imports. An exact-input execution of the pinned upstream Python TSV
stage and this package’s flat reproducer over the complete March 2026
archives produced the same 4,125,389 keys with zero classification or
star differences. Input, code, configuration, and output digests are in
the [oracle
manifest](https://github.com/sounkou-bioinfo/RClinVarbitration/blob/main/inst/audits/march-2026-flat-exact-oracle.dcf).

The independently matched XML/flat audit classified every one of the 16
shared value differences and 361 key-set differences with source-row
receipts. Most come from NCBI flat rows whose classification is `-`
while XML carries a current classification; the remainder are one
duplicate-SCV identity case, five source vocabulary differences, and two
nested compound alleles. The [ERRATA
audit](https://github.com/sounkou-bioinfo/RClinVarbitration/blob/main/docs/ERRATA.md)
contains the full counts and receipts. A published Zenodo release with
16,865 reference-only keys used an unpinned source snapshot; it is not
the exact-input conformance result.

One deliberate edge-case difference is that RClinVarbitration applies
the qualified Illumina benign exclusion declared by upstream. At the
pinned commit, the Python implementation’s inner-loop `continue` does
not actually remove that submission, so compatibility here follows the
documented policy rather than that implementation accident.

## Evidence retrieval and reanalysis

A second motivation is to make ClinVar’s attributable evidence reusable,
not only to annotate known alleles. Submission descriptions, comments,
HPO links, gene relations, and publication identifiers can support
semantic retrieval, dynamic gene-panel proposals, and evidence review
for VUS or novel variants. The package provides joinable views for
[`ducksemantics`](https://github.com/sounkou-bioinfo/ducksemantics),
DuckLake release history, and the source-observation model planned by
[`VariantStory`](https://github.com/sounkou-bioinfo/VariantStory).

These workflows retrieve and rank evidence; an embedding neighbor does
not classify a variant. Provider identity, release, source rows,
deterministic evidence admission, and human review must remain explicit.

## Acknowledgements

The decision policy is adapted from Centre for Population Genomics
ClinVarbitration 2.2.11 under its MIT license. ClinVar source data are
provided by NCBI.
