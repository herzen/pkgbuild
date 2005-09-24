#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long qw(:config gnu_getopt no_auto_abbrev);
use rpm_spec;
use config;

# --------- global vars ----------------------------------------------------
# config settings
my $the_good_build_dir;
my $the_good_rpms_copy_dir;
my $live_summary = 1;

my $build_command;

my $exit_val = 0;
my $full_path = 0;

# counter used as an id for the spec files
my $spec_counter = 0;

# array of spec objects
my @specs_to_build = ();
my @build_status;
my @status_details;
my @remove_list = ();

my %all_specs;
my %provider;
my %warned_about;

# --------- defaults -------------------------------------------------------
my $defaults;
my @predefs = ();
my $build_engine = "pkgbuild";
my $topdir = rpm_spec::get_topdir ($build_engine, \@predefs);

sub process_defaults () {
    my $default_spec_dir = "$topdir/SPECS";
    $topdir = rpm_spec::get_topdir ($build_engine, \@predefs);

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
		    "$topdir/SOURCES");
    $defaults->add ('sourcedirs', 's',
		    'colon (:) separated list of directories where extra sources (not tarballs) are searched for',
		    "$topdir/SOURCES");
    $defaults->add ('specdirs', 's',
		    'colon (:) separated list of directories where spec files are searched for',
		    "$topdir/SPECS");
    $defaults->add ('patchdirs', 's',
		    'colon (:) separated list of directories where source patches are searched for',
		    "$topdir/SOURCES");
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
		    "$topdir/SOURCES");
}

# --------- utility functions ----------------------------------------------
my $arch;
my $os;
my $os_rel;

sub find_in_path ($) {
    my $executable = shift;
    my $PATH = $ENV{PATH};
    $PATH = "/bin:/usr/bin" unless defined $PATH;
    my @path = split /:/, $PATH;
    foreach my $dir (@path) {
	if ( -x "$dir/$executable" ) {
	    return "$dir/$executable";
	}
    }
    return undef;
}

my $wget;
sub wget_in_path () {
    msg_info (2, "Looking for wget");
    if (not defined ($wget)) {
	$wget = find_in_path ("wget");
	if (not defined ($wget)) {
	    msg_warning (0, "wget is not found in the PATH, automatic downloads are not possible");
	    $wget = "-";
	    return 0;
	}
	msg_info (2, "Found $wget");
	return 1;
    } elsif ($wget ne "-") {
	return 1;
    } else {
	return 0;
    }
}

sub init () {
    $arch = `uname -p`;
    chomp ($arch);
    if ($arch eq "unknown") {
	$arch = `uname -m`;
	chomp ($arch);
	if ($arch eq 'i585') {
	    $arch = 'i386';
	} elsif ($arch eq 'i686') {
	    $arch = 'i386';
	}
    }
    
    $os = `uname -s`;
    chomp ($os);
    $os = lc($os);
    $os_rel = `uname -r`;
    chomp ($os_rel);
    if ($os eq 'sunos') {
	if ($os_rel =~ /^5\./) {
	    $os = 'solaris';
	}
    }

    if ($os eq "solaris") {
	$build_engine = "pkgbuild";
    } elsif (defined (find_in_path ("rpmbuild"))) {
	$build_engine = "rpmbuild";
    } elsif (defined (find_in_path ("rpm"))) {
	$build_engine = "rpm";
    } else {
	$build_engine = "pkgbuild";
    }
}

# return the name of the log file given the id of the spec file
sub get_log_name ($) {
    my $spec_id = shift;
    my $spec = $specs_to_build[$spec_id];
    my $spec_file = $spec->get_file_name ();
    my $base_name = $spec->get_base_file_name ();
    my $log_name = "$base_name";
    $log_name =~ s/(\.spec|)$/.log/;
    
    return $log_name;
}

my $current_log;

sub open_log ($) {
    my $log_filename = shift;
    
    if (not defined ($log_filename)) {
	return;
    }
    
    if (defined ($current_log)) {
	if ($current_log ne $log_filename) {
	    close LOG_FILE;
	}
    }
    
    $current_log = undef;
    
    if (! open LOG_FILE, ">>$log_filename") {
	msg_warning (0, "Failed to open log file $log_filename for writing");
	return;
    }
    
    $current_log = $log_filename;
    
    msg_log ("--- log starts --- " . `date`);
}

sub close_log () {
    msg_log ("--- log ends --- " . `date`);
    close LOG_FILE;
    $current_log = undef;
}

sub print_message ($$) {
    my $min_verbose = shift;
    my $message = shift;
    
    chomp $message;
    
    my $verbose = $defaults->get ('verbose');
    if ($verbose > $min_verbose) {
	print "$message\n";
    }
    if (defined ($current_log)) {
	print LOG_FILE "$message\n";
    }
}

sub msg_error ($) {
    my $message = shift;
    
    print_message (0, "ERROR: $message");
    my $halt_on_errors = $defaults->get ('halt_on_errors');
    if ($halt_on_errors > 0) {
	print "ERROR: Exiting...\n";
	exit (255);
    } else {
	my $interactive_mode = $defaults->get ('interactive');
	if ($interactive_mode) {
	    print "Would you like to continue? (yes/no) [yes]";
	    my $ans = <STDIN>;
	    chomp ($ans);
	    $ans = lc($ans);
	    if ($ans ne "y" and $ans ne "yes" and $ans ne "") {
		exit(254);
	    }
	    return 1;
	}
    }
    return 0;
}

sub msg_warning ($$) {
    my $min_verbose = shift;
    my $message = shift;
    
    print_message ($min_verbose, "WARNING: $message");
}

sub msg_info ($$) {
    my $min_verbose = shift;
    my $message = shift;
    
    print_message ($min_verbose, "INFO: $message");
}

sub msg_debug ($$) {
    my $min_debug = shift;
    my $message = shift;
    
    my $debug_level = $defaults->get ('debug');
    if ($debug_level > $min_debug) {
	print "DEBUG: $message\n";
    }
}

sub msg_log ($) {
    my $message = shift;
    
    if (defined ($current_log)) {
	print LOG_FILE "$message\n";
    }
}

sub find_file ($) {
    my $glob = shift;
    
    my @files = `find $glob 2>&1`;
    if ($? == 0) {
	my $file = $files[$#files];
	chomp $file;
	return ($file);
    }
    
    return (undef);
}

sub mail_log ($) {
    my $spec_id = shift;
    my $address;
    my $cc;
    my $log_name = get_log_name ($spec_id);
    my $spec_name = $specs_to_build[$spec_id]->get_name ();
    my $base_name = $log_name;
    $log_name =~ s/\.log$//;
    
    my $mail_errors_file = $defaults->get ('maintainers');
    if (defined ($mail_errors_file)) {
	$address = get_address_from_file ($mail_errors_file, $base_name);
    }
    
    my $mail_errors_to = $defaults->get ('mail_errors_to');
    if (not defined ($address)) {
	$address = $mail_errors_to;
    }

    my $mail_errors_cc = $defaults->get ('mail_errors_cc');
    if (not defined ($address)) {
	$address = $mail_errors_cc;
    } else {
	$cc = $mail_errors_cc;
    }

    if (not defined ($address)) {
	return;
    }
    
    my $log_file = get_log_name ($spec_id);
    msg_info (1, "emailing the build log to $address");

    my $subject;
    
    my $prodname = $defaults->get ('prodname');
    if (defined ($prodname)) {
	$subject = "BUILD FAILED ($prodname): $spec_name";
    } else {
	$subject = "BUILD FAILED: $spec_name";	
    }
 
    my $the_log_dir = $defaults->get ('logdir');
    my $the_logdir_url = $defaults->get ('logdir_url');
    my $log_pointer;
    if (defined ($the_logdir_url)) {
	$log_pointer = "$the_logdir_url/${log_name}.log";
    } else {
	$log_pointer = "$the_log_dir/${log_file}";
    }

    if (defined ($cc)) {
	`( echo "Full log: $log_pointer" ; echo; echo "--- tail of the log follows ---"; echo; tail -100 $the_log_dir/$log_file ) | mailx -s "$subject" -c "$cc" $address`;
    } else {
	`( echo "Full log: $log_pointer" ; echo; echo "--- tail of the log follows ---"; echo; tail -100 $the_log_dir/$log_file ) | mailx -s "$subject" $address`;
    }
}

sub get_address_from_file ($$) {
    my $fname = shift;
    my $pkg = shift;
    
    $pkg =~ s/\.spec$//;
    
    if (! open ADDR_FILE, "<$fname") {
        msg_warning (0, "Could not open file $fname");
	return undef;
    }
    my @lines = <ADDR_FILE>;
    my @addresses = grep /^$pkg:/, @lines;
    my $address = $addresses[0];
    if (not defined ($address)) {
	return undef;
    }
    $address =~ s/^$pkg://;
    $address =~ s/\s//g;
    close ADDR_FILE;
    return $address;
}

# --------- functions to process the command line args ---------------------
my @specs_to_read = ();

sub add_spec ($) {
    my $spec_name = shift;

    @specs_to_read = (@specs_to_read, $spec_name);
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
	    my @the_spec_dirlist = split /:/, $defaults->get ('specdirs');
	    foreach my $specdir (@the_spec_dirlist) {
		next if not defined $specdir;
		$spec = rpm_spec->new ("$specdir/$spec_name", \@predefs);
		last if defined $spec;
	    }
	}
    }
    
    if (not defined ($spec)) {
	msg_error ("$spec_name not found\n");
    } else {
	my $this_spec_id = $spec_counter ++;
	$specs_to_build[$this_spec_id] = $spec;

	$build_status[$this_spec_id] = 'NOT_BUILT';
	$status_details[$this_spec_id] = '';
	$all_specs{$spec->get_file_name ()} = $this_spec_id;
    }
}

