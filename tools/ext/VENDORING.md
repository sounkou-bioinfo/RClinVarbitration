# Native dependency boundary

The native extension is intentionally small:

- DuckDB v1.5.3 C extension headers are pinned under `duckdb_capi/v1.5.3/`.
  `duckdb_headers.json` records their upstream revision.
- libxml2 is presently a host dependency discovered by `pkg-config`. The
  extension does not call libxml2 outside `rclinvarbitration_extension.c`.
- The package builds one artifact per exact DuckDB engine version and records
  `C_STRUCT_UNSTABLE` metadata. It must never load a nearby-version artifact.

A future platform expansion must either vendor a pinned static libxml2 build
with hidden symbols or add a documented platform adapter. It must not replace
the streaming parser with an R XML DOM or a community-extension runtime load.
