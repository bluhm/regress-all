#!/usr/bin/perl
# collect cvs logs between certain dates for sub branches

# Copyright (c) 2018-2020 Alexander Bluhm <bluhm@genua.de>
# Copyright (c) 2018-2019 Moritz Buhl <mbuhl@genua.de>
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
use Buildquirks;
my $scriptname = "$0 @ARGV";

my %opts;
getopts('vC:D:T:', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] [-D date] -T test
    -v		verbose
    -D date	run date
    -T test	tcp|tcp6|linux|linux6|make|udp|udp6|fs
EOF
    exit(2);
};
my $verbose = $opts{v};
my ($run, $date);
if ($opts{D}) {
    $run = str2time($opts{D})
	or die "Invalid -D date '$opts{D}'";
    $date = $opts{D};
}
my $test = $opts{T}
    or die "Option -T test missing";

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

my $testfile = "$performdir/bin/plot.gp";
-f $testfile
    or die "No gnuplot file '$testfile'";
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

my $testnames = join(" ", sort keys %tests);
my %q = quirks();
my $quirks = join(" ", sort keys %q);

my $outprefix = "";
$outprefix .= "$date-" if $run;
$outprefix .= "$test";

my @plotcmd = ("gnuplot", "-d",
    "-e", "DATA_FILE='$testdata'",
    "-e", "OUT_PREFIX='$outprefix'",
    "-e", "QUIRKS='$quirks'",
    "-e", "TESTS='$testnames'",
    "-e", "TITLE='$title'",
    "-e", "UNIT='$unit'");
push @plotcmd, "-e", "RUN_DATE='$run'" if $run;
push @plotcmd, $testfile;
print "Command '@plotcmd' started\n" if $verbose;
system(@plotcmd)
    and die "system @plotcmd failed: $?";
print "Command '@plotcmd' finished\n" if $verbose;

my $htmlfile = "";
$htmlfile .= "$date-" if $date;
$htmlfile .= "$test.html";
unlink("$htmlfile.new");
open(my $html, '>', "$htmlfile.new")
    or die "Open '$htmlfile.new' for writing failed: $!";
my $htmltitle = uc $opts{T}. " Performance";
$htmltitle .= ", run $date" if $date;

print $html "<!DOCTYPE html>
<html>
<head>
    <title>OpenBSD Perform $htmltitle Results</title>
    <style>
	body {
	    display: flex;
	    flex-direction: row;
	    flex-wrap: wrap;
	    margin-top: 768px;
	}
	img {
	    position: absolute;
	    left: 0;
	    right: 0;
	    max-width: 100%;
	    top: 0;
	}
	input {
	    z-index: 2;
	    margin: 0;
	    width: 24px;
	    height: 16px;
	}
	input[type=\"checkbox\"]:not(:checked)".(" + * "x(2 * keys %tests)).
	"+ img {
	    display: none;
	}
	body :nth-child(6n) {
	    page-break-after: always;
	}
	label {
	    display: inherit;
	    width: calc(33vw - 30px);
	    align-items: center;
	}
	.key {
	    position: unset;
	    margin: 0 2px;
	    height: 24px;
	    width: 16px;
	}
	#frame {
	    z-index: 1;
	}
	#combined {
	    z-index: 2;
	    opacity: 0;
	}
    </style>
</head>
<body>";

my $i = 1;
foreach my $cmd (sort keys %tests) {
    print $html "<input id=\"checkbox-$i\" checked type=checkbox>
	<label for=\"checkbox-$i\">
	<img class=\"key\" src=\"key_$i.png\" alt=\"Key $i\">
	$cmd
	</label>";
    $i++;
}

print $html "<img id=\"frame\" src=\"";
print $html "$date-" if ($date);
print $html "$test\_0.png\" alt=\"". uc($test). " Grid\">";

$i = 1;
foreach my $cmd (sort keys %tests) {
    print $html "<img src=\"";
    print $html "$date-" if ($date);
    print $html "$test\_$i.png\" alt=\"". uc($test). " $cmd\"><span></span>";
    $i++;
}

print $html "<img id=\"combined\" src=\"";
print $html "$date-" if ($date);
print $html "$test.png\" alt=\"". uc($test). " Performance\">";

print $html "</body>
</html>";

rename("$htmlfile.new", $htmlfile)
    or die "Rename '$htmlfile.new' to '$htmlfile' failed: $!";