sub process_args {
    my $arg = shift;
    
    if (not defined ($build_command)) {
	if (($arg ne "build") and ($arg ne "build-order") and
	    ($arg ne "build-only") and ($arg ne "build-install") and
	    ($arg ne "install-pkgs") and ($arg ne "prep") and
	    ($arg ne "uninstall-pkgs") and ($arg ne "spkg") and
	    ($arg ne "install-order") and ($arg ne "download")) {
	    msg_error ("unknown command: $arg");
	    usage (1);
	}
	$build_command = $arg;
    } else {
	add_spec ($arg);
    }
}

my $read_rc = 1;

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

sub process_options {
    
    Getopt::Long::Configure ("bundling");
      
    our $opt_good_build_dir;
    our $opt_good_rpms_copy_dir;
    our $opt_live_summary = 1;
    our $verbose = $defaults->get ('verbose');

    GetOptions ('v|verbose+' => \$verbose,
		'debug=n' => sub { shift; $defaults->set ('debug', shift); },
		'q|quiet' => sub { $verbose = 0; },
		'specdirs|specdir|spec|specs|S=s' => sub { shift; $defaults->set ('specdirs', shift); },
		'halt-on-errors!' => sub { shift; $defaults->set ('halt_on_errors', shift); },
		'mail-errors-to=s' => sub { shift; $defaults->set ('mail_errors_to', shift); },
		'mail-errors-cc=s' => sub { shift; $defaults->set ('mail_errors_cc', shift); },
		'mail-errors-file|maintainers=s' => sub { shift; $defaults->set ('maintainers', shift); },
		'prodname=s' => sub { shift; $defaults->set ('prodname', shift); },
		'sourcedirs|sourcedir|src|srcdirs|srcdir|sources|source|s=s'  => sub { shift; $defaults->set ('sourcedirs', shift); },
		'logdir|log|l=s' => sub { shift; $defaults->set ('logdir', shift); },
		'summary-log|report=s' => sub { shift; $defaults->set ('summary_log', shift); },
		'live-summary|live!',
		'summary-title|report-title=s' => sub { shift; $defaults->set ('summary_title', shift); },
		'rcfile=s' => sub { shift; my $dummy = shift; $read_rc=0; $defaults->readrc ($dummy) or msg_error ("Config file not found: $dummy"); },
		'logdir-url=s' => sub { shift; $defaults->set ('logdir_url', shift); },
		'rpm-url=s' => sub { shift; $defaults->set ('rpm_url', shift); },
		'srpm-url=s' => sub { shift; $defaults->set ('srpm_url', shift); },
		'target=s' => sub { shift; $defaults->set ('target', shift); },
		'deps!' => sub { shift; $defaults->set ('deps', shift); },
		'rc!' => \$read_rc,
		'interactive!' => sub { shift; $defaults->set ('interactive', shift); },
		'tarballdirs|tarballdir|tar|tarballs|tardirs|t=s' => sub { shift; $defaults->set ('tarballdirs', shift); },
		'good-build-dir|substitutes=s',
		'good-rpms-copy-dir=s',
		'nightly!' => sub { shift; $defaults->set ('nightly', shift); },
		'define=s' => sub { 
		    shift; 
		    my $def = shift;
		    @predefs = ( @predefs, $def );
		    $topdir = rpm_spec::get_topdir ($build_engine, \@predefs);
		},
		'with=s' => \&process_with,
		'without=s' => \&process_with,
		'pkgformat=s' => \&process_pkgformat,
		'date|date-format|nightly-date-format=s' => sub { shift; $defaults->set ('date_format', shift); },
		'patchdirs|patchdir|patch|patches|p=s' => sub { shift; $defaults->set ('patchdirs', shift); },
		'rpmdir|rpm|topdir|r=s' => sub { 
		    shift; 
		    $topdir = shift;
		    @predefs = ( @predefs, "_topdir $topdir" );
		},
		'full-path' => \$full_path,
		'help' => \&usage,
		'dumprc' => sub { $defaults->dumprc (); exit (0); }, 
		'pkgbuild' => sub { 
		    $defaults->set ('build_engine', 'pkgbuild');
		    $build_engine = 'pkgbuild';
		    $topdir = rpm_spec::get_topdir ($build_engine, \@predefs);
		},
		'rpmbuild' => sub {
		    if (defined (find_in_path ('rpmbuild'))) {
			$build_engine = 'rpmbuild';
		    } elsif (defined (find_in_path ('rpm'))) {
			$build_engine = 'rpm';
		    } else {
			fatal ('rpm/rpmbuild not found in the PATH');
		    }
		    $defaults->set ('build_engine', $build_engine);
		    $topdir = rpm_spec::get_topdir ($build_engine, \@predefs);
		},
		'download' => sub { shift; $defaults->set ('download', shift); },
		'download-to=s' => sub {
		    shift;
		    $defaults->set ('download_to', shift);
		    $defaults->set ('download', 1);
		},
		'<>' => \&process_args);
      
    if ($read_rc) {
	$defaults->readrc ("$ENV{'HOME'}/.pkgtoolrc");
	$defaults->readrc ('./.pkgtoolrc');
    }

    for my $spec_name (@specs_to_read) {
	read_spec ($spec_name) unless not defined ($spec_name);
    }
    $the_good_build_dir = $opt_good_build_dir;
    $the_good_rpms_copy_dir = $opt_good_rpms_copy_dir;
    $live_summary = $opt_live_summary;
      
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
pkgtool [options] [command] specs...
	
Options:

  General:
	
    -v|--verbose:    
	          Increase verbosity: the more -v's the more diag messages.

    -q|--quiet:
                  Silent operation.

    --halt-on-errors:
                  Halt on the first build error, do not attempt to continue.

    --rcfile=file
                  Read default configuration from file.
                  Default: ./.pkgtoolrc, ~/.pkgtoolrc

    --norc
                  Ignore the default rc files.

    --dumprc
                  Print the current configuration in a format suitable
                  for an rc file, then exit.

    --download

                  Automatically download sources if not found in the local
                  search paths (requires wget)  Specify your proxy servers
                  using the http_proxy and ftp_proxy environment variables.

    --download-to=dir

                  Save downloaded files in dir.  By default, files are
                  downloaded to $topdir/SOURCES.  Implies --download.

    --interactive  [EXPERIMENTAL]

	          Interactive mode: pkgbuild/rpm output is displayed on
                  the standard output; pkgbuild is executed in interactive
                  mode which makes it start a subshell if the build fails

  Directories and search paths:

    --specdirs=path, --spec=path:
                  Specify a colon separated list of directories to search
                  for spec files in

    --tarballdirs=path, --tarballs=path, --tar=path:
                  Specify a colon separated list of directories to search
                  for tarballs in

    --sourcedirs=path, --src=path:
                  Specify a colon separated list of directories to search
                  for additional source files in

    --patchdirs=path, --patches=path, --patch=path
                  Specify a colon separated list of directories to search
                  for patches (source diffs) in
 
    --topdir=dir
                  Use dir as the rpm base directory (aka %topdir, where the
                  SPECS, SOURCES, RPMS, SRPMS, BUILD directories are found).
                  Default: $topdir

    --logdir=dir, --log=dir:
                  Write build logs to dir.

  Options controlling the build:
                  
    --nodeps, --deps:
                  Ignore/verify dependencies before building a component.
                  Default: --deps

    --with foo, --without foo
                  This option is passed on to rpm/pkgbuild as is.  Use it
                  for enabling/disabling conditional build options.

    --target=arch
                  This option is passed on to rpm/pkgbuild as is.

    --pkgformat={filesystem|fs|datastream|ds}
                  Create Solaris packages in filesystem or datastream format.
                  This option is ignored when running on Linux.
                  Default: filesystem

    --nightly, --nonightly:
                  Suffix/Don't suffix the rpm Release with the current date.
		  Default: --nonightly;  See also: --date-format
    
    --date-format=format, --date=format:
                  Use "date +format" to generate the date suffix for
	          the nightly builds.  Default: %y%m%d

  Reporting:

    --mail-errors-to=address

                  Send the last few lines of the build log to address
		  if the build fails

    --report=file

                  Write a build report to file (in HTML format)

    --prodname=string

                  The name of the product as appears in the build report
    
    --full-path:
                  Print the full path to the package when running install-order

Commands:
	
    build-install  Build and install the specs listed on the command line.
                   The build order is determined by the dependencies
		   defined in the spec files.

    build          Same as build-install

    build-only     Build the specs listed on the command line, don't install
                   them.

    prep           run the %prep section of the spec files listed on the
                   command line

    spkg           create source package(s) only (no build done)

    build-order    Print the build order of the specs listed on the
                   command line.

    install-order  Print the rpms in the order they should be installed
	
    install-pkgs   (not implemented yet): install the packages defined
                   by the spec files listed on the command line from
                   the PKGS directory.  No build is done.  Useful to
                   install packages previously built using the build-only
                   command.
	
    uninstall-pkgs Uninstall all packages defined in the spec files listed
	           on the command line. (runs rpm --erase --nodeps on
                   Linux, pkgrm on Solaris)

    download       Download the source files from the URLs specified in
                   the spec files listed on the command line.  Source
                   files found in the local search paths will not be
                   downloaded.  (See --tarballdirs, --sourcedirs,
                   --download-to)
	
specs...
	
    List of spec files to build. Either full path names or names of spec
    files in the spec directory search path.
EOF
#' <-- (keep emacs syntax highlighting happy

    exit $retval;
}

