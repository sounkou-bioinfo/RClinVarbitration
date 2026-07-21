# Keep this release artifact name in sync with DESCRIPTION.
PKG = RClinVarbitration
VER = 0.1.1
TAR = $(PKG)_$(VER).tar.gz

.PHONY: rd build install rdm test check clean

rd:
	Rscript -e 'roxygen2::roxygenize(load_code = "source")'

build: rd
	R CMD build .

install: build
	R CMD INSTALL --preclean $(TAR)

# The README is a full-release integration run, not a fixture smoke test.
rdm: install
	@test -n "$$CLINVAR_VCV_XML_FILE" && test -f "$$CLINVAR_VCV_XML_FILE" || (echo "ERROR: set CLINVAR_VCV_XML_FILE to ClinVarVCVRelease_00-latest.xml.gz" >&2; exit 1)
	@test -n "$$CLINVAR_RELEASE_ID" || (echo "ERROR: set CLINVAR_RELEASE_ID to an immutable ClinVar release label" >&2; exit 1)
	Rscript -e 'rmarkdown::render("README.Rmd", output_file = "README.md", quiet = TRUE)'
	rm -f README.html

test: install
	Rscript -e 'tinytest::test_package("RClinVarbitration", ncpu = 1L)'

check: build
	R CMD check --no-manual $(TAR)

clean:
	rm -rf $(PKG).Rcheck $(TAR) man
	rm -rf inst/rclinvarbitration_extension/build
