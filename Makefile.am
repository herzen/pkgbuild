topdir = @TOPDIR@

gen_modules =        rpm_spec.pm
gen_module_sources = rpm_spec.pm.in
plain_modules = packagebase.pm  rpm_file.pm  rpm_package.pm
all_modules = $(gen_modules) $(plain_modules)

pkgbuilddir = $(PKGBUILD_LIBDIR)
pkgbuild_DATA = $(all_modules) get_rpm_topdir
pkgbuild_SCRIPTS = pkgbuild.pl pkgbuild-postprocess
bin_SCRIPTS = pkgbuild

EXTRA_DIST= pkgbuild.spec.in $(plain_modules) $(gen_module_sources) \
	TODO get_rpm_topdir pkgbuild-postprocess

if ENABLE_STICKY_DIRS
DIRMODE=1777
else
DIRMODE=644
endif

install-data-local:
	$(INSTALL) -m $(DIRMODE) -d $(DESTDIR)$(topdir)/BUILD
	$(INSTALL) -m $(DIRMODE) -d $(DESTDIR)$(topdir)/SPECS
	$(INSTALL) -m $(DIRMODE) -d $(DESTDIR)$(topdir)/SOURCES
	$(INSTALL) -m $(DIRMODE) -d $(DESTDIR)$(topdir)/PKGS
	$(INSTALL) -m $(DIRMODE) -d $(DESTDIR)$(topdir)/SPKGS
	$(INSTALL) -m 755 -d $(DESTDIR)$(topdir)/PKGMAPS
	$(INSTALL) -m $(DIRMODE) -d $(DESTDIR)$(topdir)/PKGMAPS/proto
	$(INSTALL) -m $(DIRMODE) -d $(DESTDIR)$(topdir)/PKGMAPS/pkginfo
	$(INSTALL) -m $(DIRMODE) -d $(DESTDIR)$(topdir)/PKGMAPS/depend
	$(INSTALL) -m $(DIRMODE) -d $(DESTDIR)$(topdir)/PKGMAPS/copyright
	$(INSTALL) -m $(DIRMODE) -d $(DESTDIR)$(topdir)/PKGMAPS/scripts

uninstall-local:
	DIR=$(DESTDIR)$(topdir)/BUILD; rmdir $$DIR || echo "WARNING: $$DIR not empty; not removing"
	DIR=$(DESTDIR)$(topdir)/SPECS; rmdir $$DIR || echo "WARNING: $$DIR not empty; not removing"
	DIR=$(DESTDIR)$(topdir)/SOURCES; rmdir $$DIR || echo "WARNING: $$DIR not empty; not removing"
	DIR=$(DESTDIR)$(topdir)/PKGS; rmdir $$DIR || echo "WARNING: $$DIR not empty; not removing"
	DIR=$(DESTDIR)$(topdir)/SPKGS; rmdir $$DIR || echo "WARNING: $$DIR not empty; not removing"
	DIR=$(DESTDIR)$(topdir)/PKGMAPS/proto; rmdir $$DIR || echo "WARNING: $$DIR not empty; not removing"
	DIR=$(DESTDIR)$(topdir)/PKGMAPS/pkginfo; rmdir $$DIR || echo "WARNING: $$DIR not empty; not removing"
	DIR=$(DESTDIR)$(topdir)/PKGMAPS/depend; rmdir $$DIR || echo "WARNING: $$DIR not empty; not removing"
	DIR=$(DESTDIR)$(topdir)/PKGMAPS/copyright; rmdir $$DIR || echo "WARNING: $$DIR not empty; not removing"
	DIR=$(DESTDIR)$(topdir)/PKGMAPS/scripts; rmdir $$DIR || echo "WARNING: $$DIR not empty; not removing"
	DIR=$(DESTDIR)$(topdir)/PKGMAPS; rmdir $$DIR || echo "WARNING: $$DIR not empty; not removing"
