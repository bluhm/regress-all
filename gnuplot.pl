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
getopts('vD:P:', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] -D date -O file file
    -v		verbose
    -D date	run date
    -P file	gnuplot file
EOF
    exit(2);
};
my $verbose = $opts{v};
my $date = $opts{D}
    or die "No -D run date";
my $run = str2time($opts{D})
    or die "Invalid -D date '$opts{D}'";
my $plotfile = $opts{P}
    or die "No -P gnuplot file";

# better get an errno than random kill by SIGPIPE
$SIG{PIPE} = 'IGNORE';

my $performdir = dirname($0). "/..";
my $gnuplotdir = "$performdir/results/gnuplot";
chdir($gnuplotdir)
    or die "Chdir to '$gnuplotdir' failed: $!";
$gnuplotdir = getcwd();

# collect gnuplot test.data and write output to date-plot.format

-f $plotfile
    or die "No gnuplot file '$plotfile' in $gnuplotdir";
my $testdata = "test.data";
-f $testdata
    or die "No test data file '$testdata";
(my $outfile = basename($plotfile)) =~ s/\.[^.]*//;
$outfile = "$date-$outfile.svg";

my @plotcmd = ("gnuplot", "-d",
    "-e", "RUN_DATE='$run'",
    "-e", "DATA_FILE='$testdata'",
    "-e", "OUT_FILE='$outfile.new'",
    $plotfile);
print "Command '@plotcmd' started\n" if $verbose;
system(@plotcmd)
    and die "system @plotcmd failed: $?";
print "Command '@plotcmd' finished\n" if $verbose;

rename("$outfile.new", $outfile)
    or die "Rename '$outfile.new' to '$outfile' failed: $!";
