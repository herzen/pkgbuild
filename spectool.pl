#!/usr/bin/perl
#
#  A tool for extracting various info from rpm spec files
#
#  Copyright (C) 2004, 2005 Sun Microsystems, Inc.
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
use Getopt::Long qw(:config gnu_compat no_auto_abbrev bundling pass_through);
use rpm_spec;
use config;
use ips_utils;

my $ips_utils = new ips_utils ();

# --------- global vars ----------------------------------------------------
# config settings
my $spec_command;
my $spec_cmd_arg;
my @spec_names = ();
my @specs = ();
my $spec_counter = 0;
my @predefs = ();
my $defaults;
my $pkgbuild_path = "pkgbuild";
my $build_engine = "pkgbuild";
my $logname = $ENV{USER} || $ENV{LOGNAME} || `logname`;
chomp ($logname);
my $_homedir = $ENV{HOME};
my $topdir = "${_homedir}/packages";
my $read_rc = 1;
my $exit_val = 0;
my $full_path = 0;
my $long_output = 0;
my $ips;
my $svr4;
# --------- messages -------------------------------------------------------
sub print_message ($$) {
    my $min_verbose = shift;
    my $message = shift;
    
    chomp $message;
    
    my $verbose = $defaults->get ('verbose');
    if ($verbose > $min_verbose) {
	print "$message\n";
    }
}

sub msg_info ($$) {
    my $min_verbose = shift;
    my $message = shift;
    
    print_message ($min_verbose, "INFO: $message");
}

sub msg_error ($) {
    my $message = shift;
    
    print_message (-1, "ERROR: $message");
}

sub msg_warning ($$) {
    my $min_verbose = shift;
    my $message = shift;
    
    print_message ($min_verbose, "WARNING: $message");
}

