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
    $self->{_blocks} = {};
    my @files = ();
    $self->{_files} = \@files;

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

sub get_files ($) {
    my $self = shift;

    my $files = $self->{_files};
    return @$files if $files;
    return undef;
}

sub get_block ($$) {
    my $self = shift;
    my $block_name = shift;

    return $self->{_blocks}->{$block_name};
}

1;
