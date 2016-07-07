package pkgnmmap;
use v5.10;
use parent qw(Exporter);
use YAML::XS;
use autodie;

our @EXPORT_OK = qw(read_yaml_file distro_pkgname);

my $csv_filename = '../data/mapping.csv';
my $yaml_filename = 'include/mapping.yaml';
my $distro_names;
my $distro_regexs;
my $mappings;
my $distro_num;

sub determine_distro {
    my $uname = `uname -v`; chomp $uname;
    for ( my $i = 0; $i < scalar @$distro_regexs; $i++ ) {
	if ( $uname =~ $distro_regexs->[$i] ) { return $i; }
    }
    die 'Unknown distribution';
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

return 1;
