topdir=@TOPDIR@

bin_SCRIPTS=pkgbuild

pkgbuilddir=$(libdir)/pkgbuild-@PKGBUILD_VERSION@

modules=packagebase.pm  rpm_file.pm  rpm_package.pm  rpm_spec.pm
pkgbuild_DATA=$(modules)
pkgbuild_SCRIPTS=pkgbuild.pl

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
