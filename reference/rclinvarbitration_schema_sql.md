# ClinVar relational schema SQL

Returns DuckDB DDL for the focused ClinVar schema. Public identifiers
and domain relations are retained directly: VCV variants, alleles and
assembly locations, genes, RCV aggregates, SCV submissions, conditions,
observations, citations, attributes, and attributable discovery text.
XML parser nodes are not persisted. The release catalogue enforces its
small primary key; the release-scale analytical tables expose logical
key columns without DuckDB ART indexes so complete imports remain
memory-bounded.

## Usage

``` r
rclinvarbitration_schema_sql()
```

## Value

A named character vector of SQL statements.