# --------- print reports --------------------------------------------------
# plain text report on stdout and
# html report if summary log file name
# was specified on the command line
sub print_status {
    print_status_text ();
    print_status_html ();
}

sub print_live_status {
    if ($live_summary) {
	print_status_html ();
    }
}

sub print_status_text {
    my $spec_name;
    print "\nSummary:\n\n";
    printf "%32s | %11s | %s\n", "package", "status", "details";
    print "---------------------------------+-------------+-------------------------------\n";
    for (my $i = 0; $i <= $#specs_to_build; $i++) {
	$spec_name=$specs_to_build[$i]->get_name ();
	if (not defined ($spec_name)) {
	    $spec_name = $specs_to_build[$i]->get_base_file_name ();
	}
	printf "%32s | %11s | %s\n", $spec_name, $build_status[$i], 
		$status_details[$i];
    }
}

sub print_status_html {
    my $spec_name;

    my $the_summary_log = $defaults->get ('summary_log');
    if (not defined ($the_summary_log)) {
	return;
    }

    if (! open SUM_LOG, ">$the_summary_log") {
	msg_warning (0, "Failed to open file $the_summary_log for writing");
	return;
    }
	
    print SUM_LOG "<HTML>\n<HEAD>\n<TITLE>Build report</TITLE>\n";
    print SUM_LOG "</HEAD>\n<BODY BGCOLOR=#FFFFFF>\n";
    my $the_summary_title = $defaults->get ('summary_title');
    if (defined ($the_summary_title)) {
	print SUM_LOG "<P><H3>$the_summary_title</H3><P>\n";
    }
    print SUM_LOG "<TABLE BORDER=1 CELLSPACING=0 CELLPADDING=5 WIDTH=90%>\n";
    print SUM_LOG " <TR>\n";
    print SUM_LOG "  <TD BGCOLOR=#666699><B>package</B></TD>\n";
    print SUM_LOG "  <TD BGCOLOR=#666699><B>version</B></TD>\n";
    print SUM_LOG "  <TD BGCOLOR=#666699><B>release</B></TD>\n";
    print SUM_LOG "  <TD BGCOLOR=#666699><B>status</B></TD>";
    print SUM_LOG "  <TD BGCOLOR=#666699><B>details</B></TD>\n";
    print SUM_LOG " </TR>\n";
    for (my $i = 0; $i <= $#specs_to_build; $i++) {
	my $log_name = get_log_name ($i);
	$spec_name=$specs_to_build[$i]->get_name ();
	my $version = $specs_to_build[$i]->get_value_of ("version");
	$version = "unknown" if not defined $version;
	my $release = $specs_to_build[$i]->get_value_of ("release");
	$release = "" if not defined $release;
	print SUM_LOG " <TR>\n";
	my $the_srpm_url = $defaults->get ('srpm_url');
	if (defined ($the_srpm_url)) {
	    if (($build_status[$i] eq "PASSED") and defined ($the_srpm_url)) {
		print SUM_LOG "  <TD><A HREF=\"$the_srpm_url/$spec_name-$version-$release.src.rpm\">$spec_name</A></TD>\n";
	    } else {
		print SUM_LOG "  <TD>$spec_name</TD>\n";
	    }
	} else {
	    print SUM_LOG "  <TD>$spec_name</TD>\n";
	}
	print SUM_LOG "  <TD>", $version, "</TD>\n";
	print SUM_LOG "  <TD>", $release, "</TD>\n";
	my $color_start = "";
	my $color_end = "";
	if ($build_status[$i] eq "PASSED") {
	    $color_start = "<FONT COLOR=#11AA11>";
	    $color_end = "</FONT>";
	} elsif ($build_status[$i] eq "BEING_BUILT") {
	    $color_start = "<FONT COLOR=#FFA500>";
	    $color_end = "</FONT>";
	} elsif ($build_status[$i] eq "DEP") {
	    $color_start = "<FONT COLOR=#FFA500>";
	    $color_end = "</FONT>";
	} elsif ($build_status[$i] eq "NOT_BUILT") {
	    $color_start = "";
	    $color_end = "";
	} else {
	    $color_start = "<FONT COLOR=#CC1111>";
	    $color_end = "</FONT>";
	}
	my $the_logdir_url = $defaults->get ('logdir_url');
	if (defined ($the_logdir_url) and ($build_status[$i] ne "NOT_BUILT")) {
	    print SUM_LOG "  <TD><A HREF=\"$the_logdir_url/$log_name\">",
	    $color_start, $build_status[$i], $color_end,
	    "</A></TD>\n";
	} else {
	    print SUM_LOG "  <TD>", 
	    $color_start, $build_status[$i], $color_end,
	    "</A></TD>\n";
	}
	if ($build_status[$i] eq "PASSED") {
	    my $the_rpm_url = $defaults->get ('rpm_url');
	    if (defined ($the_rpm_url)) {
		print SUM_LOG "  <TD>package: \n";
		my @pkgs = $specs_to_build[$i]-> get_package_names ();
		my $ctr = 1;
		for my $pkg (@pkgs) {
		    if ($os eq "solaris") {
			$pkg = "$pkg.tar.gz";
		    }
		    print SUM_LOG "    <A HREF=\"$the_rpm_url/$pkg\">[$ctr]</a> \n";
		    $ctr++;
		}
		print SUM_LOG "  </TD>\n";
	    } else {
		print SUM_LOG "  <TD>&nbsp;</TD>\n";
	    }
	} else {
	    print SUM_LOG "  <TD><PRE>", $status_details[$i], "</PRE></TD>\n";
	}
	print SUM_LOG " </TR>\n";
    }
    print SUM_LOG "</TABLE><P>\n";
    print SUM_LOG "<SMALL>", `date`, "</SMALL>\n";
    print SUM_LOG "</BODY>\n</HTML>\n";
    close SUM_LOG;
}