sub init () {
    my $uid;
    if (-x "/usr/xpg4/bin/id") {
	$uid = `/usr/xpg4/bin/id -u`;
	chomp ($uid);
    } else {
	$uid = `LC_ALL=C /bin/id`;
	chomp ($uid);
	$uid =~ s/^[^=]+=([0-9]+)\(.*$/$1/;
    }
    
    if ($uid eq (getpwnam($logname))[2]) {
	$_homedir = (getpwnam($logname))[7];
    } else {
	# logname is incorrect, look up the uid
	$logname = (getpwuid($uid))[0];
	$_homedir = (getpwuid($uid))[7];
    }
    if (defined ($ENV{PKGBUILD_IPS_SERVER}) or
	(defined($ips_utils) and $ips_utils->is_depotd_enabled())) {
	$ips = 1;
	$svr4 = undef;
    } else {
	$ips = undef;
	$svr4 = 1;
    }
}

# --------- functions to process the command line args ---------------------
sub process_defaults () {
    $topdir = rpm_spec::get_topdir ($build_engine, \@predefs);
    my $default_spec_dir = "$topdir/SPECS";

    $defaults = config->new ();
    $defaults->add ('target', 's', 
		    'the value of the --target option passed on to rpm');
    $defaults->add ('logdir', 's',
		    'the directory for saving log files',
		    '/tmp');
    $defaults->add ('logdir_url', 's',
		    'a URL pointing to the log directory (used in the HTML build report)',
		    'file:///tmp');
    $defaults->add ('tarballdirs', 's',
		    'colon (:) separated list of directories where source tarballs are searched for',
		    "%{topdir}/SOURCES");
    $defaults->add ('sourcedirs', 's',
		    'colon (:) separated list of directories where extra sources (not tarballs) are searched for',
		    "%{topdir}/SOURCES");
    $defaults->add ('specdirs', 's',
		    'colon (:) separated list of directories where spec files are searched for',
		    "%{topdir}/SPECS");
    $defaults->add ('patchdirs', 's',
		    'colon (:) separated list of directories where source patches are searched for',
		    "%{topdir}/SOURCES");
    $defaults->add ('nightly', '!',
		    'suffix the Release rpm tag with the date (specified by date_format)',
		    0);
    $defaults->add ('verbose', 'n', 
		    'level of verbosity; 0 means quiet operation',
		    1);
    $defaults->add ('debug', 'n',
		    'debug level',
		    0);
    $defaults->add ('prodname', 's',
		    'name of the product to appear in the error mail subject',
		    'unnamed');
    $defaults->add ('summary_log', 's',
		    'file name for the HTML summary build report');
    $defaults->add ('summary_title', 's',
		    'title of the HTML summary build report',
		    'Build Report');
    $defaults->add ('rpm_url', 's',
		    'a URL pointing to the directory where the resulting rpms will be save (used in the HTML build report)');
    $defaults->add ('srpm_url', 's',
		    'a URL pointing to the directory where the resulting source srpms will be save (used in the HTML build report)');
    $defaults->add ('deps', '!',
		    'whether to check dependencies; use nodeps to ignore dependencies',
		    1);
    $defaults->add ('halt_on_errors', '!',
		    'whether to abort the build if an error occurs', 
		    0);
    $defaults->add ('interactive', '!',
		    '[EXPERIMENTAL] display the build output and enter interactive mode if an error occurs', 
		    0);
    $defaults->add ('maintainers', 's',
		    'file containing the list of maintainers for each spec file');
    $defaults->add ('mail_errors_to', 's',
		    'email address to send build error reports to');
    $defaults->add ('mail_errors_cc', 's',
		    'email address to Cc build error reports');
    $defaults->add ('date_format', 's',
		    'string passed on the command line to the date(1) command for calculating the suffix for the Release tag in nightly builds',
		    "%y%m%d");
    $defaults->add ('pkgformat', 's',
		    'Format of Solaris packages: filesystem or datastream',
		    'filesystem');
    $defaults->add ('build_engine', 's',
		    'The build engine to use.',
		    $build_engine);
    $defaults->add ('download', '!',
		    'download missing sources as needed.  requires wget',
		    0);
    $defaults->add ('download_to', 's',
		    'save downloaded files in the given directory.',
		    "%{topdir}/SOURCES");
    $defaults->add ('source_mirrors', 's',
		    'comma-separated list of mirror sites for source downloads');
}

sub add_spec ($) {
    my $spec_name = shift;

    @spec_names = (@spec_names, $spec_name);
}

sub read_spec ($) {
    my $spec_name = shift;
    
    my $spec;
    
    my $rpm_target = $defaults->get ('target');
    if (defined $rpm_target) {
	@predefs = (@predefs, "_target $rpm_target");
    }

    if (-f $spec_name) {
	$spec = rpm_spec->new ($spec_name, \@predefs);
    } else {
	if (not $spec_name =~ /^\//) {
	    my @the_spec_dirlist = split /:/, $defaults->get ('specdirs'); #/
	    foreach my $specdir (@the_spec_dirlist) {
		next if not defined $specdir;
		$spec = rpm_spec->new ("$specdir/$spec_name", \@predefs);
		last if defined $spec;
	    }
	}
    }
    
    if (not defined ($spec)) {
	die ("$spec_name not found\n");
    } else {
	my $this_spec_id = $spec_counter ++;
	$specs[$this_spec_id] = $spec;
    }
}

sub process_args {
    my $arg = shift;
    
    if ($arg =~ /^--with-(.*)/) {
	process_with ("with", $1);
	return;
    } elsif ($arg =~ /^--without-(.*)/) {
	process_with ("without", $1);
	return;
    } elsif ($arg =~ /^-/) {
	msg_error ("Unknown option: $arg\n");
        exit (1);
    }

    if (not defined ($spec_command)) {
	if (not $arg =~ /^(eval|get_meta|get_packages|get_sources|get_public_sources|get_block|get_package_names|get_patches|get_public_patches|get_classes|get_class_script_names|get_included_files|get_used_spec_files|get_error|verify|get_requires|get_buildrequires|get_prereq)$/) {
	    usage (1);
	}
	$spec_command = $arg;
    } else {
	if ($spec_command =~ /^(eval|get_block|get_requires|get_prereq)$/
	    and not defined ($spec_cmd_arg)) {
	    $spec_cmd_arg = $arg;
	} else {
	    add_spec ($arg);
	}
    }
}

sub process_pkgformat ($$) {
    shift;
    my $pkgformat = shift;

    $defaults->set ('pkgformat', $pkgformat);
}

sub process_with ($$) {
    my $with = shift;
    my $opt = shift;
    
    if ($with ne "with" and $with ne "without") {
	die ("Internal error in sub process_with()");
    }
    my $optname = $opt;
    $optname =~ tr /\-/_/;
    push (@predefs, "_${with}_${optname} --${with}-${opt}");
}

sub set_ips($) {
	$ips = shift;
	$svr4 = undef;
}

sub set_svr4($) {
	$svr4 = shift;
	$ips = undef;
}

sub process_options {
    
    Getopt::Long::Configure ("bundling");
      
    our $verbose = 0;
    GetOptions ('v|verbose+' => \$verbose,
		'debug=n' => sub { shift; $defaults->set ('debug', shift); },
		'q|quiet' => sub { $verbose = 0; },
		'l|long' => sub { $long_output = 1; },
		'specdirs|specdir|spec|specs|S=s' => sub { shift; $defaults->set ('specdirs', shift); },
		'sourcedirs|sourcedir|src|srcdirs|srcdir|sources|source|s=s'  => sub { shift; $defaults->set ('sourcedirs', shift); },
		'rcfile=s' => sub { shift; my $dummy = shift; $read_rc=0; $defaults->readrc ($dummy) or msg_error ("Config file not found: $dummy"); },
		'rc!' => \$read_rc,
		'define=s' => sub { 
		    shift; 
		    my $def = shift;
		    @predefs = ( @predefs, $def );
		    $topdir = rpm_spec::get_topdir ($build_engine, \@predefs);
		},
		'with=s' => \&process_with,
		'without=s' => \&process_with,
		'pkgformat=s' => \&process_pkgformat,
		'full-path' => \$full_path,
		'rpmdir|rpm|topdir|r=s' => sub { 
		    shift; 
		    $topdir = shift;
		    @predefs = ( @predefs, "_topdir $topdir" );
		},
		'help' => \&usage,
		'ips' => sub { set_ips(1); },
		'svr4' => sub { set_svr4(1); },
		'<>' => \&process_args);
      
    if ($read_rc) {
	$defaults->readrc ("${_homedir}/.pkgtoolrc");
	$defaults->readrc ('./.pkgtoolrc');
    }

    my $specdirstr = $defaults->get ('specdirs');
    if (defined ($specdirstr)) {
	my @specdirs = split /:/, $specdirstr;
	my $specdir = shift(@specdirs);
	if (@specdirs) {
	    $specdirstr = join (':', @specdirs);
	    @predefs = ( @predefs, "_specdir $specdir",
			 "__pkgbuild_spec_path $specdirstr");
	} else {
	    @predefs = ( @predefs, "_specdir $specdir" );
	}
    }

    if (not @spec_names) {
        msg_warning (0, "No spec files specified, nothing to do.");
        exit (0);
    }

    for my $spec_name (@spec_names) {
	read_spec ($spec_name) unless not defined ($spec_name);
    }
    $defaults->set ('verbose', $verbose);
}

sub usage (;$) {
    my $retval = shift;
    if (not defined ($retval)) {
	$retval = 0;
    } elsif ($retval eq "help" or $retval eq "h") {
	$retval = 0;
    }
    
    print << "EOF";
spectool [options] [command] specs...
	
Options:

  General:
	
    -v|--verbose:    
	          Increase verbosity: the more -v's the more diag messages.

    -q|--quiet:
                  Silent operation.

    --rcfile=file
                  Read default configuration from file.
                  Default: ./.pkgtoolrc, ~/.pkgtoolrc

    --norc
                  Ignore the default rc files.

  Directories and search paths:

    --specdirs=path, --spec=path:
                  Specify a colon separated list of directories to search
                  for spec files in

  Options controlling the build:
                  
    --nodeps, --deps:
                  Ignore/verify dependencies before building a component.
                  Default: --deps

    --with foo, --without foo
                  This option is passed on to rpm/pkgbuild as is.  Use it
                  for enabling/disabling conditional build options.

Commands:
	
    eval <expr>   evaluate <expr> in the context of each spec file
                  specified on the command line

    get_packages  list the packages defined in the spec files specified
                  on the command line

    get_sources

    get_public_sources

    get_block <block_name>

    get_meta

    get_package_names

    get_patches

    get_public_patches

    get_requires <package name>

    get_prereq <package name>

    get_buildrequires

    get_classes

    get_class_script_names

    get_included_files

    get_used_spec_files [-l]

    get_error

    verify
	
specs...
	
    List of spec files to work with.  Either full path names or names of spec
    files in the spec directory search path.
EOF
#' <-- (keep emacs syntax highlighting happy)

    exit $retval;
}


sub process_specs () {
    msg_info (1, "Processing spec files\n");
    for (my $spec_id = 0; $spec_id <= $#spec_names; $spec_id++) {
	my $spec = $specs[$spec_id];
	msg_info (2, "Processing spec file " . $spec->get_base_file_name ());
	my $dummy = $spec->get_packages ();
    }
}

# --------- implement the various spectool commands ------------------------
sub print_result ($@) {
    my $spec = shift;
    my @args = @_;

    my $verbose = $defaults->get ('verbose');
    foreach my $line (@args) {
	if ($verbose > 0) {
	    print $spec->get_base_file_name() . ": $line\n";
	} else {
	    print "$line\n";
	}
    }
}

sub do_eval () {
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    print_result ($spec, $spec->eval ($spec_cmd_arg));
	}
    }
}

