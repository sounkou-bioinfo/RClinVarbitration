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
rclinvarbitration_import_xml(con, path, release_id, replace = FALSE)
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

## Value

A named numeric vector with imported entity counts.
