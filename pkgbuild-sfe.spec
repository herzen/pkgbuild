# This spec assumes that it is run inside pkgbuild's git repository.
# It also assumes that you already have pkgbuild installed and
# a local IPS repository set up.

# Install in /opt/dtbld to avoid conflict with system pkgbuild
# Use pkgbuild --define 'pkgbuild_prefix /path/to/dir'
# to define a different install prefix.

%{?!pkgbuild_prefix:%define pkgbuild_prefix /opt/dtbld}
%define _prefix %pkgbuild_prefix
%define branch_name sfe

Name:         pkgbuild
IPS_Package_Name: sfe/package/pkgbuild
License:      GPLv2
Group:        System/Packaging
URL:	      http://github.com/herzen/pkgbuild
Version:      1.4.0
Summary:      rpmbuild-like tool for building Solaris packages
Source:       http://github.com/herzen/pkgbuild/archive/pkgbuild-%branch_name.zip
BuildRequires:	library/perl-5/yaml-libyaml
Requires:	library/perl-5/yaml-libyaml

%description
A tool for building Solaris IPS packages based on RPM spec files.
Most features and some extensions of the spec format are implemented.

%prep
%setup -c -T -q -n pkgbuild-%branch_name
cd %(pwd)
git archive HEAD | (cd %_builddir/pkgbuild-%branch_name; gtar xf -)

%build
./autogen.sh
./configure --prefix=%_prefix
make

%install
make DESTDIR=%buildroot install

%clean
rm -rf %buildroot

%files
%defattr (-, root, bin)
%doc COPYING AUTHORS NEWS
%dir %attr (0755, root, sys) %_datadir
%dir %attr (0755, root, other) %_datadir/doc
%attr (0755, root, bin) %_bindir
%attr (0755, root, bin) %_libdir
%_datadir/%name
%_mandir

%changelog
Sun Aug 21 2016 - Alex Viskovatoff
- import spec from sfe-tools and modify it to use files from the git archive
  to avoid the extra step of creating a source tarball
