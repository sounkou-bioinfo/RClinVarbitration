# Changelog

## RClinVarbitration 0.1.1

- Add experimental webR/WebAssembly support. The package now builds its
  version-matched DuckDB extension as an Emscripten side module and has
  a browser smoke test that loads it and imports the compressed VCV
  fixture.

- Project compact parser rows with the package-owned
  `rclinvar_json_field()` scalar rather than DuckDB’s separately
  downloadable JSON extension. Imports now require no extension
  download, including in browser/webR runtimes.

- Remove the premature local `v1` policy suffix; preserve the pinned
  `cpg-clinvarbitration-2.2.11` identifier, source-order strong-review
  rule, and separate disease- and allele-level decision views.

- Add Parquet exporters for the VCV-derived allele policy and for
  direct, SQL-only reproduction of ClinVarbitration from versioned NCBI
  flat-file archives, plus a retained differential script for published
  Zenodo releases.

- Retain imported SCV source order for deterministic strong-review
  decisions.

- Bundle exact `C_STRUCT_UNSTABLE` extension artifacts for DuckDB
  `v1.5.0` through `v1.5.4`, selected from the enabled connection’s
  engine version.

- Replace generic XML node/edge/statement persistence with a one-pass,
  ClinVar-specific entity scan and focused VCV, allele, location, gene,
  RCV, SCV, condition, observation, citation, attribute, and
  evidence-text relations. Staging now stores one JSON-backed row per
  selected entity and requires no release-wide EAV grouping.
  Release-scale tables use logical keys without memory-resident ART
  indexes, and each projection commits separately; the release catalogue
  marks completion and failed imports clean partial rows.

- Add `clinvar_disease_aggregates` and `clinvar_disease_submissions` as
  direct RCV- and SCV-level disease-policy inputs, with canonical
  disease identifiers selected independently of the complete retained
  cross-reference relation.

- Add the `cpg-clinvarbitration-2.2.11` SQL policy, configurable
  submitter-blinding profiles, and `clinvar_policy_pathogenic_alleles`
  as the disease-specific P/LP join surface for Rduckhts/DuckHTS.

- Require README execution against the complete official VCV XML.GZ in
  one file-backed import; all displayed summaries query that persisted
  import and never rescan XML.

## RClinVarbitration 0.1.0

- First public release.
- Added a package-owned DuckDB C extension with
  `clinvar_xml_statements(path)`, a single-threaded libxml2 forward scan
  of ClinVar VCV XML and XML.GZ releases.
- Added semantic SQL materialization for ordered XML nodes, edges,
  literals, and discovery text, with a real NCBI VCV XML.GZ fixture.
- The first artifact supports exactly DuckDB `v1.5.3` on Unix-like
  hosts; it fails closed for other engine versions.