sub do_get_block () {
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    print_result ($spec, $spec->get_block ($spec_cmd_arg));
	}
    }
}

sub do_get_packages () {
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    my @pkgs = $spec->get_packages ();
	    print_result ($spec, @pkgs);
	}
    }
}

sub do_get_requires () {
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    my @pkgs = $spec->get_packages ();
	    my @reqs = ();
	    foreach my $pkg (@pkgs) {
		next if "$pkg" ne "$spec_cmd_arg";
		my @pkg_breqs = $pkg->get_array ('requires');
		if (@pkg_breqs) {
		    push(@reqs, @pkg_breqs);
		}
	    }
	    print_result ($spec, @reqs);
	}
    }
}

sub do_get_prereq () {
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    my @pkgs = $spec->get_packages ();
	    my @reqs = ();
	    foreach my $pkg (@pkgs) {
		next if "$pkg" ne "$spec_cmd_arg";
		my @pkg_breqs = $pkg->get_array ('prereq');
		if (@pkg_breqs) {
		    push(@reqs, @pkg_breqs);
		}
	    }
	    print_result ($spec, @reqs);
	}
    }
}

sub do_get_buildrequires () {
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    my @pkgs = $spec->get_packages ();
	    my @buildreqs = ();
	    foreach my $pkg (@pkgs) {
		my @pkg_breqs = $pkg->get_array ('buildrequires');
		if (@pkg_breqs) {
		    push(@buildreqs, @pkg_breqs);
		}
	    }
	    print_result ($spec, @buildreqs);
	}
    }
}

