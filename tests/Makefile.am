EXTRA_DIST = $(TESTS) do-test.pl.in
TESTS = test-simple
SUBDIRS = SOURCES SPECS

testsubdir = BUILD

$(TESTS): $(testsubdir) .do-test.pl

TESTS_ENVIRONMENT = top_builddir=$(top_builddir)

all: .do-test.pl
.do-test.pl: Makefile do-test.pl.in
	(cd $(top_builddir); ./config.status)
	chmod a+x do-test.pl

$(testsubdir):
	mkdir -p $(testsubdir)

distclean-local:
	-rm -rf $(testsubdir)

PHONY: .do-test.pl
