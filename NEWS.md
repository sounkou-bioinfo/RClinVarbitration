# RClinVarbitration development news

## 0.1.0

- First public release.
- Added a package-owned DuckDB C extension with
  `clinvar_xml_statements(path)`, a single-threaded libxml2 forward scan of
  ClinVar VCV XML and XML.GZ releases.
- Added semantic SQL materialization for ordered XML nodes, edges, literals,
  and discovery text, with a real NCBI VCV XML.GZ fixture.
- The first artifact supports exactly DuckDB `v1.5.3` on Unix-like hosts; it
  fails closed for other engine versions.
