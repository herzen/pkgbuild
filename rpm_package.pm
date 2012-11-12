#
#  The pkgbuild build engine
#
#  Copyright 2009 Sun Microsystems, Inc.
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
use rpm_spec;
use rpm_file;

package rpm_package;

sub get_name ($);

use overload ('""' => \&get_name);	  

my $package_counter = 0;

# Create a new rpm_package object.
sub new ($$;&) {
    my $class = shift;
    my $parent_spec_ref = shift;
    my $name = shift;
    my $self = {};

    $self->{_id} = ++$package_counter;

    $self->{_parent_spec_ref} = $parent_spec_ref;
    $self->{_tags} = {};
    $self->{_tag_opts} = {};
    $self->{_meta} = {};
    $self->{_tags}->{release} = 0;
    my $ips_os_rel = `uname -r`;
    chomp ($ips_os_rel);
    $self->{_tags}->{ips_component_version} = '%{version}';
    $self->{_tags}->{ips_build_version} = $ips_os_rel;
    my $os_build;
    if (-x "/usr/bin/pkg") {
	$os_build = `pkg info -l release/name | grep Branch`;
	chomp($os_build);
	$os_build =~ s/^.*: *([0-9.]+)/$1/;
    } else {
	$os_build = `uname -v`;
	chomp ($os_build);
	$os_build =~ s/^\S+_([0-9]+).*/$1/;
    }
    $self->{_tags}->{ips_vendor_version} = "0.$os_build";
    my $target = $$parent_spec_ref->{_defines}->{"_target_cpu"};
    if (defined $target) {
	$self->{_tags}->{buildarchitectures} = $target;
    } else {
	$self->{_tags}->{buildarchitectures} = `uname -p`;
    }
    for my $tag_name ("buildrequires", "requires", "obsoletes",
		      "prereq", "provides") {
	my @dummy;
	$self->{_tags}->{$tag_name} = \@dummy;
    }
    $self->{_blocks} = {};
    my @metafiles = ();
    $self->{_metafiles} = \@metafiles;
    my @defattr = ('-', '-', '-', '-');
    $self->{_defattr} = \@defattr;

    # initialisation
    if (defined ($name)) {
	$self->{_tags}->{name} = $name;
    }

    $self->{_is_subpkg} = 0;

    return (bless $self, $class);
}

sub new_subpackage ($$$;$$) {
    my $class = shift;
    my $parent_spec_ref = shift;
    my $name = shift;
    my $pkg_tag = shift;
    my $is_subpkg = shift;
    my $self = {};

    $self->{_parent_spec_ref} = $parent_spec_ref;
    $self->{_id} = ++$package_counter;

    # initialisation
    $self->{_name} = $name;
    my @packages = $$parent_spec_ref->get_packages ();
    if (not defined ($packages[0])) {
	die ("new_subpackage should only be used when the main package is " .
	     "already defined.");
    }

    my $tags = $packages[0]->{_tags};
    $self->{_tags} = {%$tags};
    $self->{_parent_spec_ref} = $parent_spec_ref;
    $self->{_tags}->{name} = $name;
    $self->{_tags}->{sunw_pkg} = undef;
    $self->{_tags}->{ips_package_name} = undef;
    for my $tag_name ("buildrequires", "requires", "obsoletes",
		      "prereq", "provides") {
	my @dummy;
	$self->{_tags}->{$tag_name} = \@dummy;
    }
    my $tag_opts = $packages[0]->{_tag_opts};
    $self->{_tag_opts} = {%$tag_opts};

    my $meta = $packages[0]->{_meta};
    $self->{_meta} = {%$meta};
    
    $self->{_blocks} = {};
    my @metafiles = ();
    $self->{_metafiles} = \@metafiles;
    my @defattr = ('-', '-', '-', '-');
    $self->{_defattr} = \@defattr;
    # the tag of the subpkg, e.g. devel, l10n
    $self->{_pkg_tag} = $pkg_tag;
    if (not defined ($is_subpkg)) {
	if (defined ($pkg_tag)) {
	    $is_subpkg = 1;
	} else {
	    $is_subpkg = 0;
	}
    }
    $self->{_is_subpkg} = $is_subpkg;

    return (bless $self, $class);
}

