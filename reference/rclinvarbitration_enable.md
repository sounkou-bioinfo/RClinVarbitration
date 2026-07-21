# Enable native ClinVar XML scanning on a DuckDB connection

Loads the package-owned `rclinvarbitration` extension and DuckDB's
official JSON extension. The latter is downloaded through DuckDB on
first use when it is not already installed; JSON is required to project
compact parser rows. Its native `clinvar_xml_entities(path)` table
function is the compact, ClinVar-specific one-pass staging surface used
by
[`rclinvarbitration_import_xml()`](https://sounkou-bioinfo.github.io/RClinVarbitration/reference/rclinvarbitration_import_xml.md).
The connection must have been created with
`duckdb::duckdb(config = list(allow_unsigned_extensions = "true"))`, as
for any locally built DuckDB extension.

## Usage

``` r
rclinvarbitration_enable(con, extension_path = NULL)
```

## Arguments

- con:

  A DuckDB DBI connection.

- extension_path:

  Optional explicit exact-version extension path.

## Value

`con`, invisibly.
