use strict;
use warnings;

package rpm_file;

sub get_glob ($);

use overload ('""' => \&get_glob);

my @_all_verify =  ('owner', 'group', 'mode', 'md5', 'size', 'maj', 'min',
		    'symlink', 'mtime');

# Create a new rpm_file object.
sub new ($$;$$$$$$) {
    my $class = shift;
    my $glob = shift;
    my $attribs = shift;
    my $verify = shift;
    my $is_recursive = shift;
    my $is_doc = shift;
    my $is_config = shift;
    my $class_name = shift;
    my $self = {};

    if (not @$attribs) {
	my @new_attribs = ('-', '-', '-');
	$attribs = \@new_attribs;
    } else {
	my @new_attribs = (@$attribs);
	$attribs = \@new_attribs;
    }

    if (not @$verify) {
	my @new_verify = (@_all_verify);
	$verify = \@new_verify;
    } else {
	$verify = _process_verify ($verify);
    }

    if (not defined $is_recursive) {
	$is_recursive = 1;
    }

    if (not defined $is_doc) {
	$is_doc = 0;
    }

    if (not defined $is_config) {
	$is_config = 0;
    }

    $self->{_glob} = $glob;
    $self->{_attributes} = $attribs;
    $self->{_verify} = $verify;
    $self->{_is_doc} = $is_doc;
    $self->{_is_config} = $is_config;
    $self->{_is_recursive} = $is_recursive;
    if (defined ($class_name)) {
	$self->{_class} = $class_name;
    } else {
	$self->{_class} = "none";
    }

    return (bless $self, $class);
}

sub _process_verify ($) {
    my $verify_ref = shift;

    my @verify = (@$verify_ref);

    if ($verify[0] ne "not") {
	return \@verify;
    }

    my @new_verify = ();

    foreach my $name (@_all_verify) {
	my $do_add = 1;
	for (my $i = 1; $i <= $#verify; $i++) {
	    if ($name eq $verify[$i]) {
		$do_add = 0;
		last;
	    }
	}
	if ($do_add) {
	    push (@new_verify, $name);
	}
    }

    return \@new_verify;
}

sub get_all_verify () {
    return (@_all_verify);
}

sub get_attributes ($) {
    my $self = shift;

    my $ref = $self->{_attributes};
    return @$ref;
}

sub get_verify ($) {
    my $self = shift;

    my $ref = $self->{_verify};
    return @$ref;
}

sub has_verify ($$) {
    my $self = shift;
    my $name = shift;

    my $ref = $self->{_verify};
    foreach my $val (@$ref) {
	if ($val eq $name) {
	    return 1;
	}
    }

    return 0;
}

sub is_doc ($) {
    my $self = shift;

    return $self->{_is_doc};
}

sub is_config ($) {
    my $self = shift;

    return $self->{_is_config};
}

sub is_recursive ($) {
    my $self = shift;

    return $self->{_is_recursive};
}

sub get_glob ($) {
    my $self = shift;

    return $self->{_glob};
}

sub get_class ($) {
    my $self = shift;

    return $self->{_class};
}

1;