sub do_get_package_names () {
    my $pkgformat = $defaults->get('pkgformat');
    if ($pkgformat eq 'ds' || $pkgformat eq 'datastream') {
	$pkgformat = '1';
    } else {
	$pkgformat = undef;
    }
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    my @pkgs = ();
	    if ($ips) {
		my @ps = $spec->get_packages ();
		foreach my $p (@ps) {
		    # subpackages are merged in the main package
		    next if ($p->is_subpkg());
		    push (@pkgs, $p->get_ips_name());
		    if ($full_path) {
			my $auth = $ips_utils->get_pkgbuild_authority();
			map $_="pkg://$auth/$_", @pkgs;
		    }
		}
	    } elsif ($svr4) {
		@pkgs = $spec->get_package_names ($pkgformat);
		if ($full_path) {
		    my $pkgdir = $spec->get_value_of ('_topdir') . "/PKGS";
		    map $_="$pkgdir/$_", @pkgs;
		}
	    } else {
		msg_error ("internal error: either svr4 or ips must be selected");
	    }
	    print_result ($spec, @pkgs);
	}
    }
}

sub do_get_classes () {
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    my @pkgs = $spec->get_classes ();
	    print_result ($spec, @pkgs);
	}
    }
}

sub do_get_meta () {
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    my @meta;
	    my $spec = $specs[$spec_id];
	    my @packages = $spec->get_packages ();
	    foreach my $package (@packages) {
		next if (defined $ips and $package->is_subpkg());
		my $meta_hash_ref = $package->get_meta_hash ();
		my $pkgname;
		if (defined $ips) {
		    $pkgname = $package->get_ips_name();
		} else {
		    $pkgname = $package->get_svr4_name();
		}
		foreach my $key (keys %$meta_hash_ref) {
		    push (@meta, $pkgname . ": " . $key . " = " . $$meta_hash_ref{$key});
		}
	    }
	    print_result ($spec, @meta);
	}
    }
}

