use strict;
use warnings;
use rpm_package;

package packagebase;

my $packagebase;

sub new ($) {
    my $class = shift;

    $packagebase ||= bless {}, $class;
}

sub add_package ($) {
    my $self = shift;
    my $package = shift;

    if (not defined ($self->{_all_packages})) {
	my @arr;
	$self->{_all_packages} = \@arr;
    }
    my $ref = $self->{_all_packages};
    push (@$ref, \$package);
}

sub find_package_by_name ($) {
    my $self = shift;
    my $name = shift;

    my $ref = $self->{_all_packages};
    foreach my $package (@$ref) {
	if ($$package->get_tag ("name") eq $name) {
	    return $$package;
	}
    }
    return undef;
}

sub add_spec ($) {
    my $self = shift;
    my $spec = shift;

    if (not defined ($self->{_all_specs})) {
	my @arr;
	$self->{_all_specs} = \@arr;
    }
    my $ref = $self->{_all_specs};
    push (@$ref, \$spec);
}

sub find_spec_by_file_name ($) {
    my $self = shift;
    my $fname = shift;

    my $ref = $self->{_all_specs};
    foreach my $spec (@$ref) {
	if ($$spec->get_file_name () eq $fname) {
	    return $$spec;
	}
    }
    return undef;
}

sub find_spec_by_base_name ($) {
    my $self = shift;
    my $fname = shift;

    my $ref = $self->{_all_specs};
    foreach my $spec (@$ref) {
	if ($$spec->get_base_file_name () eq $fname) {
	    return $$spec;
	}
    }
    return undef;
}

1;
