use strict;
use warnings;

package config;

# Create a new rpm_file object.
sub new ($) {
    my $class = shift;
    my $self = {};
    my %defvals = ();
    my %rcvals = ();
    my %clvals = ();
    my %valid_keys = ();
    my %docs = ();
    $self->{'valid_keys'} = \%valid_keys;
    $self->{'defvals'} = \%defvals;
    $self->{'rcvals'} = \%rcvals;
    $self->{'clvals'} = \%clvals;
    $self->{'docs'} = \%docs;

    return (bless $self, $class);
}

sub _is_type ($$) {
    my $type = shift;
    my $val = shift;

    if ($type eq 's') {
	if (defined ($val)) {
	    return 1;
	}
	return 0;
    } elsif ($type eq 'n') {
	if ($val =~ /^[0-9]+$/) {
	    return 1;
	}
	return 0;
    } elsif ($type eq '!') {
	if ($val eq '0' or $val eq '1') {
	    return 1;
	}
	return 0;
    }
}

sub add ($$$$;$) {
    my $self = shift;
    my $key = shift;
    my $type = shift;
    my $docs = shift;
    my $defval = shift;

    if (defined ($self->{'valid_keys'}->{$key})) {
	print "ERROR: option $key already defined\n";
	return 0;
    }

    if (not $type =~ /^[sn!]$/) {
	print "ERROR: unknown type \"$type\" for option $key\n";
	return 0;
    }

    $self->{'valid_keys'}->{$key} = $type;
    $self->{'docs'}->{$key} = $docs;

    if (defined ($defval)) {
	if (_is_type ($type, $defval)) {
	    $self->{'defvals'}->{$key} = $defval;
	    return 1;
	} else {
	    print "ERROR: Default value for option $key is invalid.\n";
	}
    }
}

sub get ($$) {
    my $self = shift;
    my $key = shift;

    if (not defined ($self->{'valid_keys'}->{$key})) {
	return undef;
    }

    if (defined ($self->{'clvals'}->{$key})) {
	return ($self->{'clvals'}->{$key});
    }

    if (defined ($self->{'rcvals'}->{$key})) {
	return ($self->{'rcvals'}->{$key});
    }

    if (defined ($self->{'defvals'}->{$key})) {
	return ($self->{'defvals'}->{$key});
    }

    return undef;
}

sub set ($$$) {
    my $self = shift;
    my $key = shift;
    my $value = shift;

    if (defined $self->{'valid_keys'}->{$key}) {
	if (_is_type ($self->{'valid_keys'}->{$key}, $value)) {
	    $self->{'clvals'}->{$key} = $value;
	    return 1;
	} else {
	    print "WARNING: Value for option $key is invalid.\n";
	}
    } else {
	print "ERROR: Unknown option: $key\n";
    }
    return 0;
}

sub norc ($) {
    my $self = shift;
    my %rcvals = ();
    $self->{'rcvals'} = \%rcvals;
}

sub _deref ($$$) {
    my $self = shift;
    my $str = shift;
    my $varref = shift;

    if (not defined ($str)) {
	return undef;
    }

    foreach my $var (keys %$varref) {
	next if not defined $var;
	my $val = $$varref{$var};
	$str =~ s/\${$var}/$val/g;
    }

    return $str;
}

