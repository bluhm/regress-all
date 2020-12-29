#!/usr/bin/perl
# remove directories with old results

# Copyright (c) 2018-2020 Alexander Bluhm <bluhm@genua.de>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

use strict;
use warnings;
use Cwd;
use File::Basename;
use File::Path qw(remove_tree);
use Getopt::Std;
use POSIX;

my $scriptname = "$0 @ARGV";

my %opts;
getopts('d:m:nvw:y:', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-nv] [-m months] [-w weeks]
    -d days	remove log and obj tgz older than days, default 3
    -m months	thin out directories older than months, default 1
    -n		do not clean, just display obsolete directories
    -v		verbose
    -w weeks	remove setup and run log than weeks, default 4
    -y years	remove all directories older than years, default 1
EOF
    exit(2);
};
my $dy = 365.25;
my $dm = $dy/12;
my $dw = 7;
my $alldays = ($opts{y} // 1) * $dy;
my $thindays = ($opts{m} // 1) * $dm;
my $logdays = ($opts{w} // 4) * $dw;
my $tgzdays = ($opts{d} // 3);

my $now = strftime("%FT%TZ", gmtime);
my ($year, $month, $day) = $now =~ /^(\d+)-(\d+)-(\d+)T/
    or die "Bad date: $now";

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
    my $age = ($year*$dy + $month*$dm + $day) - ($y*$dy + $m*$dm + $d);

    if ($age > $alldays or ($age > $thindays && $d !~ /5$/)) {
	print "remove $date\n" if $opts{v};
	remove_tree($date, { safe => 1 }) unless $opts{n};
	next;
    }
    my @cleanfiles;
    if ($age > $tgzdays) {
	push @cleanfiles, glob("$date/test.*.tgz");
    }
    if ($age > $logdays) {
	push @cleanfiles, glob("$date/*.log");
    }
    if (@cleanfiles) {
	print "clean $date\n" if $opts{v};
	unlink(@cleanfiles) or die "Unlink '@cleanfiles' failed: $!"
	    unless $opts{n};
	next;
    }
    print "skip $date\n" if $opts{v};
}
