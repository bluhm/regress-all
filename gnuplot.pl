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
use Testvars qw(%TESTDESC);

my %opts;
getopts('vnB:d:E:p:r:', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-vn] [-B date] [-d date] [-E date] -p plot [-r release]
    -v		verbose
    -n		dry run
    -B date	begin date of x range, inclusive
    -d date	run date of performance test
    -E date	end date of x range, inclusive
    -p plot	(tcp|tcp6|udp|udp6|linux|linux6|forward|forward6|ipsec|make|fs)
    -r release	OpenBSD version number
EOF
    exit(2);
};
my $verbose = $opts{v};
my $dry = $opts{n};
my $release;
if ($opts{r} && $opts{r} ne "current") {
    ($release = $opts{r}) =~ /^\d+\.\d+$/
	or die "Release '$release' must be major.minor format";
}
my ($run, $date);
if ($opts{d}) {
    $run = str2time($opts{d})
	or die "Invalid -d date '$opts{d}'";
    $date = $opts{d};
}
my ($begin, $end);
if ($opts{B}) {
    $begin = str2time($opts{B})
	or die "Invalid -B date '$opts{B}'";
}
if ($opts{E}) {
    $end = str2time($opts{E})
	or die "Invalid -E date '$opts{E}'";
}
my $plot = $opts{p}
    or die "Option -p plot missing";

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

my $gplotfile = "$performdir/bin/plot.gp";
-f $gplotfile
    or die "No gnuplot file '$gplotfile'";
my $datafile = "$gnuplotdir/test-$plot.data";
-f $datafile
    or die "No test data file '$datafile' in $gnuplotdir";

my $prefix = "";
$prefix .= "$release-" if $release;
$prefix .= "$date-" if $date;
$prefix .= "$plot";

my ($UNIT, %SUBTESTS);
parse_data_file();

exit unless keys %SUBTESTS;

my @descs = sort keys %SUBTESTS;

create_plot_files();

exit if $dry;

my $num = @descs;
create_key_files(1, $num) unless -f "key_$num.png";

my $htmlfile = "$prefix.html";
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
	input[type=\"checkbox\"]:not(:checked)".(" + * "x(2 * @descs)).
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
foreach my $cmd (@descs) {
    print $html "<input id=\"checkbox-$i\" checked type=checkbox>
	<label for=\"checkbox-$i\">
	<img class=\"key\" src=\"key_$i.png\" alt=\"Key $i\">
	$cmd
	</label>";
    $i++;
}

print $html "<img id=\"frame\" src=\"";
print $html "$prefix\_0.png\" alt=\"". uc($plot). " Grid\">";

$i = 1;
foreach my $cmd (@descs) {
    print $html "<img src=\"";
    print $html "$prefix\_$i.png\" alt=\"". uc($plot). " $cmd\">";
    print $html "<span></span>";
    $i++;
}

print $html "<img id=\"combined\" src=\"";
print $html "$prefix.png\" alt=\"". uc($plot). " Performance\">";

print $html "</body>
</html>";

rename("$htmlfile.new", $htmlfile)
    or die "Rename '$htmlfile.new' to '$htmlfile' failed: $!";

exit;

sub parse_data_file {
    open (my $fh, '<', $datafile)
	or die "Open '$datafile' for reading failed: $!";

    # test subtest run checkout repeat value unit host
    <$fh>; # skip file head
    my ($test, $sub, $checkout, $unit);
    while (<$fh>) {
	($test, $sub, undef, $checkout, undef, undef, $unit) = split;
	next unless $unit;
	$UNIT ||= $unit;
	next if $begin && $checkout < $begin;
	next if $end && $end < $checkout;
	$SUBTESTS{"$TESTDESC{$test} $sub"} = "$test $sub";
    }
}

sub create_plot_files {
    # sort by description, use test values for gnuplot
    my @tests = map { $SUBTESTS{$_} } sort keys %SUBTESTS;
    my @quirks = sort keys %{{quirks()}};

    my $title = uc($plot). " Performance";

    my @vars = (
	"DATA_FILE='$datafile'",
	"PREFIX='$prefix'",
	"QUIRKS='@quirks'",
	"TESTS='@tests'",
	"TITLE='$title'",
	"UNIT='$UNIT'"
    );
    push @vars, "RUN_DATE='$run'" if $run;
    push @vars, "XRANGE_MIN='$begin'" if $begin;
    push @vars, "XRANGE_MAX='$end'" if $end;
    my @cmd = ("gnuplot", "-d");
    if ($dry) {
	push @cmd, (map { ("-e", "\"$_\"") } @vars);
	push @cmd, $gplotfile;
	print "@cmd\n";
    } else {
	push @cmd, (map { ("-e", $_) } @vars);
	push @cmd, $gplotfile;
	print "Command '@cmd' started.\n" if $verbose;
	system(@cmd)
	    and die "Command '@cmd' failed: $?";
	print "Command '@cmd' finished.\n" if $verbose;
    }
}

sub create_key_files {
    my ($from, $to) = @_;
    my @cmd = ("$performdir/bin/keys.sh", $from, $to);
    print "Command '@cmd' started.\n" if $verbose;
    system(@cmd)
	and die "Command '@cmd' failed: $?";
    print "Command '@cmd' finished.\n" if $verbose;
}