# --------- rpm utility functions ------------------------------------------
my %pkginfo; # cache the pkginfo results, as it's very slow
my %pkginfo_version;
sub is_provided ($) {
    my $capability = shift;

    if ($os eq "solaris") {
	$capability =~ s/\s.*//;
	if (defined $pkginfo{$capability}) {
	    return $pkginfo{$capability};
	}
	`pkginfo -q $capability'.*'`;
	my $result = (! $?);
	$pkginfo{$capability} = $result;
	if ($result) {
	    my $version = `pkginfo -l $capability'.*' | grep VERSION: | head -1`;
	    chomp $version;
	    $version =~ s/\s*VERSION:\s*([^,]+)(,|$).*/$1/;
            $pkginfo_version{$capability} = $version;
	}
	return $result;
    } else {
	$capability =~ s/\s.*//;
	`sh -c "rpm -q --whatprovides $capability" >/dev/null 2>&1`;
	my $result = (! $?);
	`sh -c "rpm -q $capability" >/dev/null 2>&1`;
	$result = ($result or (! $?));
    
	return ($result);
    }
}

sub is_installed ($) {
    my $pkg = shift;

    if ($os eq "solaris") {
	if (defined $pkginfo{$pkg}) {
	    return $pkginfo{$pkg};
	}
	`pkginfo -q $pkg'.*'`;
	my $result = (! $?);
	$pkginfo{$pkg} = $result;
	if ($result) {
	    my $version = `pkginfo -l $pkg'.*' | grep VERSION: | head -1`;
	    chomp $version;
	    $version =~ s/\s*VERSION:\s*([^,]+)(,|$).*/$1/;
            $pkginfo_version{$pkg} = $version;
        }
	return $result;
    } else {
	`sh -c "rpm -q $pkg" >/dev/null 2>&1`;
	my $result = (! $?);
	return ($result);
    }
}

sub what_provides ($) {
    my $capability = shift;

    $capability =~ s/ .*//;

    if ($os eq "solaris") {
	return $capability . "-" . $pkginfo_version{$capability};
    } else {
	my $rpm=`sh -c "rpm -q --whatprovides $capability" 2>&1 | head -1`;
	if ($?) {
	    $rpm=`sh -c "rpm -q $capability" 2>&1 | head -1`;
	}
	chomp $rpm;
	$rpm =~ s/-[^-]+$//;
	return ($rpm);
    }
}

sub install_good_pkgs ($) {
    my $spec_id = shift;
    my $spec = $specs_to_build[$spec_id];

#FIXME!
    if ($os eq "solaris") {
	return 0;
    }

    my @rpms =  $spec->get_rpms ();
    map $_ =~ s/[0-9]*-[0-9]+\..*\.rpm/[0-9]*-[0-9]*.*.rpm/, @rpms;
    map $_ =~ s/^/$the_good_build_dir\//, @rpms;


    for (my $i = 0; $i <= $#rpms; $i++) {
	my $current_rpm = $rpms[$i];
	msg_info (1, "Looking for last known good rpm as $current_rpm");
	$rpms[$i] = find_file ($current_rpm);
	if (not defined ($rpms[$i])) {
	    msg_error ("No file matches $current_rpm");
	    return 0;
	} else {
	    msg_info (1, "Found $rpms[$i]");
	}
    }

    my $command = "rpm --upgrade -v @rpms";

    my $verbose = $defaults->get ('verbose');
    if ($verbose > 0) {
	map msg_info (0, "Installing last known good rpm: $_\n"), @rpms;
    }

    my $msg=`$command 2>&1`;

    if ($? > 0) {
	msg_error "failed to install last known good rpm: $msg";
	$status_details[$spec_id] = $status_details[$spec_id] . 
	    "; Failed to install last known good rpm: " . $msg;
	return 0;
    }

    if (defined ($the_good_rpms_copy_dir)) {
	`mkdir -p $the_good_rpms_copy_dir`;
	`cp @rpms $the_good_rpms_copy_dir`;
    }

    return 1;
}

sub install_rpms ($) {
    my $spec_id = shift;
    my $spec = $specs_to_build[$spec_id];

    my @rpms =  $spec->get_rpm_paths ();
# FIXME: is this OK?
#    map $_ =~ s/^/$topdir\//, @rpms;
    my $command = "rpm --upgrade -v @rpms";

    my $verbose = $defaults->get ('verbose');
    if ($verbose > 0) {
	map msg_info (0, "Installing $_\n"), @rpms;
    }

    my $msg=`$command 2>&1`;
    if ($? > 0) {
	msg_error "failed to install rpm: $msg";
	$build_status[$spec_id] = 'FAILED';
	$status_details[$spec_id] = $msg;
	return 0;
    }

    return 1;
}

sub install_pkgs ($) {
    my $spec_id = shift;
    my $spec = $specs_to_build[$spec_id];
    
    my @pkgs = $spec->get_pkgs ();
    my $verbose = $defaults->get ('verbose');
    if ($verbose > 0) {
	map msg_info (0, "Installing $_\n"), @pkgs;
    }
    
    my $pkgsdir = $spec->get_value_of ("_topdir") . "/PKGS";
    
    my $adminfile = "/tmp/pkg.admin.$$";
    make_admin_file ($adminfile);

# FIXME: should install in dependency order
    foreach my $pkg (@pkgs) {
	my $msg=`pfexec /usr/sbin/pkgadd -a $adminfile -n -d $pkgsdir $pkg 2>&1`;
	if ($? > 0) {
	    unlink ($adminfile);
	    msg_error "failed to install package: $msg";
	    $build_status[$spec_id] = 'FAILED';
	    $status_details[$spec_id] = $msg;
	    return 0;
	}
    }
    
    unlink ($adminfile);
    return 1;
}

sub print_rpms ($) {
    my $spec_id = shift;
    my $spec = $specs_to_build[$spec_id];
    my @rpms;

    if ($full_path) {
	@rpms = $spec->get_rpm_paths ();
    } else {
	@rpms = $spec->get_rpms ();
    }
    map print("$_\n"), @rpms;
}

sub print_pkgs ($) {
    my $spec_id = shift;
    my $spec = $specs_to_build[$spec_id];
    
    my @pkgs = $spec->get_pkgs ();
    if ($full_path) {
	my $pkgdir = $spec->get_value_of ('_topdir') . "/PKGS";
	map print("$pkgdir/$_\n"), @pkgs;
    } else {
	map print("$_\n"), @pkgs;
    }
}

sub print_spec ($) {
    my $spec_id = shift;
    my $spec = $specs_to_build[$spec_id];

    print $spec->get_file_name() . "\n";
}

sub push_to_remove_list ($) {
    my $spec_id = shift;
    my $spec = $specs_to_build[$spec_id];

    my @pkgs =  $spec->get_package_names ();
    foreach my $pkg (@pkgs) {
	my @d = ($spec_id, $pkg);
	unshift (@remove_list, \@d);
    }
}

# --------- dependency checking code ---------------------------------------
sub warn_always ($$$) {
    my $spec_name = shift;
    my $dep = shift;
    my $reason = shift;

    if ($reason eq "DEP_FAILED") {
	msg_warning (0, "skipping package $spec_name: required package $dep failed");
    } elsif ($reason eq "NOT_FOUND") {
	msg_warning (0, "skipping package $spec_name: required package $dep not installed");
	msg_warning (0, "and no spec file specified on the command line provides it");
    }
}

sub warn_once ($$$) {
    my $spec_name = shift;
    my $dep = shift;
    my $reason = shift;

    if ($reason eq "DEP_FAILED") {
	# should not happen
	msg_error ("assertion failed: warn_once / DEP_FAILED");
    } elsif ($reason eq "NOT_FOUND") {
	if (not defined ($warned_about{$dep})) {
	    msg_warning (0, "$dep is required but not found");
	    $warned_about{$dep}=1;
	}
    }
}

sub warn_never ($$$) {
}

