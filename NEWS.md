# RClinVarbitration development news

## 0.1.1

- Bundle exact `C_STRUCT_UNSTABLE` extension artifacts for DuckDB `v1.5.0`
  through `v1.5.4`, selected from the enabled connection's engine version.
- Replace generic XML node/edge/statement persistence with a one-pass compact
  semantic staging scan and focused VCV, allele, location, gene, RCV, SCV,
  condition, observation, citation, attribute, and evidence-text relations.
- Keep README execution fast and deterministic with the bundled unaltered NCBI
  VCV record; full multi-gigabyte releases are imported once into file-backed
  DuckDB databases rather than reparsed while rendering documentation.

## 0.1.0

- First public release.
- Added a package-owned DuckDB C extension with
  `clinvar_xml_statements(path)`, a single-threaded libxml2 forward scan of
  ClinVar VCV XML and XML.GZ releases.
- Added semantic SQL materialization for ordered XML nodes, edges, literals,
  and discovery text, with a real NCBI VCV XML.GZ fixture.
- The first artifact supports exactly DuckDB `v1.5.3` on Unix-like hosts; it
  fails closed for other engine versions.
