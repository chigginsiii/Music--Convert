#!/usr/bin/perl

use strict;
use Music::Tag;
use File::Basename;
use File::Find;
use File::Spec;
use File::Path qw(make_path);
use Getopt::Long;
use Cwd;

my $prog = File::Basename::basename($0);
my $USAGE = qq{
$prog - convert oggs to mp3s and bring over tag info

$prog --source|-s <source dir> --dest|-d <dest dir> [--clobber|-c]

* source default:   current directory
* dest default:     <source>/converted_to_mp3/
* ogg2dec params:   -R -e 1 -s 1 -b 16
* lame params:      --brief -r -s 44.1 --bitwidth 16 --signed --preset fast extreme -
* tags migrated:    album artist disc genre title track
* --clobber         overwrite existing files in the destination directory
};

my ($opt_src_dir, $opt_dest_dir, $opt_clobber);
GetOptions(
    'source|s:s' => \$opt_src_dir,
    'dest|d:s'   => \$opt_dest_dir,
    'help|h|?'   => sub { print "$USAGE\n"; exit(0); },
    'clobber|c'  => \$opt_clobber,
);

# searching:
my $src_dir = $opt_src_dir || Cwd::cwd();
File::Spec->rel2abs($src_dir);
# putting converted into:
my $dest_dir = $opt_dest_dir || File::Spec->catdir($src_dir, 'converted_to_mp3');
$dest_dir = File::Spec->rel2abs( $dest_dir );

my @oggs;
sub want_oggs {
    if (
	(my ($dev,$ino,$mode,$nlink,$uid,$gid) = lstat($_))
	&& -f _
	&& /.*\.ogg\z/) {
	my $info = Music::Tag->new($_, {quiet => 1}, "OGG");
	$info->get_tag();
        if ( !$info->artist() || !$info->album() ) {
            print STDERR "Can not find artist or album for $File::Find::name, skipping\n";
            next;
        }
	my $mp3_dirname = File::Spec->catdir(map { clean_filename($_) } $info->artist(), $info->album());
        if ( !$info->track() || !$info->title() ) {
            print STDERR "Can not find artist or album for $File::Find::name, skipping\n";
            next;
        }
	my $mp3_filename = clean_filename( sprintf("%02i - %s.mp3", $info->track, $info->title) );
	push @oggs, [ $File::Find::name, $mp3_dirname, $mp3_filename ];
    }
}
print "Searching $src_dir for OGGs...";
find({ wanted => \&want_oggs }, $src_dir);
if ( scalar @oggs == 0 ) {
    print "No oggs found in $src_dir, exiting!\n";
    exit(0);
}

print "Converting " . scalar(@oggs). " oggs from $src_dir into mp3s to $dest_dir\n";

my $tag_map = {
    'disc' => 'discnum',
    'track' => 'tracknum'
};
foreach my $ogg ( @oggs ) {
    my ($src_file, $mp3_path, $mp3_filename) = @$ogg;
    my $convert_path = File::Spec->catdir($dest_dir, $mp3_path);

    my $convert_fullpath =  File::Spec->catfile($convert_path, $mp3_filename);
    if ( -f $convert_fullpath && !$opt_clobber ) {
        print "Already converted, skipping!\n";
        next;
    }

    # there's some things in the paths i wouldna expected to have to hack around
    my $escaped_path = $convert_path;
    $escaped_path =~ s/\Q`\E/\Q\`\E/g;
    my $escaped_src_file = $src_file;
    $escaped_src_file =~ s/\Q`\E/\Q\`\E/g;

    if (! -d $escaped_path) {
        print "Creating export directory $escaped_path\n";
        make_path($convert_path, {mode => 0711});
    }
    my $oggdec_cmd = q{oggdec -R -e 1 -s 1 -b 16 -o -};
    my $lame_cmd = q{lame --brief -r -s 44.1 --bitwidth 16 --signed --preset fast extreme - };
    my $convert_cmd = qq{$oggdec_cmd "$escaped_src_file" | $lame_cmd "$convert_fullpath"};
    print "Converting $src_file => $convert_fullpath\n";
    system($convert_cmd);

    if ( 1 ) {
        print "Setting MP3 tags for $mp3_filename\n";

        my $ogg_info = Music::Tag->new($src_file, {quiet => 1}, 'OGG');
        $ogg_info->get_tag();
        my $mp3_info = Music::Tag->new($convert_fullpath, {quiet => 1}, 'MP3');
        $mp3_info->get_tag();

        foreach my $field ( qw(album artist disc genre title track) ) {
            my $mp3_field = $tag_map->{$field} || $field;
            $mp3_info->set_data($mp3_field, $ogg_info->get_data($field)) if !$mp3_info->get_data($mp3_field);
        }
        $mp3_info->set_tag();
        $mp3_info->close();
        $ogg_info->close();
    }

}

sub clean_filename {
    my $str = shift;
    my $nstr = $str;
    $nstr =~ s/\//-/g;
    $nstr =~ s/[^\w\.\-\_\(\)\[\] ]//g;
    $nstr =~ s/__{2,}/_/g;
    return $nstr;
}
