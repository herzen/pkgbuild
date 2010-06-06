AUTOMAKE_OPTIONS = dist-bzip2

topdir = @TOPDIR@

SUBDIRS = m4 doc

gen_modules = \
	rpm_spec.pm \
	pkgdb.pm
gen_module_sources = \
	rpm_spec.pm.in \
	pkgdb.pm.in
plain_modules = \
	packagebase.pm \
	rpm_file.pm \
	rpm_package.pm \
	config.pm \
	ips_utils.pm \
	ips_package.pm
all_modules = $(gen_modules) $(plain_modules)

pkgbuilddir = $(PKGBUILD_LIBDIR)
pkgbuild_DATA = $(all_modules) \
	get_rpm_topdir \
	pkgnames \
	macros \
	version-file
pkgbuild_SCRIPTS = \
	pkgbuild.pl \
	pkgbuild-postprocess \
	spectool.pl \
	pkgtool.pl
pkgbuild_PROGRAMS = \
	pkgdbgrep
bin_SCRIPTS = \
	pkgbuild \
	spectool \
	pkgtool

pkgdbgrep_SOURCES = \
	pkgdbgrep.c

pkgdbgrep_CFLAGS = \
	-D_LARGEFILE64_SOURCE \
	-DPKGBUILD_VERSION=\"@PKGBUILD_VERSION@\"

EXTRA_DIST= $(plain_modules) $(gen_module_sources) \
	pkgbuild.spec.in \
	pkgbuild.spec \
	TODO \
	get_rpm_topdir \
	spectool.in \
	spectool.pl \
	pkgtool.pl \
	pkgbuild-postprocess \
	pkgnames \
	macros.in \
	version-file.in

