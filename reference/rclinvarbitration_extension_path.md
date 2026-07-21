# Locate a version-matched RClinVarbitration DuckDB extension

The package uses DuckDB's unstable C extension ABI for its streaming
table function, so it bundles one artifact per supported exact engine
release.

## Usage

``` r
rclinvarbitration_extension_path(duckdb_version = NULL)
```

## Arguments

- duckdb_version:

  Exact DuckDB version, with or without a `v` prefix. `NULL` selects the
  version reported by the installed `duckdb` package.

## Value

An absolute extension path.