sub get_spec ($) {
    my $self = shift;
    return undef unless defined ($self->{_parent_spec_ref});
    return ${$self->{_parent_spec_ref}};
}

sub get_svr4_name ($) {
    my $self = shift;
    if (defined $self->{_tags}->{sunw_pkg}) {
	return $self->{_tags}->{sunw_pkg};
    }
    return $self->{_tags}->{name};
}

sub get_ips_name ($) {
    my $self = shift;
    # the %package has its own IPS package name
    if (defined $self->{_tags}->{ips_package_name}) {
	return $self->{_tags}->{ips_package_name};
    }
    # it doesn't have its own IPS name, if it's a subpackage,
    # the IPS name is the name of the main package otherwise
    # it's the value of Name
    if ($self->{_is_subpkg}) {
	my $parent_ref = $self->{_parent_spec_ref};
	return $$parent_ref->get_ips_name();
    } else {
	return $self->{_tags}->{name};
    }
}

sub set_tag ($$$;$) {
    my $self = shift;
    my $tag_name = shift;
    my $value = shift;
    my $tag_opt = shift;

    $self->{_tags}->{$tag_name} = $value;
    if (defined ($tag_opt) and ($tag_opt ne "")) {
	$self->{_tag_opts}->{$tag_name} = $tag_opt;
    } else {
	$self->{_tag_opts}->{$tag_name} = undef;
    }
}

sub get_tag ($$) {
    my $self = shift;
    my $tag_name = shift;

    $tag_name = lc ($tag_name);

    return $self->{_tags}->{$tag_name};
}

sub get_value_of ($$) {
    my $self = shift;
    my $name = shift;

    my $lcname = lc ($name);

    if (defined ($self->{_tags}->{$lcname})) {
	return $self->{_tags}->{$lcname};
    }

    my $evname = $self->eval("%$name");
    return $evname unless $evname eq "%$name";

    return undef;
}

sub get_tag_opts ($$) {
    my $self = shift;
    my $tag_name = shift;

    $tag_name = lc ($tag_name);

    return $self->{_tag_opts}->{$tag_name};
}

sub set_meta ($$$) {
    my $self = shift;
    my $meta_name = shift;
    my $value = shift;
    $self->{_meta}->{$meta_name} = $value;
}

sub get_meta ($$) {
    my $self = shift;
    my $meta_name = shift;
    $meta_name = lc($meta_name);
    return $self->{_meta}->{$meta_name};
}

sub get_meta_hash ($) {
    my $self = shift;
    my $meta_ref = $self->{_meta};
    return {%$meta_ref};
}

sub get_pkg_tag ($) {
    my $self = shift;
    return $self->{_pkg_tag};
}

sub is_subpkg ($) {
    my $self = shift;
    return $self->{_is_subpkg};
}

sub set_subpkg ($$) {
    my $self = shift;
    my $val = shift;
    $self->{_is_subpkg} = $val;
}

sub set_svr4_match ($$) {
    my $self = shift;
    my $pkgref = shift;

    $self->{_svr4_match} = $pkgref;
    if (defined ($pkgref->{_svr4_rev_match})) {
	my $rev_matches = $pkgref->{_svr4_rev_match};
	push (@$rev_matches, $self);
    } else {
	my @rev_matches = ($self);
	$pkgref->{_svr4_rev_match} = \@rev_matches;
    }
}

sub has_svr4_match ($) {
    my $self = shift;
    return defined ($self->{_svr4_match});
}

sub eval ($$) {
    my $self = shift;
    my $string = shift;

    return ${$self->{_parent_spec_ref}}->eval($string);
}

sub get_svr4_src_pkg_name ($) {
    my $self = shift;

    return ${$self->{_parent_spec_ref}}->get_svr4_src_pkg_name();
}

