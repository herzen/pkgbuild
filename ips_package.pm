#
#  A module representing an IPS package
#
#  Copyright (c) 2010, Oracle and/or its affiliates. All rights reserved.
#
#  pkgbuild is free software; you can redistribute it and/or
#  modify it under the terms of the GNU General Public License 
#  version 2 published by the Free Software Foundation.
#
#  pkgbuild is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#  General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
#  As a special exception to the GNU General Public License, if you
#  distribute this file as part of a program that contains a
#  configuration script generated by Autoconf, you may include it under
#  the same distribution terms that you use for the rest of that program.
#
#  Authors:  Laszlo Peter  <laca@sun.com>
#

# FIXME
# FIXME
# FIXME
# BIG FAT WARNING: this module currently only works for publishing
#                  incorporations and package groups, not for "normal"
#                  packages, since it does not handle files, dirs, etc.

use strict;
use warnings;
use ips_utils;
use File::Basename;

package ips_package;

my $ips_utils = new ips_utils;

my $ips_server = $ENV{PKGBUILD_IPS_SERVER};
if (not defined($ips_server)) {
    if (defined ($ips_utils)) {
	$ips_server = $ips_utils->get_local_ips_server();
    }
}

# create a new ips_package object
sub new ($;$$) {
    my $class = shift;
    my $name = shift;
    my $version = shift;
    my $self = {};

    $self->{_name} = $name;
    $self->{_basename} = File::Basename::basename ($name);
    $self->{_dependencies} = {};
    $self->{_attributes} = {};
    $self->{_changed} = 0;

    bless ($self, $class);
    return $self;
}

sub set_name($$) {
    my $self = shift;
    my $name = shift;
    if ($name ne $self->{_name}) {
	$self->{_name} = $name;
	$self->{_basename} = File::Basename::basename ($name);
	$self->{_changed} = 1;
    }
}

sub get_name($) {
    my $self = shift;
    return $self->{_name};
}

sub get_fmri($) {
    my $self = shift;
    return $self->{_fmri} if defined ($self->{_fmri});
    return $self->{_name};
}

sub set_version($$) {
    my $self = shift;
    my $version = shift;
    if ($version ne $self->{_version}) {
	$self->{_version} = $version;
	$self->{_changed} = 1;
    }
}

sub _fatal ($) {
    my $msg = shift;
    print STDERR "$msg\n";
    return 0;
}

sub changed ($) {
    my $self = shift;
    return $self->{_changed};
}

# create a new ips_package object by loading an fmri
sub new_from_fmri($$) {
    my $class = shift;
    my $fmri = shift;
    my $self = {};

    $self->{_dependencies} = {};
    $self->{_attributes} = {};
    $self->{_fmri} = $fmri;
    $self->{_changed} = 0;

    bless ($self, $class);
    $self->load_from_fmri() or return undef;
    $self->{_changed} = 0;
    # Some versions of pkg have pkg.fmri others have fmri yet others have both.
    # pkg.fmri tends to have the publisher in it, fmri doesn't.
    if (not defined ($self->{_attributes}->{'pkg.fmri'})) {
	$self->{_attributes}->{'pkg.fmri'} = $self->{_attributes}->{'fmri'};
    }
    $self->{_name} = $self->{_attributes}->{'pkg.fmri'};
    $self->{_name} =~ s/(\S+)@.*/$1/;
    # pkg://publisher/package/name
    $self->{_name} =~ s/^pkg:\/\/[^\/]+\/(\S+)/$1/;
    # pkg:/package/name
    $self->{_name} =~ s/^pkg:\/(\S+)/$1/;
    $self->{_basename} = File::Basename::basename ($self->{_name});
    # everything after the @ is version
    $self->{_version} = $self->{_attributes}->{'pkg.fmri'};
    $self->{_version} =~ s/^.*@(\S+):.*/$1/;
    return $self;    
}

# add a dependency to an ips_package object
sub add_depend($$$;$) {
    my $self = shift;
    my $fmri = shift;
    my $type = shift;
    my $variant_arch = shift;

    my $version = $fmri;
    $version =~ s/^\S+@//;
    if (not $fmri =~ /@/) {
	$version = undef;
    }
    $fmri =~ s/^(\S+)@.*/$1/;
    $fmri =~ s/^pkg:\///;
    $self->{_changed} = 1;

    $self->{_dependencies}->{$fmri}->{'type'} = $type;
    $self->{_dependencies}->{$fmri}->{'version'} = $version;
    $self->{_dependencies}->{$fmri}->{'arch'} = $variant_arch;
}

# split an IPS version string into components, as defined in pkg(5)
sub version_split($) {
    my $version_string = shift;

    # anything before the "," (or "-" or ":")
    my $component_version = $version_string;
    $component_version =~ s/[,:-].*//;

    # after the "," (if any)
    my $build_version = $version_string;
    if ($build_version =~ /,/) {
	$build_version =~ s/^.*,//;
	$build_version =~ s/[-:].*//;
    } else {
	$build_version = "";
    }

    # after the "-" (if any)
    my $vendor_version = $version_string;
    if ($vendor_version =~ /-/) {
	$vendor_version =~ s/^.*-//;
	$vendor_version =~ s/:.*//;
    } else {
	$vendor_version = "";
    }

    # after the ":" (if any)
    my $timestamp = $version_string;
    if ($timestamp =~ /:/) {
	$timestamp =~ s/^.*://;
    } else {
	$timestamp = "";
    }

    return ($component_version, $build_version, $vendor_version, $timestamp);
}

