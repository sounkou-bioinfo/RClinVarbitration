# Export an allele-level ClinVarbitration-compatible Parquet file

Writes the seven columns in Centre for Population Genomics
ClinVarbitration's `clinvar_decisions.tsv`: `contig`, `position`,
`reference`, `alternate`, `clinical_significance`, `gold_stars`, and
`allele_id`. The source is the package's allele-level policy view, not
the disease-level decision view, so each output row is usable as a
locus/alleles annotation record. Both GRCh37 and GRCh38 are supported.
The output retains every qualifying source locus, including distinct X/Y
locations for one AlleleID.

## Usage

``` r
rclinvarbitration_export_clinvarbitration_parquet(
  con,
  path,
  release_id,
  assembly = c("GRCh38", "GRCh37"),
  profile_id = "default",
  submitter_exclusions = character()
)
```

## Arguments

- con:

  A DuckDB DBI connection initialized with
  [`rclinvarbitration_init()`](https://sounkou-bioinfo.github.io/RClinVarbitration/reference/rclinvarbitration_init.md).

- path:

  New output `.parquet` file path.

- release_id:

  Imported ClinVar release label to export.

- assembly:

  Genome assembly: `"GRCh38"` or `"GRCh37"`.

- profile_id:

  Policy profile identifier, normally `"default"`.

- submitter_exclusions:

  Additional submitter names to exclude from this export. Matching is
  case-insensitive and ignores surrounding whitespace. These exclusions
  are combined with any exclusions already stored for `profile_id`;
  imported source submissions are not deleted.

## Value

A named list describing the written Parquet file, invisibly.

## Details

The file is schema-compatible with the upstream TSV/Hail decision
resource, but is not claimed to be byte-for-byte equivalent: this
package derives submissions and locations from VCV XML, whereas upstream
uses ClinVar's tab-delimited submission and variant summaries. PM5 is
deliberately not exported; Rduckhts/DuckHTS own downstream consequence
and PM5 processing.
