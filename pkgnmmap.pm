package pkgnmmap;
use v5.10;
use parent qw(Exporter);
use YAML::XS;
use autodie;

our @EXPORT_OK = qw(read_yaml_file distro_pkgname);

my $csv_filename = '../data/mapping.csv';
my $yaml_filename = 'include/mapping.yaml';
my @col_titles;
my @unames;
my %mappings;
my $monopkgs = 0;
my $multipkgs = 0;
my $distro_names;
my $distro_regexs;
my $mappings;
my $distro_num;

sub read_csv_file {
    open CSVS, '<', shift;
    my $line = <CSVS>;
    chomp $line;
    @col_titles = split /,/, $line;
    @unames = split /,/, $line;
    # Discard first item of titles lists, which describes what the symbols mean
    shift @col_titles; shift @unames;
    while ($line = <CSVS>) {
	chomp $line;
	my ($key, @list) = split /,/, $line;
	if (members_eq(@list)) {
	    $mappings{$key} = $list[0];
	    $monopkgs++;
	} else {
	    $mappings{$key} = \@list;
	    $multipkgs++;
	}
    }
}

# We are all Haskell programmers now
sub members_eq {
    my ($head, @tail) = @_;
    if (!@tail) {
	return 1;
    }
    elsif ($head ne $tail[0]) {
	return 0;
    }
    else { members_eq (@tail); }
}

sub determine_distro {
    my $uname = `uname -v`; chomp $uname;
    for ( my $i = 0; $i < scalar @$distro_regexs; $i++ ) {
	if ( $uname =~ $distro_regexs->[$i] ) { return $i; }
    }
    die 'Unknown distribution';
}

sub create_yaml_file {
    read_csv_file ($csv_filename);
    say "$multipkgs packages with different names; $monopkgs with the same name";

    open YAMLS, '>', $yaml_filename;
    print YAMLS Dump( \@col_titles, \@unames, \%mappings );
}

sub read_yaml_file {
    my $data;
    if (not -f $yaml_filename) { return; }
    $data = do {
	if (open my $fh, '<', $yaml_filename) { local $/; <$fh> }
	else { undef }
    };
    ( $distro_names, $distro_regexs, $mappings ) = Load( $data );
    $distro_num = determine_distro();
}

sub distro_pkgname {
    my $key = shift;
    unless ($mappings) {
	die '(Build)Requires tag was used but mappings.yaml file is not present';
    }
    my $symb = $mappings->{$key};
    ref $symb ? $symb->[$distro_num] : $symb;
}

sub dump_keys {
    read_yaml_file ();
    print "@$distro_names\n";
    print keys %$mappings, "\n";
}

return 1;
