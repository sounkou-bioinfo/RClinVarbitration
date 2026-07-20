# Keep this release artifact name in sync with DESCRIPTION.
PKG = RClinVarbitration
VER = 0.1.0
TAR = $(PKG)_$(VER).tar.gz

.PHONY: rd build install rdm test check clean

rd:
	Rscript -e 'roxygen2::roxygenize(load_code = "source")'

build: rd
	R CMD build .

install: build
	R CMD INSTALL --preclean $(TAR)

# Render the executable README against the just-installed package and clean its
# transient HTML companion so it cannot enter a source release.
rdm: install
	Rscript -e 'rmarkdown::render("README.Rmd", output_file = "README.md", quiet = TRUE)'
	rm -f README.html

test: install
	Rscript -e 'tinytest::test_package("RClinVarbitration", ncpu = 1L)'

check: build
	R CMD check --no-manual $(TAR)

clean:
	rm -rf $(PKG).Rcheck $(TAR) man
	rm -rf inst/rclinvarbitration_extension/build