sub do_get_class_script_names () {
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    my @pkgs = $spec->get_classes ();
	    print_result ($spec, @pkgs);
	}
    }
}

sub do_get_included_files () {
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    my @pkgs = $spec->get_included_files ();
	    print_result ($spec, @pkgs);
	}
    }
}

sub do_get_error () {
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    my @pkgs = $spec->get_error ();
	    print_result ($spec, @pkgs);
	}
    }
}

sub do_get_used_spec_files () {
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    my @output;
	    if ($long_output) {
		my @labels = $spec->get_used_spec_labels ();
		foreach my $label (@labels) {
		    my $used_spec = $spec->{_specs_used}->{$label};

		    push (@output, "$label = " . $$used_spec->get_file_name());
		}
	    } else {
		@output = $spec->get_used_spec_files ();
	    }
	    print_result ($spec, @output);
	}
    }
}

sub do_get_sources () {
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    my @pkgs = $spec->get_sources ();
	    print_result ($spec, @pkgs);
	}
    }
}

sub do_get_public_sources () {
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    my @pkgs = $spec->get_public_sources ();
	    print_result ($spec, @pkgs);
	}
    }
}

sub do_get_patches () {
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    my @pkgs = $spec->get_patches ();
	    print_result ($spec, @pkgs);
	}
    }
}

sub do_get_public_patches () {
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    $exit_val++;
	} else {
	    my @pkgs = $spec->get_public_patches ();
	    print_result ($spec, @pkgs);
	}
    }
}

sub do_verify () {
    my $verbose = $defaults->get ('verbose');
    for (my $spec_id = 0; $spec_id <= $#specs; $spec_id++) {
	my $spec = $specs[$spec_id];
	if (defined $spec->{error}) {
	    if ($verbose == 1) {
		print_result ($spec, "FAIL");
	    }
	    if ($verbose > 1) {
		msg_error ($spec->get_base_file_name () . ": " . $spec->{error});
	    }
	    $exit_val++;    
	} else {
	    if ($verbose == 1) {
		print_result ($spec, "PASS");
	    }
	}
    }
}

# --------- main program ---------------------------------------------------
sub main {
    process_defaults ();
    process_options ();

    if (not defined ($spec_names[0])) {
	msg_info (0, "No spec files specified: nothing to do.");
	exit (0);
    }

    process_specs ();

    if (not defined ($spec_command)) {
	usage (1);
    }
    
    if ($spec_command eq "eval") {
	do_eval ();
    } elsif ($spec_command eq "get_packages") {
	do_get_packages ();
    } elsif ($spec_command eq "get_used_spec_files") {
	do_get_used_spec_files ();
    } elsif ($spec_command eq "get_sources") {
	do_get_sources ();
    } elsif ($spec_command eq "get_public_sources") {
	do_get_public_sources ();
    } elsif ($spec_command eq "get_patches") {
	do_get_patches ();
    } elsif ($spec_command eq "get_public_patches") {
	do_get_public_patches ();
    } elsif ($spec_command eq "get_block") {
	do_get_block ();
    } elsif ($spec_command eq "get_package_names") {
	do_get_package_names ();
    } elsif ($spec_command eq "get_classes") {
	do_get_classes ();
    } elsif ($spec_command eq "get_meta") {
	do_get_meta ();
    } elsif ($spec_command eq "get_class_script_names") {
	do_get_class_script_names ();
    } elsif ($spec_command eq "get_included_files") {
	do_get_included_files ();
    } elsif ($spec_command eq "get_requires") {
	do_get_requires ();
    } elsif ($spec_command eq "get_buildrequires") {
	do_get_buildrequires ();
    } elsif ($spec_command eq "get_prereq") {
	do_get_prereq ();
    } elsif ($spec_command eq "get_error") {
	do_get_error ();
    } elsif ($spec_command eq "verify") {
	do_verify ();
    }

    exit ($exit_val);
}

$pkgbuild_path = shift (@ARGV);
$build_engine = $pkgbuild_path;

init;
main;