sub _set_error ($$;$) {
    my $self = shift;
    my $msg = shift;

    return ${$self->{_parent_spec_ref}}->_set_error($msg);
}

sub push_tag ($$$) {
    my $self = shift;
    my $tag_name = shift;
    my $value = shift;

    if (not defined ($self->{_tags}->{$tag_name})) {
	my @arr = ($value);
	$self->{_tags}->{$tag_name} = \@arr;
    } else {
	my $ref = $self->{_tags}->{$tag_name};
	push (@$ref, $value);
    }
}

sub set_ord_tag ($$$$) {
    my $self = shift;
    my $tag_name = shift;
    my $tag_num = shift;
    my $value = shift;

    if (not defined ($tag_num) or $tag_num eq "") {
	$tag_num = 0;
    }

    if (not defined ($self->{_tags}->{$tag_name})) {
	my @arr = ();
	$arr[$tag_num] = $value;
	$self->{_tags}->{$tag_name} = \@arr;
    } else {
	my $ref = $self->{_tags}->{$tag_name};
	if (defined $$ref[$tag_num]) {
	    my $parent_ref = $self->{_parent_spec_ref};
	    print "WARNING: " . 
		$$parent_ref->get_base_file_name() .
		": $tag_name$tag_num redefined\n";
	}
	$$ref[$tag_num] = $value;
    }
}

sub get_name ($) {
    my $self = shift;

    if (not defined ($self->{_tags}->{name})) {
	return undef;
    }
    return $self->{_tags}->{name};
}

sub get_array ($$) {
    my $self = shift;
    my $tag_name = shift;

    my $ref = $self->{_tags}->{$tag_name};
    if (not defined ($ref)) {
	return ();
    }
    return @$ref;
}

sub tag_is_defined ($$) {
    my $self = shift;
    my $tag_name = shift;

    return defined ($self->{_tags}->{$tag_name});
}

sub block_is_defined ($$) {
    my $self = shift;
    my $block_name = shift;

    return defined ($self->{_blocks}->{$block_name});
}

sub append_to_block ($$$) {
    my $self = shift;
    my $block_name = shift;
    my $text_to_append = shift;

    if (defined ($self->{_blocks}->{$block_name})) {
	$self->{_blocks}->{$block_name} = 
	    $self->{_blocks}->{$block_name} . "\n" . $text_to_append;
    } else {
	$self->{_blocks}->{$block_name} = $text_to_append;
    }
}

sub add_action($$) {
    my $self = shift;
    my $action_string = shift;
    
    if (not defined $self->{_actions}) {
        my @actions_array = ();
        $self->{_actions} = \@actions_array;
    }
    return if not defined $action_string;
    my $actions = $self->{_actions};
    push(@$actions, $action_string);
}

sub set_default_mogrify($$) {
    my $self = shift;
    my $fname = shift;

    $self->{__default_mogrify} = $fname;
}

sub unset_default_mogrify($) {
    my $self = shift;

    $self->{__no_default_mogrify} = 1;
}

sub get_default_mogrify($) {
    my $self = shift;

    if (defined ($self->{__no_default_mogrify})) {
	return undef;
    }

    if (defined ($self->{__default_mogrify})) {
	return $self->{__default_mogrify};
    }

    my $pkgbuild_d_m_r = $self->eval('%{?__pkgbuild_default_mogrify_rules}');
    if ($pkgbuild_d_m_r ne '') {
	return $pkgbuild_d_m_r;
    }

    return undef;
}

sub add_mogrify_rule($$) {
    my $self = shift;
    my $rule_string = shift;
    
    if (not defined $self->{_mogrify_rules}) {
        my @rules_array = ();
        $self->{_mogrify_rules} = \@rules_array;
    }
    return if not defined $rule_string;
    my $rules = $self->{_mogrify_rules};
    push(@$rules, $rule_string);
}

sub get_mogrify_rules($) {
    my $self = shift;
    return ($self->{_mogrify_rules});
}