# compare 2 ips version strings.  Assume that they match if some parts
# of the string are unspecified but the ones specified in both strings match
# return 1 for a match, 0 for a mismatch
sub version_match($$) {
    my $version1 = shift;
    my $version2 = shift;

    return 0 unless defined ($version1);
    return 0 unless defined ($version2);

    my ($cv1, $bv1, $vv1, $ts1) = version_split ($version1);
    my ($cv2, $bv2, $vv2, $ts2) = version_split ($version2);

#    print "DEBUG: $version1 -> $cv1 - $bv1 - $vv1 - $ts1\n";
#    print "DEBUG: $version2 -> $cv2 - $bv2 - $vv2 - $ts2\n";

    return 0 if ($cv1 ne "" and $cv2 ne "" and $cv1 ne $cv2);
    return 0 if ($bv1 ne "" and $bv2 ne "" and $bv1 ne $bv2);
    return 0 if ($vv1 ne "" and $vv2 ne "" and $vv1 ne $vv2);
    return 0 if ($ts1 ne "" and $ts2 ne "" and $ts1 ne $ts2);

    return 1;
}

# update a dependency with a new version
# return 1 if an update was needed, 0 otherwise
sub update_depend($$$) {
    my $self = shift;
    my $name = shift;
    my $version = shift;

    if (defined ($self->{_dependencies}->{$name})) {
	if (not version_match ($self->{_dependencies}->{$name}->{'version'},
			   $version)) {
	    $self->{_dependencies}->{$name}->{'version'} = $version;
	    $self->{_changed} = 1;
	    return 1;
	}
    }
    return 0;
}

# FIXME: add files, dirs, etc.
sub add_file($$$$$) {
    my $self = shift;

    return 0;
}

# add an attribute to an ips_package object
sub add_attribute($$$) {
    my $self = shift;
    my $name = shift;
    my $value = shift;

    $self->{_attributes}->{$name} = $value;
    $self->{_changed} = 1;
}

# load the contents of a pkg from an fmri
sub load_from_fmri($) {
    my $self = shift;

    return 0 if not defined ($self->{_fmri});

    my @manifest = `pkg contents -m $self->{_fmri}`;
    if ($? != 0) {
	return 0;
    }

    foreach my $line (@manifest) {
	if ($line =~ /^depend fmri=(\S+) type=(\S+)/) {
	    $self->add_depend($1, $2);
	}
	if ($line =~ /^depend fmri=(\S+) type=(\S+) variant.arch=(\S+)$/) {
	    $self->add_depend($1, $2, $3);
	}
	if ($line =~ /^set name=(\S+) value=(.*)/) {
	    $self->add_attribute($1, $2);
	}
    }

    return 1;
}

sub write_manifest($$) {
    my $self = shift;
    my $pkgmapsdir = shift;

    my $fname = $self->{_basename} . ".manifest";

    open MANIFEST, ">$pkgmapsdir/manifests/$fname" or
	return _fatal ("failed to create file $pkgmapsdir/manifests/$fname");

    foreach my $name (keys %{$self->{_attributes}}) {
	next if $name eq "fmri";
	next if $name eq "pkg.fmri";
	print MANIFEST "set name=$name value=$self->{_attributes}->{$name}\n";
    }
    foreach my $dep (keys %{$self->{_dependencies}}) {
	my $v = "";
	if (defined ($self->{_dependencies}->{$dep}->{'version'})) {
	    my $v = "@" . $self->{_dependencies}->{$dep}->{'version'};
	}
	if (defined ($self->{_dependencies}->{$dep}->{'variant_arch'})) {
	    print MANIFEST "depend fmri=${dep}${v}" .
		" type=$self->{_dependencies}->{$dep}->{'type'} " .
		"variant.arch=" .
		"$self->{_dependencies}->{$dep}->{'variant_arch'}\n";
	} else {
	    print MANIFEST "depend fmri=${dep}${v}" .
		" type=$self->{_dependencies}->{$dep}->{'type'}\n";
	}
    }

    # FIXME: write other file types

    close MANIFEST;
}

sub _push_manifest($$) {
    my $self = shift;
    my $pkgmapsdir = shift;

    my $fname = $self->{_basename} . "_ips.sh";
    my $manifest_name = $self->{_basename} . ".manifest";

    open SCRIPT, ">$pkgmapsdir/scripts/$fname" or
	return _fatal ("failed to create file $pkgmapsdir/scripts/$fname");

    print SCRIPT "#!/usr/bin/bash\n";
    print SCRIPT "export PKG_REPO=\${PKGBUILD_SRC_IPS_SERVER:-\${PKGBUILD_IPS_SERVER:-$ips_server}}\n";
    print SCRIPT "eval `pkgsend open $self->{_name}@" .
	$self->{_version} . "` || exit 1\n";
    print SCRIPT "pkgsend include $pkgmapsdir/manifests/$manifest_name || exit 2\n";
    print SCRIPT "pkgsend close || exit 3\n";

    close SCRIPT;
}

sub publish($$) {
    my $self = shift;
    my $pkgmapsdir = shift;

    return "UNCHANGED" if (not $self->{_changed});

    $self->write_manifest($pkgmapsdir) or return undef;
    $self->_push_manifest($pkgmapsdir) or return undef;

    my $script = "$pkgmapsdir/scripts/$self->{_basename}" . "_ips.sh";
    `chmod +x $script`;
    my $msg = `$script`;
    print $msg;
    if ($?) {
	return undef;
    }

    if (defined ($msg) and $msg =~ /^PUBLISHED\n(pkg:\/[^@]+@[^\n]+)/s) {
	$self->{_fmri} = $1;
	$self->{_changed} = 0;
	return $1;
    } elsif (defined ($msg) and $msg =~ /^(pkg:\/[^@]+@[^\n]+)\nPUBLISHED/s) {
	$self->{_fmri} = $1;
	$self->{_changed} = 0;
	return $1;
    } else {
	return undef;
    }
}

1;
