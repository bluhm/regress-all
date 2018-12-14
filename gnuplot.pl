#!/usr/bin/perl
# collect cvs logs between certain dates for sub branches

# Copyright (c) 2018 Alexander Bluhm <bluhm@genua.de>
# Copyright (c) 2018 Moritz Buhl <mbuhl@genua.de>
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
use Date::Parse;
use File::Basename;
use Getopt::Std;
use POSIX;
use Time::Local;

use lib dirname($0);
my $scriptname = "$0 @ARGV";

my %opts;
getopts('vC:D:T:', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] [-C date] [-D date] -T tcp|make|udp
    -v		verbose
    -C date	checkout date
    -D date	run date
    -T test	test name (tcp, make, upd)
EOF
    exit(2);
};
my $verbose = $opts{v};
my $run = str2time($opts{D})
    or die "Invalid -D date '$opts{D}'"
    if ($opts{D});
my $chk = str2time($opts{C})
    or die "Invalid -C date '$opts{C}'"
    if ($opts{C});
my $test = $opts{T}
    or die "Option -T tcp|make|udp missing";

# better get an errno than random kill by SIGPIPE
$SIG{PIPE} = 'IGNORE';

my $performdir = dirname($0). "/..";
chdir($performdir)
    or die "Chdir to '$performdir' failed: $!";
$performdir = getcwd();
my $gnuplotdir = "results/gnuplot";
chdir($gnuplotdir)
    or die "Chdir to '$gnuplotdir' failed: $!";
$gnuplotdir = getcwd();

my $plotfile = "$performdir/bin/plot.gp";
-f $plotfile
    or die "No gnuplot file '$plotfile'";
my $testdata = "test-$test.data";
-f $testdata
    or die "No test data file '$testdata' in $gnuplotdir";

my $title = uc($test). " Performance";
my %tests;
open (my $fh, '<', $testdata)
    or die "Open '$testdata' for reading failed: $!";

<$fh>; # skip file head
my ($tst, $sub, undef, undef, undef, undef, $unit)  = split(/\s+/, <$fh>);
$tests{"$tst $sub"} = 1;

while (my $row = <$fh>) {
    my ($tst, $sub) = split(/\s+/, $row);
    $tests{"$tst $sub"} = 1;
}

my $testnames = join(" ", keys %tests);

my $outfile = "";
$outfile .= "$opts{D}-" if $run;
$outfile .= "$opts{C}-" if $chk;
$outfile .= "$test.svg";

my @plotcmd = ("gnuplot", "-d",
    "-e", "DATA_FILE='$testdata'",
    "-e", "OUT_FILE='$outfile.new'",
    "-e", "TESTS='$testnames'",
    "-e", "TITLE='$title'",
    "-e", "UNIT='$unit'");
push @plotcmd, "-e", "RUN_DATE='$run'" if $run;
push @plotcmd, "-e", "CHECKOUT_DATE='$chk'" if $chk;
push @plotcmd, $plotfile;
print "Command '@plotcmd' started\n" if $verbose;
system(@plotcmd)
    and die "system @plotcmd failed: $?";
print "Command '@plotcmd' finished\n" if $verbose;

rename("$outfile.new", $outfile)
    or die "Rename '$outfile.new' to '$outfile' failed: $!";