sub add_file ($$) {
    my $self = shift;
    my $file = shift;

    if (not defined $self->{_files}) {
	my @fs = ();
	$self->{_files} = \@fs;
    }
    return if not defined $file;
    my $files = $self->{_files};
    push (@$files, $file);
}

sub add_metafile ($$) {
    my $self = shift;
    my $fname = shift;

    if (defined ($self->{_metafiles_loaded}) and
	$self->{_metafiles_loaded}) {
	return 0;
    }
    my $metafiles = $self->{_metafiles};
    push (@$metafiles, $fname);
    $self->{_metafiles_loaded} = 0;
    return 1;
}

sub get_files ($;$) {
    my $self = shift;
    my $ips = shift;

    my $metafiles = $self->{_metafiles};
    if (@$metafiles and not $self->{_metafiles_loaded}) {
	my $parent_spec_ref = $self->{_parent_spec_ref};
	foreach my $metafile (@$metafiles) {
	    $$parent_spec_ref->load_metafile ($metafile, "$self") 
		or return undef;
	}
	$self->{_metafiles_loaded} = 1;
    }
    if (not $ips) {
	return undef if defined ($self->{_svr4_match});
    }
    my $files = $self->{_files};
    my @all_match_files = ();
    if (not $ips) {
	if (defined ($self->{_svr4_rev_match})) {
	    my $matches = $self->{_svr4_rev_match};
	    foreach my $match (@$matches) {
		my $match_files = $match->{_files};
		next if not defined($match_files);
		if (@$match_files) {
		    push (@all_match_files, @$match_files);
		}
	    }
	}
    }
    my @all_files;
    if (defined ($files)) {
	@all_files = (@$files, @all_match_files);
    } else {
	@all_files = @all_match_files;
    }
    return @all_files if @all_files;
    return undef;
}

sub has_files ($;$) {
    my $self = shift;
    my $ips = shift;

    $ips = 0 if not defined ($ips);

    return 1 if defined $self->{_files};
    return 1 if defined $self->{_actions};
    my $reqs = $self->{_tags}->{requires};
    return 1 if @$reqs;
    my $metafiles = $self->{_metafiles};
    return 1 if @$metafiles;
    if (not $ips and defined ($self->{_svr4_match})) {
	my $match_ref = $self->{_svr4_match};
	return 1 if $match_ref->has_files();
    } 
    if (not $ips and defined ($self->{_svr4_rev_match})) {
	foreach my $match_rev (@{$self->{_svr4_rev_match}}) {
	    return 1 if defined $match_rev->{_files};
	    return 1 if defined $match_rev->{_actions};
	    my $mreqs = $match_rev->{_tags}->{requires};
	    return 1 if @$mreqs;
	}
    }
    return 0;
}

sub get_classes ($) {
    my $self = shift;

    my @classes;
    my %cl;
    my @files = $self->get_files ();
    foreach my $file (@files) {
	next if not defined ($file);
	$cl{$file->get_class ()} = 1;
    }
    @classes = keys %cl;
    return @classes;
}

sub get_block ($$) {
    my $self = shift;
    my $block_name = shift;

    return $self->{_blocks}->{$block_name};
}

sub get_error ($) {
    my $self = shift;
    my $parent_spec = $self->{_parent_spec_ref};
    return $$parent_spec -> {error};
}

sub get_class_script ($$$) {
    my $self = shift;
    my $class_name = shift;
    my $script_name = shift;

    my $parent_spec = $self->{_parent_spec_ref};
    return $$parent_spec -> get_class_script ($class_name, $script_name);
}

sub set_defattr ($$$$$) {
    my $self = shift;
    my $mode = shift;
    my $user = shift;
    my $group = shift;
    my $dirmode = shift;

    $self->{_defattr}= [$mode, $user, $group, $dirmode];
}

sub get_defattr ($) {
    my $self = shift;
    
    my $defattr_ref = $self->{_defattr};
    return @$defattr_ref;
}

sub set_filelist ($$) {
    my $self = shift;
    $self->{_filelist} = shift;
}

sub get_filelist ($) {
    my $self = shift;
    return $self->{_filelist};
}

1;
