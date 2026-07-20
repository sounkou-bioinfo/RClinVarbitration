
<!-- README.md is generated from README.Rmd. -->

# RClinVarbitration

`RClinVarbitration` streams official ClinVar VCV XML releases into a
DuckDB semantic graph. It has one native SQL scan surface:

``` sql
SELECT * FROM clinvar_xml_statements('ClinVarVCVRelease.xml.gz');
```

The package-owned DuckDB extension uses libxml2’s forward reader, so it
accepts large gzip XML files without an R data frame, an XML DOM, a
staging TSV, or a community-extension ABI dependency. It uses DuckDB’s
version-coupled native C extension API and therefore loads only an exact
engine-version artifact.

Every source XML element becomes a node fact; every parent/child
relationship, attribute, and non-whitespace text segment becomes an
ordered statement. The R helpers materialize four ordinary DuckDB
tables:

- `clinvar_nodes`
- `clinvar_edges`
- `clinvar_literals`
- `clinvar_text`

`clinvar_text` is the discovery substrate. It holds comments,
interpretation explanations, trait names/descriptions, observations,
citation text, and other source text as separately attributable records.
Dense or ColBERT indexing can operate over those rows without discarding
their relationship to the source assertion.

``` r
library(DBI)
library(duckdb)
library(RClinVarbitration)

con <- dbConnect(duckdb(config = list(allow_unsigned_extensions = "true")))
rclinvarbitration_enable(con)
fixture <- system.file(
  "extdata", "VCV_XML_VCV000091629.xml.gz",
  package = "RClinVarbitration", mustWork = TRUE
)
counts <- rclinvarbitration_import_xml(
  con,
  fixture,
  release_id = "ncbi-vcv-sample"
)
cat(paste0("statements: ", counts[["statements"]], "\ntext: ", counts[["text"]], "\n"))
```

    ## statements: 10634
    ## text: 621

