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

Native builds currently support Linux and macOS and require libxml2,
zlib, `pkg-config`, and a C compiler. `OS_type: unix` prevents an
unsupported Windows installation; a Windows DuckDB-extension build has
not yet been implemented. webR is supported separately through the
tested Emscripten build and is Unix-like for R package metadata
purposes.

## Quick start

``` r

library(DBI)
library(duckdb)
library(RClinVarbitration)

con <- dbConnect(duckdb(config = list(allow_unsigned_extensions = "true")))
on.exit(dbDisconnect(con, shutdown = TRUE))

rclinvarbitration_enable(con)
rclinvarbitration_init(con)

# Replace this bundled one-record fixture with a complete VCV XML/XML.GZ file.
xml <- system.file(
  "extdata", "VCV_XML_VCV000091629.xml.gz",
  package = "RClinVarbitration"
)
rclinvarbitration_import_xml(con, xml, release_id = "clinvar-example")

dbGetQuery(con, "
  SELECT vcv_accession, variation_id, aggregate_classification
  FROM clinvar_variants
")
```

The main query surfaces are:

| Relation | Content |
|:---|:---|
| `clinvar_variants`, `clinvar_alleles`, `clinvar_locations` | VCV records and assembly-specific alleles |
| `clinvar_rcv_assertions` | disease-specific ClinVar aggregates |
| `clinvar_scv_assertions` | individual submissions and submitters |
| `clinvar_conditions`, `clinvar_observations`, `clinvar_citations`, `clinvar_text` | attributable evidence |
| `clinvar_disease_submissions` | SCV evidence grouped by disease |
| `clinvar_policy_decisions` | disease-level ClinVarbitration decisions |
| `clinvar_policy_allele_decisions` | allele-level ClinVarbitration decisions |

See the [function
reference](https://sounkou-bioinfo.github.io/RClinVarbitration/reference/index.html)
for the complete schema and API.

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

For the closest algorithm-level comparison, use the archived NCBI flat
files:

``` r

rclinvarbitration_reproduce_clinvarbitration_parquet(
  con,
  submission_path = "submission_summary_YYYY-MM.txt.gz",
  variant_path = "variant_summary_YYYY-MM.txt.gz",
  path = "clinvar_decisions.parquet",
  assembly = "GRCh38",
  submitter_exclusions = "example laboratory"
)
```

One deliberate edge-case difference is that RClinVarbitration applies
the qualified Illumina benign exclusion declared by upstream. At the
pinned commit, the Python implementation’s inner-loop `continue` does
not actually remove that submission, so compatibility here follows the
documented policy rather than that implementation accident.

## Acknowledgements

The decision policy is adapted from Centre for Population Genomics
ClinVarbitration 2.2.11 under its MIT license. ClinVar source data are
provided by NCBI.