sub get_dependencies ($@) {
    my $spec_id = shift;
    my @packages = @_;
    my $spec = $specs_to_build[$spec_id];

    my @dependencies = ();
    my @this_pkg_requires;
    foreach my $pkg (@packages) {
	@this_pkg_requires = $pkg->get_array ('requires');
	next if not @this_pkg_requires or not defined $this_pkg_requires[0];
	msg_debug (3, "adding \"@this_pkg_requires\" to the dependencies of $spec");
	push (@dependencies, @this_pkg_requires);
    }

    foreach my $pkg (@packages) {
	@this_pkg_requires = $pkg->get_array ('buildrequires');
	next if not @this_pkg_requires or not defined $this_pkg_requires[0];
	msg_debug (3, "adding \"@this_pkg_requires\" to the dependencies of $spec");
	push (@dependencies, @this_pkg_requires);
    }

    foreach my $pkg (@packages) {
	@this_pkg_requires = $pkg->get_array ('prereq');
	next if not @this_pkg_requires or not defined $this_pkg_requires[0];
	msg_debug (3, "adding \"@this_pkg_requires\" to the dependencies of $spec");
	push (@dependencies, @this_pkg_requires);
    }

    return @dependencies;
}

sub check_dependency ($$&&@) {
    my $spec_id = shift;
    my $capability = shift;
    my $recursive_callback = shift;
    my $warning_callback = shift;
    my @rec_cb_opts = @_;
    my $spec_name = $specs_to_build[$spec_id]->get_name ();

    my $result = 1;

    if (not defined ($capability)) {
	return 1;
    }

    if ((defined ($provider{$capability})) and
	($provider{$capability} == $spec_id)) {
	return 1;
    }

    if (defined $provider{$capability}) {
	if ($build_status[$provider{$capability}] eq "PASSED") {
	    return 1;
	} elsif ($build_status[$provider{$capability}] eq "SKIPPED") {
	    if (!is_provided ($capability)) {
		&$warning_callback ($spec_name, $capability, "DEP_FAILED");
		return 0;
	    }
	    return 1;
	} elsif ($build_status[$provider{$capability}] ne "NOT_BUILT") {
	    if (!is_provided ($capability)) {
		&$warning_callback ($spec_name, $capability, "DEP_FAILED");
		return 0;
	    }
	    return 1;
	}

	msg_info (1, "$spec_name requires $capability");
	my $save_log_name = $current_log;
	my $result = &$recursive_callback ($provider{$capability}, @rec_cb_opts);
	open_log ($save_log_name);
	return $result;
    } elsif (!is_provided ($capability)) {
	&$warning_callback ($spec_name, $capability, "NOT_FOUND");
	return 0;
    } else {
	return 1;
    }

    # should not happen
    msg_error("Assertion failed: check_dependency: return 0");
    return 0;
}

