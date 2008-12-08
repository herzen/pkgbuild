#
#  The pkgbuild build engine
#
#  Copyright 2008 Sun Microsystems, Inc.  All rights reserved.
#  Use is subject to license terms.
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

use strict;
use warnings;
use Socket;
use Sys::Hostname;

my $my_hostname = hostname ();

package ips_utils;

sub new ($;$) {
    my $class = shift;
    my $altroot = shift;
    my $self = {};

    $self->{_altroot} = $altroot;
    $altroot = "" if not defined ($altroot);

    if (! -f "${altroot}/var/pkg/cfg_cache") {
	return undef;
    }
    $self->{_authorities} = {};
    $self->{_properties} = {};
    $self->{_filter} = {};
    $self->{_unknown} = {};
    bless ($self, $class);
    $self->read_cfg_cache ();
    return $self;
}

sub read_cfg_cache ($) {
    my $self = shift;

    my $altroot = $self->{_altroot};
    $altroot = "" if not defined ($altroot);

    open CFG_CACHE, "<${altroot}/var/pkg/cfg_cache" or
	die "Cannot open IPS configuration file";
    my $pkgbuild_ips_host;
    my $pkgbuild_ips_port;
    my $pkgbuild_ips_server = $ENV{PKGBUILD_IPS_SERVER};
    if (defined ($pkgbuild_ips_server)) {
	if ($pkgbuild_ips_server =~ /^http:\/\/([^:]+):([0-9]+)\//) {
	    $pkgbuild_ips_host = $1;
	    $pkgbuild_ips_port = $2;
	}
    }
    my $section;
    my $authority;
    while (my $line = <CFG_CACHE>) {
	chomp ($line);
	if ($line =~ /^#/) {
	    next;
	} elsif ($line =~ /^\s*$/) {
	    next;
	} elsif ($line =~ /^\[authority_([a-zA-Z0-9._-]+)\]$/) {
	    $authority = $1;
	    $section = '_authorities';
	    $self->{_authorities}->{$authority} = {};
	} elsif ($line eq '[filter]') {
	    $section = '_filter';
	    $authority = undef;
	} elsif ($line eq '[property]') {
	    $section = '_properties';
	    $authority = undef;
	} elsif ($line =~ /^\[(.*)\]$/) {
	    print "ips_utils: unknown section $1\n";
	    $section = '_unknown';
	    $authority = undef;
	} else {
	    if ($line =~ /^([a-zA-Z_0-9-]+) = (.+)$/) {
		my $key = $1;
		my $val = $2;
		if (defined ($authority)) {
		    $self->{_authorities}->{$authority}->{$key} = $val;
		    if ($key eq "origin") {
			if ($val =~ /^http:\/\/(.+):(.+)\/$/) {
			    my $host = $1;
			    my $port = $2;
			    my $local_port = $self->get_local_ips_port ();
			    if ($port == $local_port) {
				my $packed_ip = gethostbyname ($host);
				my $local_packed_ip = 
				    gethostbyname ($my_hostname);
				if (defined $packed_ip and
				    defined $local_packed_ip) {
				    my $ip_address = Socket::inet_ntoa($packed_ip);
				    my $local_ip = Socket::inet_ntoa ($local_packed_ip);
				    if (($ip_address eq $local_ip) or
					($ip_address eq "127.0.0.1")) {
					$self->{_local_authority} = $authority;
				    }
				}
				
			    }
			    if (defined ($pkgbuild_ips_server) and
				($port == $pkgbuild_ips_port)) {
				my $packed_ip = gethostbyname ($host);
				my $pkgbuild_packed_ip = 
				    gethostbyname ($pkgbuild_ips_host);
				if (defined $packed_ip and
				    defined $pkgbuild_packed_ip) {
				    my $ip_address = Socket::inet_ntoa($packed_ip);
				    my $pkgbuild_ip = Socket::inet_ntoa ($pkgbuild_packed_ip);
				    if (($ip_address eq $pkgbuild_ip) or
					($ip_address eq "127.0.0.1")) {
					$self->{_pkgbuild_authority} = $authority;
				    }
				}
				
			    }
			}
		    }
		} else {
		    $self->{$section}->{$1} = $2;
		}
	    } else {
		print "ips_utils: failed to parse line: $line\n";
	    }
	}
    }
    close CFG_CACHE;
    if (not defined ($pkgbuild_ips_server)) {
	$self->{_pkgbuild_authority} = $self->{_local_authority};
    }
}

sub get_authority_setting ($$$) {
    my $self = shift;
    my $auth_name = shift;
    my $setting = shift;

    return $self->{_authorities}->{$auth_name}->{$setting};
}

sub get_local_ips_port ($) {
    my $self = shift;

    if (not defined ($self->{_local_ips_port})) {
	my $port = `/usr/bin/svcprop -p pkg/port svc:/application/pkg/server:default`;
	chomp ($port);
	$self->{_local_ips_port} = $port;
    }
    return $self->{_local_ips_port};
}

sub get_local_ips_server ($) {
    my $self = shift;

    if (not defined ($self->{_local_ips_server})) {
	my $port = $self->get_local_ips_port ();
	$self->{_local_ips_server} = "http://localhost:$port";
    }
    return $self->{_local_ips_server};
}

sub get_local_authority ($) {
    my $self = shift;

    return $self->{_local_authority};
}

sub get_pkgbuild_authority ($) {
    my $self = shift;

    return $self->{_pkgbuild_authority};
}

sub is_depotd_enabled ($) {
    my $self = shift;

    if (not defined ($self->{_depotd_enabled})) {
	my $server_state = `svcs -H -o STATE svc:/application/pkg/server:default`;
	if ($server_state eq "online\n") {
	    $self->{_depotd_enabled} = 1;
	} else {
	    $self->{_depotd_enabled} = 0;
	}
    }
    return $self->{_depotd_enabled};
}

1;