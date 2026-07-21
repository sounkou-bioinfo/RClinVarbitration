# Stream a ClinVar VCV XML release into relational DuckDB tables

The native extension reads `.xml` and `.xml.gz` with a libxml2 forward
reader. One compact JSON-backed row per selected ClinVar entity is
written to a disk-backed staging table in one XML pass, projected into
the public ClinVar relations without an EAV pivot, and dropped. No XML
DOM, XML blob, generic parser-node graph, or R data-frame
materialization is used. Each public relation is committed
independently, the release catalogue row marks completion, and failed
imports remove partial rows for `release_id`.

## Usage

``` r
rclinvarbitration_import_xml(
  con,
  path,
  release_id,
  replace = FALSE,
  source_url = NULL,
  source_md5 = NULL
)
```

## Arguments

- con:

  A DuckDB DBI connection.

- path:

  Path to an official ClinVar VCV XML or XML.GZ release.

- release_id:

  User-supplied release label stored with every row.

- replace:

  Replace rows already stored for `release_id`?

- source_url:

  Optional source URL for the release catalogue. When `path` is returned
  directly by
  [`rclinvarbitration_download_clinvar()`](https://rgenomicsetl.github.io/RClinVarbitration/reference/rclinvarbitration_download_clinvar.md),
  its download metadata supplies this value automatically.

- source_md5:

  Optional 32-character source MD5 digest. Download metadata is used
  automatically when available.

## Value

A named numeric vector with imported entity counts.