# --------- copy build spec files, tarballs, patches -----------------------
sub find_spec ($) {
    my $fname = shift;

    my $spec_file;
    if (not ($fname =~ /^\// or -f $fname)) {
	msg_info (3, "Looking for spec file $fname");
	my @the_spec_dirlist = split /:/, $defaults->get ('specdirs');
	foreach my $sdir (@the_spec_dirlist) {
	    my $spath = "$sdir/$fname";
	    if (! -f "$spath") {
		msg_info (3, "   $fname not found in $sdir");
	    } else {
		msg_info (3, "   found in $sdir");
		$spec_file = "$spath";
		last;
	    }
	}
	if (not defined ($spec_file)) {
	    msg_warning (1, "spec file $fname not found");
	}
    } else {
	$spec_file = $fname;
    }

    return $spec_file;
}

sub copy_spec ($$) {
    my $spec = shift;
    my $spec_file = shift;

    my $base_name = $spec_file;
    $base_name =~ s/^.*\/([^\/]+)/$1/;
    my $target = "$topdir/SPECS/$base_name";

    msg_info (2, "copying spec file $spec_file to the SPECS dir");

    my $is_nightly = $defaults->get ('nightly');
    if ($is_nightly and ($os eq "linux")) {
	my $the_nightly_date_format = $defaults->get ('date_format');
	my $the_nightly_date = `date "+$the_nightly_date_format"`;
	if ($? > 0) {
	    msg_error ("incorrect date format: $the_nightly_date_format");
	    my $spec_id = $all_specs{$spec->get_file_name ()};
	    msg_error ("Assertion failed: copy_spec: can't find spec_id for $spec_file") unless defined $spec_id;
	    $build_status[$spec_id] = 'ERROR';
	    $status_details[$spec_id] = "incorrect nightly date format: $the_nightly_date";
	    return 0;
	}

	open SPEC_OUT, ">$target";
	my $msg=`cp $spec_file /tmp/.pkgtool.tmp.$$ 2>&1`;
	if ($? > 0) {
	    msg_error ("failed to copy $spec_file to $target");
	    my $spec_id = $all_specs{$spec->get_file_name ()};
	    msg_error ("Assertion failed: copy_spec: can't find spec_id for $spec_file (2)") unless defined $spec_id;
	    $build_status[$spec_id] = 'FAILED';
	    $status_details[$spec_id] = "cound not copy spec file: $msg";
	    return 0;
	}
	open SPEC_IN, "</tmp/.pkgtool.tmp.$$";
	my $line;
	while (1) {
	    $line = <SPEC_IN>;
	    if (not defined ($line)) {
		last;
	    }
	    if ($line =~ /^Release\s*:/) {
		$line =~ s/\s*$/.$the_nightly_date/;
	    }
	    print SPEC_OUT $line;
	}
	close SPEC_OUT;
	close SPEC_IN;

	`rm -f /tmp/.pkgtool.tmp.$$`;
	my @predefs = ();
	my $rpm_target = $defaults->get ('target');
	if (defined $rpm_target) {
	    @predefs = ("_target $rpm_target");
	}
	my $spec_id = $all_specs{$spec->get_file_name ()};
	delete ($all_specs{$spec->get_file_name ()});
	msg_error ("Assertion failed: copy_spec: can't find spec_id for $spec_file (3)") unless defined $spec_id;
	my $spec = rpm_spec->new ($target, $rpm_target);
	$all_specs{$spec->get_file_name ()} = $spec_id;
	$specs_to_build[$spec_id] = $spec;
    } else {
	`cmp -s $spec_file $target`;
	if ($? != 0) {  # the files differ
	    my $msg=`cp -f $spec_file $target 2>&1`;
	    if ($? > 0) {
		msg_error "failed to copy $spec_file to $target";
		my $spec_id = $all_specs{$spec->get_file_name ()};
		msg_error ("Assertion failed: copy_spec: can't find spec_id for $spec_file (3)") unless defined $spec_id;
		$build_status[$spec_id] = 'FAILED';
		$status_details[$spec_id] = "failed to copy spec file: $msg";
		return 0;
	    }
	} else {
	    msg_info (3, "   $spec_file and $target are identical; not copying");
	}
    }
    `chmod a+r $target`;
    
    return 1;
}

sub find_source ($$) {
    my $spec_id = shift;
    my $src = shift;
    my $is_tarball = 0;
    my $src_path;

    my @the_tarball_dirlist = split /:/, $defaults->get ('tarballdirs');
    if ($src =~ /\.(tar\.gz|tgz|tar\.bz2|tar\.bzip2|zip|jar)$/) {
	$is_tarball = 1;

	foreach my $srcdir (@the_tarball_dirlist) {
	    $src_path = "$srcdir/$src";
	    if (! -f "$src_path") {
		msg_info (3, "   $src not found in $srcdir");
	    } else {
		msg_info (3, "   found in $srcdir");
		return "$src_path";
	    }
	}
    }
    my @the_source_dirlist = split /:/, $defaults->get ('sourcedirs');
    foreach my $extsrcdir (@the_source_dirlist) {
	$src_path = "$extsrcdir/$src";
	if (! -f "$src_path") {
	    msg_info (3, "   $src not found in $extsrcdir");
	} else {
	    msg_info (3, "   found in $extsrcdir");
	    return "$src_path";
	}
    }

    if (!$is_tarball) {
	msg_info (3, "   trying the tarball directories");
	foreach my $srcdir (@the_tarball_dirlist) {
	    $src_path = "$srcdir/$src";
	    if (! -f "$src_path") {
		msg_info (3, "   $src not found in $srcdir");
	    } else {
		msg_info (3, "   found in $srcdir");
		msg_warning (1, "$src is not expected to be in the tarball dir");
		return $src_path;
	    }
	}
    }

    return undef;
}

sub wget_source ($$$) {
    my $spec_id = shift;
    my $src = shift;
    my $target = shift;

    if (! -x $wget) {
	print "WARNING: assertion failed: wget_source();\n";	
    }

    if (not $src =~ /^(http:\/\/|ftp:\/\/)/) {
	return 0
    }

    my $download_dir = $defaults->get ("download_to");
    $download_dir = "$target" unless defined ($download_dir);

    msg_info (0, "Downloading source $src");

    my $wget_command = "$wget -nd -nH -P $download_dir $src 2>&1";
    msg_info (2, "Running $wget_command");
    my $wget_output = `$wget_command`;
    chomp ($wget_output);
    my $retval = $?;

    if ($retval != 0) {
	$wget_output =~ s/\n/\nERROR: wget: /;
	print "ERROR: wget: $wget_output\n";
	msg_log ("ERROR: wget: $wget_output");
	msg_error ("Download failed: $src");
	$build_status[$spec_id] = 'ERROR';
	$status_details[$spec_id] = "Download failed: $src";
	return 0;
    }

    if ($download_dir ne $target) {
	my $src_path = $src;
	$src_path =~ s/^.*\/([^\/]+)/$1/;
	msg_info (1, "Source $src_path saved in $download_dir");
	$src_path = "$download_dir/$src_path";
	my $msg=`cp -f $src_path $target 2>&1`;
	if ($? > 0) {
	    msg_error ("failed to copy $src_path to $target");
	    $build_status[$spec_id] = 'ERROR';
	    $status_details[$spec_id] = $msg;
	    return 0;
	}
	`chmod a+r $target`;
    }

    return 1;
}

sub copy_sources ($) {
    my $spec_id = shift;
    my $spec = $specs_to_build[$spec_id];

    my @sources = $spec->get_sources ();
    my $src_path;
    my $target;

    my @packages = $spec->get_packages ();
    foreach my $pkg (@packages) {
	next if not defined $pkg;
	my $cp_file = $pkg->get_tag ('sunw_copyright');
	next if not defined $cp_file;
	push (@sources, $cp_file);
    }

    if ($spec->{_defines}->{_pkgbuild_version} =~ /0\.[789]/) {
	my @class_scripts = $spec->get_class_script_names ();
	push (@sources, @class_scripts);
    }

    msg_info (2, "copying sources to $topdir/SOURCES");

    foreach my $src (@sources) {
	if (not defined ($src)) {
	    next;
	}
	my $base_src = $src;
	$base_src =~ s/^.*\/([^\/]+)/$1/;
        $src_path = find_source ($spec_id, $base_src);
	if (not defined ($src_path)) {
	    if ($defaults->get ("download") and wget_in_path ()) {
		wget_source ($spec_id, $src, "$topdir/SOURCES") and next;
	    }
	    $build_status[$spec_id] = 'FAILED';
	    $status_details[$spec_id] = "Source $src not found";
	    msg_error ($specs_to_build[$spec_id] . ": Source file $src not found");
	    return 0;
	}

	msg_info (3, "   copying $base_src");

	$target = "$topdir/SOURCES/$base_src";

	`cmp -s $src_path $target`;

	if ($? != 0) {  # the files differ
	    my $msg=`cp -f $src_path $target 2>&1`;
	    if ($? > 0) {
		msg_error ("failed to copy $src_path to $target");
		$build_status[$spec_id] = 'ERROR';
		$status_details[$spec_id] = $msg;
		return 0;
	    }
	}

	`chmod a+r $target`;
    
    }

    return 1;
}

sub copy_patches ($) {
    my $spec_id = shift;
    my $spec = $specs_to_build[$spec_id];

    my @patches = $spec->get_patches ();
    my $patch_path;
    my $target;
    foreach my $patch (@patches) {
	if (not defined ($patch)) {
	    next;
	}

	msg_info (2, "looking for patch $patch");

	my @the_patch_dirlist = split /:/, $defaults->get ('patchdirs');
	foreach my $the_patch_dir (@the_patch_dirlist) {
	    $patch_path = "$the_patch_dir/$patch";
	    
	    if (! -f "$patch_path") {
		msg_info (3, "   $patch not found in $patch_path");
	    } else {
		msg_info (3, "   found in $patch_path");
		last;
	    }
	}

	if (! -f "$patch_path") {
	    $build_status[$spec_id] = 'ERROR';
	    $status_details[$spec_id] = "Patch $patch_path not found";
	    msg_error ("Patch $patch_path not found");
	    return 0;
	}

	$target = "$topdir/SOURCES/$patch";

	`cmp -s $patch_path $target`;

	if ($? != 0) {  # the files differ
	    my $msg=`cp -f $patch_path $target 2>&1`;
	    if ($? > 0) {
		msg_error "failed to copy $patch_path to $target";
		$build_status[$spec_id] = 'ERROR';
		$status_details[$spec_id] = $msg;
		return 0;
	    }
	} else {
	    msg_info (3, "   $patch and $topdir/SOURCES/$patch are identical; not copying");
	}

	`chmod a+r $target`;
    
    }

    return 1;
}

# --------- build command --------------------------------------------------
# optional args: build_only {1 = yes, 0 = no} == ! install
#                prep_only  {1 = yes, 0 = no}
sub do_build (;$$) {
    my $build_only = shift;
    my $prep_only = shift;
    $build_only = 0 unless defined $build_only;
    $prep_only = 0 unless defined $prep_only;

    for (my $i = 0; $i <= $#specs_to_build; $i++) {
	if ($build_status[$i] eq "NOT_BUILT") {
	    if (! build_spec ($i, $build_only, $prep_only)) {
		if (defined ($the_good_build_dir) and not $build_only) {
		    msg_info (0, "Attempting to use a known good package");
		    install_good_pkgs ($i);
		}
	    }
	    print_live_status;
	}
	if ($build_status[$i] ne "PASSED") {
	    if ($build_status[$i] ne "DEP_FAILED"
		and $build_status[$i] ne "SKIPPED") {
		$exit_val++;
		mail_log ($i);
	    }
	}
    }

    print_live_status;

    my $verbose = $defaults->get ('verbose');
    if ($verbose > 0) {
	print_status;
    }
}

sub build_spec ($$$) {
    my $spec_id = shift;
    my $build_only = shift;
    my $prep_only = shift;
    my $spec = $specs_to_build[$spec_id];

    my $logname = $defaults->get ('logdir') . "/" . get_log_name ($spec_id);

    msg_debug (0, "Trying to build $spec");
    open_log ($logname);

    if ($build_status[$spec_id] ne "NOT_BUILT") {
	if ($build_status[$spec_id] eq "DEP") {
	    $build_status[$spec_id]="ERROR";
	    $status_details[$spec_id]="Circular dependency detected";
	    msg_error ("Circular dependency detected " .
		"while trying to build $spec");
	}
	return 0;
    }

    my @packages = $spec->get_packages ();
    msg_debug (3, "packages: " . $spec->get_file_name () . " defines: @packages");

    my $check_deps = $defaults->get ('deps');
    if (not $build_only) {
	foreach my $pkg (@packages) {
	    if (not defined ($pkg)) {
		next;
	    }
	    msg_info (3, "Checking if $pkg is installed");
	    if (is_provided ("$pkg") and $check_deps) {
		my $provider = what_provides ("$pkg");
		my $pkgver = $pkg->eval ("%version");
		if ($provider eq "${pkg}-${pkgver}") {
		    msg_warning (0, "skipping package ${pkg}-${pkgver}: already installed");
		    $status_details[$spec_id]="${pkg}-${pkgver} already installed";
		} else {
		    msg_warning (0, "skipping package ${pkg}-${pkgver}: $provider already installed");
		    $status_details[$spec_id]="$provider installed";
		}
		$build_status[$spec_id]='SKIPPED';
		return 1;
	    }
	}
    }

    if ($check_deps) {
	my @dependencies = get_dependencies ($spec_id, @packages);

	my $this_result;
	my $result = 1;

	$build_status[$spec_id] = "DEP";
	$status_details[$spec_id] = "building dependencies first";
	
	msg_info (1, "Checking dependencies of $spec");

	foreach my $dep (@dependencies) {
	    $dep =~ s/ .*//;
	    
	    $this_result = check_dependency ($spec_id, $dep,
					     \&build_spec, \&warn_always, ($build_only, $prep_only));
	    if (!$this_result) {
		if (defined ($the_good_build_dir)) {
		    msg_info (0, "Attempting to use a known good package");
		    $this_result = install_good_pkgs ($dep);
		}
		if (! $this_result) {
		    msg_warning (1, "$spec won't be built as it requires $dep");
		}
	    }
	    $result = ($this_result and $result);
	}
	
	if (! $result) {
	    $build_status[$spec_id]="DEP_FAILED";
	    $status_details[$spec_id]="Dependency check failed";
	    return 0;
	}
    }

    copy_sources ($spec_id) || return 0;
    copy_patches ($spec_id) || return 0;

    if ($live_summary) {
	$build_status[$spec_id] = 'BEING_BUILT';
	$status_details[$spec_id] = "$build_engine running";
	print_live_status;
    }

    if ($prep_only) {
	if ($prep_only == 2) {
	    run_build ($spec_id, "-bs") || return 0;
	} else {
	    run_build ($spec_id, "-bp") || return 0;
	}
    } else {
	run_build ($spec_id) || return 0;
    }

    if (not $build_only) {
	if ($os eq "solaris") {
	    install_pkgs ($spec_id) || return 0;
	} else {
	    install_rpms ($spec_id) || return 0;
	}
    }

    $build_status[$spec_id] = "PASSED";
    $status_details[$spec_id] = "";

    close_log;

    return 1;

}

sub run_build ($;$) {
    my $spec_id = shift;
    my $build_mode = shift;
    $build_mode = "-ba" unless defined $build_mode;
    my $spec = $specs_to_build[$spec_id];
    my $spec_file = $spec->get_file_name ();
    my $base_name = $spec->get_base_file_name ();
    my $log_name = "$base_name";
    $log_name = get_log_name ($spec_id);
    my $builddir = $spec->get_value_of ("_topdir");
    my $build_user = getpwuid ((stat($builddir))[4]);
    chomp (my $id = `id`);
    $id =~ s/^uid=([0-9]*).*/$1/;
    my $running_user = getpwuid ($id);    
    my $command;

    msg_info (0, "Running $build_engine $build_mode $base_name ($spec)");
    my $the_log_dir = $defaults->get ('logdir');
    msg_info (1, "Log file: $the_log_dir/$log_name");

    my $the_command = $build_engine;
    my $check_deps = $defaults->get ('deps');
    if (not $check_deps) {
	$the_command = "$build_engine --nodeps";
    }
    my $interactive_mode = $defaults->get ('interactive');
    if ($interactive_mode and ($build_engine eq "pkgbuild")) {
	$the_command = "$the_command --interactive";
    }
    if ($build_engine eq "pkgbuild") {
	my $pkgformat = $defaults->get ('pkgformat');
	if ($pkgformat ne 'filesystem' and $pkgformat ne 'fs') {
	    $the_command = "$the_command --pkgformat $pkgformat";
	}
    }
    foreach my $def (@predefs) {
	next if not defined $def;
	$the_command = "$the_command --define '$def'";
    }

    if ($build_mode eq "-bp") {
	$the_command = "$the_command --nodeps";
    }

    my $save_log_name = $current_log;
    msg_log ("INFO: Starting $build_engine build engine at " . `date`);
    close_log;
    my $tempfile = "/tmp/$build_engine.out.$$";
# FIXME: ExclusiveArch?
    my $rpm_target = $defaults->get ('target');
    if (defined($rpm_target)) {
        $command = "$the_command --target $rpm_target $build_mode $spec_file";
    } else {
        $command = "$the_command $build_mode $spec_file";
    }
    if ($running_user eq "root") {
	$command = "/bin/su $build_user -c \"$command\"";
    }

    my $build_result;
    if ($interactive_mode) {
#	system ("( $command 2>&1 ; echo $? > /tmp/.pkgbuild.status.$$) | tee $tempfile");
#	$build_result = `cat /tmp/.pkgbuild.status.$$ && rm -f /tmp/pkgbuild.status.$$`
	system ($command);
	$build_result = $?;
    } else {
	`$command > $tempfile 2>&1`;
	$build_result = $?; 
    }
    system ("sed -e 's/^/$build_engine: /' $tempfile >> $the_log_dir/$log_name 2>&1; rm -f $tempfile");
    open_log ($save_log_name);
    msg_log ("INFO: $build_engine $build_mode finished at " . `date`);

    if ($build_result) {
	msg_error ("$spec FAILED");
	msg_info (0, "Check the build log in $save_log_name for details");
	$build_status[$spec_id] = "FAILED";
	$status_details[$spec_id] = "$build_engine build failed";
	return 0;
    }

    msg_info (0, "$spec PASSED");
    return 1;
}

# --------- build-order and install-order commands -------------------------
sub do_build_order () {
    for (my $i = 0; $i <= $#specs_to_build; $i++) {
	print_order ($i, \&print_spec);
    }
}

sub do_install_order () {
    for (my $i = 0; $i <= $#specs_to_build; $i++) {
	if ($os eq "solaris") {
	    print_order ($i, \&print_pkgs);
	} else {
	    print_order ($i, \&print_rpms);
	}
    }
}

sub print_order ($&) {
    my $spec_id = shift;
    my $print_command = shift;
    my $spec = $specs_to_build[$spec_id];

    if ($build_status[$spec_id] ne "NOT_BUILT") {
	if ($build_status[$spec_id] eq "DEP") {
	    $build_status[$spec_id]="ERROR";
	    $status_details[$spec_id]="Circular dependency detected";
	    msg_error ("Circular dependency detected " .
		"while checking dependencies of $spec");
	}
	return 0;
    }

    my $check_deps = $defaults->get ('deps');
    if ($check_deps) {
	my @packages = $spec->get_packages ();
	my @dependencies = get_dependencies ($spec_id, @packages);

	if (@dependencies) {
	    $build_status[$spec_id] = "DEP";
	
	    msg_info (1, "Checking dependencies of $spec");
	    
	    foreach my $dep (@dependencies) {
		$dep =~ s/ .*//;	
    
		check_dependency ($spec_id, $dep, \&print_order, 
				  \&warn_never, ($print_command));
	    }
	}
    }
    
    $build_status[$spec_id] = "PASSED";
    &$print_command ($spec_id);
}

sub do_download () {
    $defaults->set ("download", 1);
    for (my $spec_id = 0; $spec_id <= $#specs_to_build; $spec_id++) {
	my $spec = $specs_to_build[$spec_id];
	$build_status[$spec_id] = "DONE";
	msg_info (1, "Downloading sources for $spec");
	my @sources = $spec->get_sources ();
	foreach my $src (@sources) {
	    if (not defined ($src)) {
		next;
	    }
	    my $base_src = $src;
	    $base_src =~ s/^.*\/([^\/]+)/$1/;
	    my $src_path = find_source ($spec_id, $base_src);
	    if (not defined ($src_path)) {
		if (wget_in_path ()) {
		    wget_source ($spec_id, $src, "$topdir/SOURCES") and next;
		}
		$build_status[$spec_id] = 'FAILED';
		$status_details[$spec_id] = "Source $src not found";
		msg_error ($specs_to_build[$spec_id] . ": Source file $src not found");
		next;
	    }
	}
    }
    print_status ();
}

sub make_admin_file ($) {
    my $fname = shift;

    open ADMIN_FILE, ">$fname" or
	msg_error ("Failed to create pkgadd/pkgrm admin file $fname"),
	return undef;

    print ADMIN_FILE "mail=\n";
    print ADMIN_FILE "instance=unique\n";
    print ADMIN_FILE "conflict=quit\n";
    print ADMIN_FILE "setuid=nocheck\n";
    print ADMIN_FILE "action=nocheck\n";
    print ADMIN_FILE "partial=quit\n";
    print ADMIN_FILE "idepend=nocheck\n";
    print ADMIN_FILE "rdepend=nocheck\n";
    print ADMIN_FILE "space=quit\n";

    close ADMIN_FILE;
}

# --------- uninstall-pkgs command -----------------------------------------
sub do_uninstall_pkgs () {
    for (my $i = 0; $i <= $#specs_to_build; $i++) {
	print_order ($i, \&push_to_remove_list);
    }

    my $adminfile = "/tmp/pkg.admin.$$";
    my $command;
    my $pkgrm;
    if ($os eq "solaris") {
	make_admin_file ($adminfile);
	$command = "pfexec /usr/sbin/pkgrm -a $adminfile -n 2>&1";
	$pkgrm = "pkgrm";
    } else {
	$command = "rpm -v --erase --nodeps 2>&1";
	$pkgrm = "rpm";
    }
    my $verbose = $defaults->get ('verbose');
    my $remove_status;
    foreach my $ref (@remove_list) {
	my ($spec_id, $pkg_to_remove) = @$ref;
	if (is_installed ($pkg_to_remove)) {
	    msg_info (0, "Uninstalling $pkg_to_remove");
	    my $cmd_out = `$command $pkg_to_remove 2>&1`;
	    chomp ($cmd_out);
	    $remove_status = $?;
	    if ($remove_status > 0) {
		$build_status[$spec_id] = "FAILED";
		$status_details[$spec_id] = $cmd_out;
		$exit_val++;
	    } else {
		msg_info (1, "Successfully uninstalled $pkg_to_remove");
		if ($build_status[$spec_id] ne "FAILED") {
		    $build_status[$spec_id] = "UNINSTALLED";
		}
	    }
	    if ($cmd_out ne "") {
		if ($remove_status > 0) {
		    $cmd_out =~ s/\n(.)/\nERROR: $pkgrm: $1/;
		} else {
		    $cmd_out =~ s/\n(.)/\nINFO: $pkgrm: $1/;
		}
		if ($verbose > 1 or ($verbose > 0 and $remove_status > 0)) {
		    if ($remove_status > 0) {
			msg_error ($cmd_out);
		    } else {
			msg_info (1, $cmd_out);
		    }
		}
	    }
	} else {
	    msg_info (0, "Package $pkg_to_remove is not installed");
	    if ($build_status[$spec_id] eq "PASSED") {
		$build_status[$spec_id] = "NOT INSTLD";
	    }
	}
    }
    if ($os eq "solaris") {
	unlink ($adminfile);
    }
    if ($verbose > 0) {
	print_status;
    }
}

sub get_specs_used ($);

sub get_specs_used ($) {
    my $fname = shift;
    my @ret = ();

    msg_info (3, "Looking for files %included or %used by $fname");

    open SPEC_IN1, "<$fname" or 
	msg_warning (0, "Couldn't open $fname for reading"), 
	return @ret;
    my @lines = <SPEC_IN1>;
    close SPEC_IN1;

    my @includes = grep /^\s*%include\s/, @lines;
    foreach my $inc (@includes) {
	$inc =~ s/^\s*%include\s+(\S+)\s*$/$1/ or next;
	if ($inc =~ /^"(.*)"$/) {
	    $inc = $1;
	}
	push (@ret, $inc);
	$inc = find_spec ($inc);
	next if not defined $inc;
	my @subspecs = get_specs_used ($inc);
	if (@subspecs) {
	    push (@ret, @subspecs);
	}
    }

    my @uses = grep /^\s*%use\s/, @lines;
    foreach my $use (@uses) {
	if ($use =~ /^\s*%use\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(\S+)\s*$/) {
	    $use = $2;
	    if ($use =~ /^"(.*)"$/) {
		$use = $1;
	    }
	    push (@ret, $use);
	    $use = find_spec ($use);
	    next if not defined $use;
	    my @subspecs = get_specs_used ($use);
	    if (@subspecs) {
		push (@ret, @subspecs);
	    }
	}
    }

    return @ret;
}

my %specs_copied;

sub copy_specs () {
    msg_info (0, "Copying spec files to SPECS directory");
    for (my $spec_id = 0; $spec_id <= $#specs_to_build; $spec_id++) {
        my $spec = $specs_to_build[$spec_id];
	my $fname = $spec->get_file_name ();
	if ($defaults->get ('nightly')) {
	    my $fullfname = find_spec ($fname);
	    if (not defined ($fullfname)) {
		$build_status[$spec_id] = 'FAILED';
		$status_details[$spec_id] = "Spec file not found: $fname\n";
		next;
	    }
	    if (not defined ($specs_copied{$fullfname})) {
		$specs_copied{$fullfname} = 1;
		copy_spec ($spec, $fullfname) or $specs_copied{$fullfname} = 0;
	    }
	}
	my @used_specs = get_specs_used ($fname);
	next if not @used_specs;
	foreach my $subspec0 (@used_specs) {
	    my $subspec = find_spec ($subspec0);
	    if (not defined ($subspec)) {
		$build_status[$spec_id] = 'FAILED';
		$status_details[$spec_id] = "Spec file used by $fname not found: $subspec0\n";
		next;
	    }
	    if (!defined $specs_copied{$subspec}) {
		$specs_copied{$subspec} = 1;
		copy_spec ($spec, $subspec) or $specs_copied{$subspec} = 0;
	    }
	}
    }
}

sub process_specs () {
    msg_info (0, "Processing spec files\n");
    for (my $spec_id = 0; $spec_id <= $#specs_to_build; $spec_id++) {
	my $spec = $specs_to_build[$spec_id];
	next if ($build_status[$spec_id] ne "NOT_BUILT");
	msg_info (1, "Processing spec file " . $spec->get_base_file_name ());
	my @packages = $spec->get_packages ();
	if (defined $spec->{error}) {
	    $build_status[$spec_id] = 'ERROR';
	    $status_details[$spec_id] = $spec->{error};
	    msg_warning (0, "Failed to process spec file $spec: $spec->{error}");
	    next;
	}
	foreach my $pkg (@packages) {
	    next if not defined $pkg;
	    my $pkgname = $pkg->get_name();
	    if (defined ($provider{$pkgname})) {
		my $prev_spec = $specs_to_build[$provider{$pkgname}];
		msg_warning (0, "skipping spec file " . 
			     $spec->get_base_file_name() . 
			     ": $pkgname already defined by spec file " . 
			     $prev_spec->get_file_name ());
		$build_status[$spec_id] = "ERROR";
		$status_details[$spec_id] = "$pkgname is already defined by spec file " .
		    $prev_spec->get_file_name ();
	    } else {
		$provider{$pkgname} = $spec_id;
		msg_debug (2, "$pkgname is provided by spec $spec");
	    }
	    my @provides = $pkg->get_array ('provides');
	    foreach my $prov (@provides) {
		if (not defined $prov) {
		    next;
		}
		$prov =~ s/ .*//;
		if (defined ($provider{$prov}) and
		    ($provider{$pkgname} != $spec_id)) {
		    my $prev_spec = $specs_to_build[$provider{$prov}];
		    msg_warning (0, "skipping spec file " .
				 $spec->get_base_file_name() .
				 ": $pkgname is already defined by spec file "
				 . $prev_spec->get_file_name ());
		    if ($build_status[$spec_id] ne "ERROR") {
			$build_status[$spec_id] = "ERROR";
			$status_details[$spec_id] = "$pkgname is already defined by spec file " . $prev_spec->get_file_name ();
		    }
		} else {
		    $provider{$prov} = $spec_id;
		}
		msg_debug (2, "$prov is provided by spec $spec");
	    }
	}
    }
}

# --------- main program ---------------------------------------------------
sub main {
    process_defaults ();
    process_options ();

    my $summary_log = $defaults->get ('summary_log');
    if (defined ($summary_log) and -f $summary_log) {
	msg_error ("Summary build report $summary_log already exists")
	    or exit (1);
    }

    if (not defined ($specs_to_build[0])) {
	msg_info (0, "No spec files specified: nothing to do.");
	exit (0);
    }

    copy_specs ();
    process_specs ();

    if (not defined ($build_command)) {
	usage (1);
    }
    
    if ($build_command eq "build") {
	do_build;
    } elsif ($build_command eq "build-install") {
	do_build;
    } elsif ($build_command eq "build-only") {
	do_build (1);
    } elsif ($build_command eq "prep") {
	do_build (1, 1);
    } elsif ($build_command eq "spkg") {
	do_build (1, 2);
    } elsif ($build_command eq "uninstall-pkgs") {
	do_uninstall_pkgs;
    } elsif ($build_command eq "build-order") {
	do_build_order;
    } elsif ($build_command eq "install-order") {
	do_install_order;
    } elsif ($build_command eq "download") {
	do_download;
    }

    exit ($exit_val);
}

init;
main;