sub readrc ($$) {
    my $self = shift;
    my $fname = shift;

    if (! -f $fname) {
	return 0;
    }

    my %vars;

    if (! open RCFILE, "<$fname") {
	print ("WARNING: Failed to open file $fname\n");
	return 0;
    }

    my $rcdir = `/usr/bin/dirname $fname`;
    chomp ($rcdir);
    $rcdir = `cd $rcdir; pwd`;
    chomp ($rcdir);
    $vars{'MYDIR'} = $rcdir;

    my $line = <RCFILE>;
    while ($line) {
	if ($line =~ /^\s*([a-zA-Z][a-zA-Z_0-9]*)\s*:\s*"([^"]*)"\s*$/) {
            my $key = lc ($1);
            my $value = $self->_deref ($2, \%vars);
            if (defined ($self->{'valid_keys'}->{$key})) {
                if (_is_type ($self->{'valid_keys'}->{$key}, $value)) {
	            $self->{'rcvals'}->{$key} = $value;
                } else {
                    print "WARNING: $fname: Incorrect value \"$value\" for option $key\n";
                }
            } else {
                print "WARNING: $fname: Unknown option \"$key\"\n";
            }
        } elsif ($line =~ /^\s*([a-zA-Z][a-zA-Z_0-9]*)\s*:\s*(.+)\s*$/) {
	    my $key = lc ($1);
            my $value = $self->_deref ($2, \%vars);
            if (defined ($self->{'valid_keys'}->{$key})) {
                if (_is_type ($self->{'valid_keys'}->{$key}, $value)) {
	            $self->{'rcvals'}->{$key} = $value;
                } else {
                    print "WARNING: $fname: Incorrect value \"$value\" for option $key\n";
                }
            } else {
                print "WARNING: $fname: Unknown option \"$key\"\n";
            }
        } elsif ($line =~ /^\s*([A-Z_]+)\s*=\s*"([^"]*)"\s*$/) {
	    my $var = $1;
	    my $val = $2;
	    $vars{$var} = $self->_deref ($val, \%vars);
        } elsif ($line =~ /^\s*([A-Z_]+)\s*=\s*(\S+)\s*$/) {
	    my $var = $1;
	    my $val = $2;
	    $vars{$var} = $self->_deref ($val, \%vars);
	} elsif ($line =~ /^\s*no([a-zA-Z][a-zA-Z0-9_]*)\s*$/){
	    my $key = lc ($1);
            if (defined ($self->{'valid_keys'}->{$key})) {
                if ($self->{'valid_keys'}->{$key} eq '!') {
	            $self->{'rcvals'}->{$key} = 0;
                } else {
                    print "WARNING: $fname: option $key is not boolean\n";
                }
            } else {
                print "WARNING: $fname: Unknown option \"$key\"\n";
            }
	} elsif ($line =~ /^\s*([a-zA-Z][a-zA-Z0-9_]*)\s*$/){
	    my $key = lc ($1);
            if (defined ($self->{'valid_keys'}->{$key})) {
                if ($self->{'valid_keys'}->{$key} eq '!') {
	            $self->{'rcvals'}->{$key} = 1;
                } else {
                    print "WARNING: $fname: option $key is not boolean\n";
                }
            } else {
                print "WARNING: $fname: Unknown option \"$key\"\n";
            }
	} elsif ($line =~ /^\s*$/) {
	    1;
	} elsif ($line =~ /^\s*#/) {
	    1;
	} else {
	    print "WARNING: $fname: Syntax error in rc file: \"$line\"\n";
	}
	$line = <RCFILE>;
    }
    return 1;
}

sub get_default ($$) {
    my $self = shift;
    my $key = shift;

    if (defined ($self->{'valid_keys'}->{$key})) {
	return $self->{'defvals'}->{$key};
    }

    return undef;
}

sub dumprc ($) {
    my $self = shift;

    my $keysref = $self->{'valid_keys'};
    foreach my $key (keys %$keysref) {
	my $type = $self->{'valid_keys'}->{$key};
	if ($type eq 's') {
	    $type = 'string';
	} elsif ($type eq 'n') {
	    $type = 'integer';
	} elsif ($type eq '!') {
	    $type = 'boolean';
	}
	print "# $key [$type]: " . $self->{'docs'}->{$key} . "\n";
	my $val = $self->get ($key);
	if (defined ($val)) {
	    my $defval = $self->get_default ($key);
	    if (defined ($defval) and $val eq $defval) {
		print "# $key:\t$val\n";
	    } else {
		print "$key:\t$val\n";
	    }
	}
	print "\n";
    }
}

1;
