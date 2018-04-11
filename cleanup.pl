#!/usr/bin/perl

use strict;
use warnings;
use Cwd;
use File::Basename;
use File::Path;
use Getopt::Std;
use POSIX;

my $scriptname = "$0 @ARGV";

my %opts;
getopts('m:nv', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-nv] [-m months]
    -m months	keep directories from past months, default 1
    -n		do not clean, just display obsolete directories
    -v		verbose
EOF
    exit(2);
};

my ($year, $month, $day) = split('-', strftime("%F", gmtime));

my $dir = dirname($0). "/..";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";
my $regressdir = getcwd();
$dir = "results";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";

my @datedirs = glob('20[0-9][0-9]-[01][0-9]-[0-3][0-9]T*Z');

foreach my $date (reverse sort @datedirs) {
    my ($y, $m, $d) = $date =~ /^(\d+)-(\d+)-(\d+)T/
	or die "Bad date directory name: $date";
    if (($year*12+$month) - ($y*12+$m) <= ($opts{m} || 1)) {
	print "skip $date\n" if $opts{v};
	next;
    }
    if ($d =~ /5$/) {
	print "skip $date\n" if $opts{v};
	next;
    }
    print "remove $date\n" if $opts{v};
    rmtree($date) unless $opts{n};
}
