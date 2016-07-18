package rpm_spec;
use v5.10;

use YAML::XS;
use autodie;

my $yaml_filename = 'mapping.yaml';
my $distro_names;
my $distro_regexs;
my $mappings;
my $distro_num;

# Define these temporarily here until it is more clear how we are going to go
# about doing this.
our @distro_defines = ('solaris11' => 0, 'oihipster' => 0, 'omnios' => 0,
    'solaris12' => 0);

sub determine_distro {
    my $uname = `uname -v`; chomp $uname;
    for ( my $i = 0; $i < scalar @$distro_regexs; $i++ ) {
	if ( $uname =~ $distro_regexs->[$i] ) { return $i; }
    }
    die 'Unknown distribution';
}

sub read_yaml_file {
    my $pathname = shift . $yaml_filename;
    if (not -f $pathname) { return; }
    my $data = do {
	if (open my $fh, '<', $pathname) { local $/; <$fh> }
	else { undef }
    };
    ( $distro_names, $distro_regexs, $mappings ) = Load( $data );
    $distro_num = determine_distro();
    # We are at the proof of concept stage with this
    $distro_defines[2*$distro_num + 1] = 1;
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
