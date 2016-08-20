package rpm_spec;
use v5.10;

use YAML::XS;
use autodie;

my $yaml_filename = 'mapping.yaml';
my $distro_names;
my $distro_regexs;
my $mappings;
my $distro_num;
our @distro_defines = ();

sub determine_distro {
    my $uname = `uname -v`; chomp $uname;
    for ( my $i = 0; $i < scalar @$distro_regexs; $i++ ) {
	if ( $uname =~ $distro_regexs->[$i] ) { return $i; }
    }
    die 'Unknown distribution';
}

sub read_yaml_file {
    my $pathname = shift . $yaml_filename;
    my $defines;
    if (not -f $pathname) { return; }
    my $data = do {
	if (open my $fh, '<', $pathname) { local $/; <$fh> }
	else { undef }
    };
    ( $distro_names, $distro_regexs, $defines, $mappings ) = Load( $data );
    $distro_num = determine_distro();

    # Create an association list with the distribution-specific defines
    my @defines = %$defines;
    for (my $i=0; $i < scalar @defines; $i+=2) {
	$distro_defines[$i] = $defines[$i];
	my $value = $defines[$i+1];
	$distro_defines[$i+1] = ref $value ? $value->[$distro_num] : $value;
    }
}

sub distro_pkgname {
    my $key = shift;
    return "" unless $mappings;
    my $symb = $mappings->{$key};
    if (defined $symb) {
	ref $symb ? $symb->[$distro_num] : $symb;
    } else {
	"";
    }
}

return 1;
