# RClinVarbitration: relational ClinVar evidence in DuckDB

A DuckDB-native, XML-first ClinVar store. Its package-owned native
extension streams official `.xml.gz` VCV releases through libxml2 in one
pass. SQL materializes VCV, allele, location, gene, RCV, SCV, condition,
observation, citation, attribute, and evidence-text relations; versioned
ClinVarbitration policy is deliberately derived from those source
records.

## See also

Useful links:

- <https://github.com/sounkou-bioinfo/RClinVarbitration>

- <https://sounkou-bioinfo.github.io/RClinVarbitration/>

- Report bugs at
  <https://github.com/sounkou-bioinfo/RClinVarbitration/issues>

## Author

**Maintainer**: Sounkou Mahamane Toure <sounkoutoure@gmail.com>

Authors:

- Sounkou Mahamane Toure <sounkoutoure@gmail.com>

Other contributors:

- DuckDB Foundation (Bundled DuckDB C extension headers) \[copyright
  holder\]

- Centre for Population Genomics (ClinVarbitration 2.2.11
  decision-policy semantics) \[copyright holder\]