``` r
DBI::dbGetQuery(con, "
  SELECT subject_id, text
  FROM clinvar_text
  WHERE release_id = 'ncbi-vcv-sample'
    AND text ILIKE '%pathogenic%'
  ORDER BY ordinal
  LIMIT 20
")
```

    ##            subject_id
    ## 1    clinvar:xml/1/13
    ## 2  clinvar:xml/1/1530
    ## 3  clinvar:xml/1/1537
    ## 4  clinvar:xml/1/1544
    ## 5  clinvar:xml/1/1551
    ## 6  clinvar:xml/1/1555
    ## 7  clinvar:xml/1/1567
    ## 8  clinvar:xml/1/1630
    ## 9  clinvar:xml/1/1723
    ## 10 clinvar:xml/1/1779
    ## 11 clinvar:xml/1/1839
    ## 12 clinvar:xml/1/1860
    ## 13 clinvar:xml/1/1865
    ## 14 clinvar:xml/1/1899
    ## 15 clinvar:xml/1/1928
    ## 16 clinvar:xml/1/1929
    ## 17 clinvar:xml/1/1965
    ## 18 clinvar:xml/1/1974
    ## 19 clinvar:xml/1/2014
    ## 20 clinvar:xml/1/2047
    ##                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       text
    ## 1                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             Sufficient evidence for dosage pathogenicity
    ## 2                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               Pathogenic
    ## 3                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               Pathogenic
    ## 4                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             Pathogenic/Likely pathogenic
    ## 5                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               Pathogenic
    ## 6                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             Pathogenic/Likely pathogenic
    ## 7                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               Pathogenic
    ## 8                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        BRCA1- and BRCA2-associated hereditary breast and ovarian cancer (HBOC) is characterized by an increased risk for female and male breast cancer, ovarian cancer (including fallopian tube and primary peritoneal cancers), and to a lesser extent other cancers such as prostate cancer, pancreatic cancer, and melanoma primarily in individuals with a BRCA2 pathogenic variant. The risk of developing an associated cancer varies depending on whether HBOC is caused by a BRCA1 or BRCA2 pathogenic variant.
    ## 9                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      American College of Medical Genetics and Genomics, Genomic Testing (Secondary Findings) ACT Sheet, BRCA1 and BRCA2 Pathogenic Variants (Hereditary Breast and Ovarian Cancer), 2019
    ## 10                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       BRCA1- and BRCA2-associated hereditary breast and ovarian cancer (HBOC) is characterized by an increased risk for female and male breast cancer, ovarian cancer (including fallopian tube and primary peritoneal cancers), and to a lesser extent other cancers such as prostate cancer, pancreatic cancer, and melanoma primarily in individuals with a BRCA2 pathogenic variant. The risk of developing an associated cancer varies depending on whether HBOC is caused by a BRCA1 or BRCA2 pathogenic variant.
    ## 11                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     American College of Medical Genetics and Genomics, Genomic Testing (Secondary Findings) ACT Sheet, BRCA1 and BRCA2 Pathogenic Variants (Hereditary Breast and Ovarian Cancer), 2019
    ## 12                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              Pathogenic
    ## 13 The c.4357+2T>G intronic pathogenic mutation results from a T to G substitution two nucleotides after coding exon 11 in the BRCA1 gene. This alteration has been observed in ovarian cancer cohorts (Ratajska M et al. J Appl Genet 2015 May;56(2):193-8; Koczkowska M et al. Cancer Med 2016 Jul;5(7):1640-6). This nucleotide position is well conserved in available vertebrate species. In silico splice site analysis predicts that this alteration will weaken the native splice donor site. Other alterations impacting the same donor site (c.4357+1G>A, c.4357+1G>T) have been shown to have a similar impact on splicing (Ambry internal data; Thomassen M et al. Breast Cancer Res Treat 2012 Apr;132:1009-23; Men&eacute;ndez M et al. Breast Cancer Res Treat 2012 Apr;132(3):979-92). Alterations that disrupt the canonical splice site are expected to cause aberrant splicing, resulting in an abnormal protein or a transcript that is subject to nonsense-mediated mRNA decay. As such, this alteration is classified as a disease-causing mutation.
    ## 14                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              Pathogenic
    ## 15                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              Pathogenic
    ## 16                                                                                                                                                                                                                                                                                                            This variant is denoted BRCA1 c.4357+2T>G or IVS12+2T>G and consists of a T>G nucleotide substitution at the +2 position of intron 12 of the BRCA1 gene. Using alternate nomenclature, this variant would be defined as/ has previously been published as BRCA1 4476+2T>G. This variant destroys a canonical splice donor site and is predicted to cause abnormal gene splicing, leading to either an abnormal message that is subject to nonsense-mediated mRNA decay or to an abnormal protein product. This variant has been reported in at least two women with a history of serous ovarian cancer (Ratajska 2015, Koczkowska 2016) We consider this variant to be pathogenic. Based on the current evidence, we consider this variant to be pathogenic.
    ## 17                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              Pathogenic
    ## 18                                                                                                                                                                                                                                                                                                                                      For these reasons, this variant has been classified as Pathogenic. Studies have shown that disruption of this splice site alters mRNA splicing and is expected to lead to the loss of protein expression (PMID: 21735045, 24667779). ClinVar contains an entry for this variant (Variation ID: 91629). Disruption of this splice site has been observed in individual(s) with ovarian cancer (PMID: 25366421, 27167707). This variant is not present in population databases (gnomAD no frequency). This sequence change affects a donor splice site in intron 12 of the BRCA1 gene. RNA analysis indicates that disruption of this splice site induces altered splicing and may result in an absent or disrupted protein product.
    ## 19                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              Pathogenic
    ## 20                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       Likely pathogenic

``` r
DBI::dbDisconnect(con, shutdown = TRUE)
```

ClinVarbitration decision rules are intentionally a later versioned SQL
layer on top of the retained assertion graph. VEP and PM5 remain
DuckHTS/Rduckhts responsibilities and join an on-demand or cached P/LP
view by normalized allele.

## Acknowledgement

[Teague Sterling’s DuckDB Webbed
extension](https://github.com/teaguesterling/duckdb_webbed) informed the
initial assessment of SQL-native XML ingestion and was tested against
NCBI’s real VCV XML. RClinVarbitration does not vendor or execute
Webbed: it uses a package-owned libxml2 forward scan because the
supported R DuckDB engine requires an exact native artifact and ClinVar
publishes the full release as gzip XML.
