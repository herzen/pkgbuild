use strict;
use warnings;
use rpm_spec;
use rpm_file;

package rpm_package;

sub get_name ($);

use overload ('""' => \&get_name);	  

# Create a new rpm_package object.
sub new ($$;&) {
    my $class = shift;
    my $parent_spec_ref = shift;
    my $name = shift;
    my $self = {};

    $self->{_parent_spec_ref} = $parent_spec_ref;
    $self->{_tags} = {};
    $self->{_tags}->{release} = 0;
    my $target = $$parent_spec_ref->{_defines}->{"_target"};
    if (defined $target) {
	$self->{_tags}->{buildarchitectures} = $target;
    } else {
	$self->{_tags}->{buildarchitectures} = 'i386';
    }
    $self->{_blocks} = {};
    my @files = ();
    $self->{_files} = \@files;
    my @metafiles = ();
    $self->{_metafiles} = \@metafiles;
    my @defattr = ('-', '-', '-');
    $self->{_defattr} = \@defattr;

    # initialisation
    if (defined ($name)) {
	$self->{_tags}->{name} = $name;
    }

    return (bless $self, $class);
}

sub new_subpackage ($$$) {
    my $class = shift;
    my $parent_spec_ref = shift;
    my $name = shift;
    my $self = {};

    $self->{_parent_spec_ref} = $parent_spec_ref;

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
    for my $tag_name ("buildrequires", "requires", "obsoletes",
		      "prereq", "provides") {
	$self->{_tags}->{$tag_name} = ();
    }

    $self->{_blocks} = {};
    my @files = ();
    $self->{_files} = \@files;
    my @metafiles = ();
    $self->{_metafiles} = \@metafiles;
    my @defattr = ('-', '-', '-');
    $self->{_defattr} = \@defattr;

    return (bless $self, $class);
}

sub set_tag ($$$) {
    my $self = shift;
    my $tag_name = shift;
    my $value = shift;

    $self->{_tags}->{$tag_name} = $value;
}

sub get_tag ($$) {
    my $self = shift;
    my $tag_name = shift;

    $tag_name = lc ($tag_name);

    return $self->{_tags}->{$tag_name};
}

sub eval ($$) {
    my $self = shift;
    my $string = shift;

    return ${$self->{_parent_spec_ref}}->eval($string);
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
	return undef;
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

sub add_file ($$) {
    my $self = shift;
    my $file = shift;

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

sub get_files ($) {
    my $self = shift;

    my $metafiles = $self->{_metafiles};
    if (@$metafiles and not $self->{_metafiles_loaded}) {
	my $parent_spec_ref = $self->{_parent_spec_ref};
	foreach my $metafile (@$metafiles) {
	    $$parent_spec_ref->load_metafile ($metafile, "$self") 
		or return undef;
	}
	$self->{_metafiles_loaded} = 1;
    }
    my $files = $self->{_files};
    return @$files if $files;
    print "WARNING: %files missing for package $self\n";
    return undef;
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

sub set_defattr ($$$$) {
    my $self = shift;
    my $mode = shift;
    my $user = shift;
    my $group = shift;

    my $defattr_ref = $self->{_defattr};
    @$defattr_ref = ($mode, $user, $group);
}

sub get_defattr ($) {
    my $self = shift;
    
    my $defattr_ref = $self->{_defattr};
    return @$defattr_ref;
}

1;
