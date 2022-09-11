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
use Html;
use Testvars qw(%TESTDESC);

my %opts;
getopts('vnB:d:E:LN:p:r:X:x:Y:y:', \%opts) or do {
    print STDERR <<"EOF";
usage: gnuplot.pl [-Lnv] [-B date] [-d date] [-E date] [-N numbers] -p plot
	[-r release] [-x min] [-X max] [-y min] [-Y max]
    -v		verbose
    -n		dry run
    -B date	begin date of x range, inclusive
    -d date	run date of performance test
    -E date	end date of x range, inclusive
    -L		create LaTeX and EPS output instead of PNG and HTML
    -N numbers	list of test numbers
    -p plot	(tcp|tcp6|udp|udp6|linux|linux6|forward|forward6|ipsec|make|fs)
    -r release	OpenBSD version number
    -x min	x range minimum
    -X max	x range maximum
    -y min	y range minimum
    -Y max	y range maximum
EOF
    exit(2);
};
my $verbose = $opts{v};
my $dry = $opts{n};
my $release;
if ($opts{r} && $opts{r} ne "current") {
    ($release = $opts{r}) =~ /^\d+\.\d$/
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
my $latex = $opts{L};
my ($xmin, $xmax, $ymin, $ymax);
if (defined $opts{x}) {
    $opts{x} =~ /^\d+$/
	or die "x min '$opts{x}' not a number";
    $xmin = $opts{x};
}
if (defined $opts{X}) {
    $opts{X} =~ /^\d+$/
	or die "X max '$opts{X}' not a number";
    $xmax = $opts{X};
}
if (defined $opts{y}) {
    $opts{y} =~ /^\d+$/
	or die "y min '$opts{y}' not a number";
    $ymin = $opts{y};
}
if (defined $opts{Y}) {
    $opts{Y} =~ /^\d+$/
	or die "Y max '$opts{Y}' not a number";
    $ymax = $opts{Y};
}
my @numbers;
if (defined $opts{N}) {
    $opts{N} =~ /^\d+(,\d+)*$/
	or die "Numbers '$opts{N}' is not a list of numbers";
    @numbers = split(/,/, $opts{N});
}
my $plot = $opts{p}
    or die "Option -p plot missing";
@ARGV and die "No arguments allowed";

# better get an errno than random kill by SIGPIPE
$SIG{PIPE} = 'IGNORE';

my $performdir = dirname($0). "/..";
chdir($performdir)
    or die "Change directory to '$performdir' failed: $!";
$performdir = getcwd();

my $gplotfile = "$performdir/bin/plot.gp";
-f $gplotfile
    or die "No gnuplot file '$gplotfile'";

my $gnuplotdir = "results/gnuplot";
if ($latex) {
    $gnuplotdir = ".";
} elsif ($date) {
    my $reldate = "$date";
    $reldate = "$release/$reldate" if $release;
    $gnuplotdir = "results/$reldate/gnuplot";
} elsif ($release && !($begin || $end)) {
    $gnuplotdir = "results/$release/gnuplot";
}
chdir($gnuplotdir)
    or die "Change directory to '$gnuplotdir' failed: $!";
$gnuplotdir = getcwd();

my $datafile = "$plot.data";
if ($latex) {
    $datafile = "results/$date/$plot.data" if $date;
    $datafile = "results/$release/$plot.data" if $release;
    $datafile = "results/test.data" if ! -f $datafile;
}
-f $datafile
    or die "No test data file '$datafile' in $gnuplotdir";

my $prefix = "";
$prefix .= "gnuplot/" if $latex;
$prefix .= "$release-" if $release && ($begin || $end || $latex);
$prefix .= "$date-" if $date && $latex;
$prefix .= "$plot";
$prefix .= "-" . join(',', @numbers) if @numbers;

my ($UNIT, %SUBTESTS);
parse_data_file();

my @files = $latex ? (glob("$prefix.tex"), glob("$prefix.eps")) :
    (glob("$prefix.png"), glob("${prefix}_*.png"), glob("$prefix.html"));
unlink(@files) if @files;
exit if !keys %SUBTESTS && ($date || $release);

create_plot_files();

exit if $dry || $latex;

my $num = scalar keys %SUBTESTS;
create_key_files(1, $num) unless -f "key_$num.png";

create_html_file();

exit;

sub parse_data_file {
    open (my $fh, '<', $datafile)
	or die "Open '$datafile' for reading failed: $!";

    # test subtest run checkout repeat value unit host
    <$fh>; # skip file head
    my ($test, $sub, $create, $checkout, $unit);
    while (<$fh>) {
	($test, $sub, $create, $checkout, undef, undef, $unit) = split;
	next unless $unit;
	$UNIT ||= $unit;
	next if $run && $run != $create;
	next if $begin && $checkout < $begin;
	next if $end && $end < $checkout;
	$SUBTESTS{"$TESTDESC{$test} $test $sub"} = "$test $sub";
    }
}

sub create_plot_files {
    # sort by description, use test values for gnuplot
    my @tests = map { $SUBTESTS{$_} } sort keys %SUBTESTS;
    @tests = @tests[@numbers] if @numbers;
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
    push @vars, "XRANGE_MIN='$xmin'" if defined $xmin;
    push @vars, "XRANGE_MAX='$xmax'" if defined $xmax;
    push @vars, "YRANGE_MIN='$ymin'" if defined $ymin;
    push @vars, "YRANGE_MAX='$ymax'" if defined $ymax;
    push @vars, "LATEX=1" if $latex;
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
    return if $from > $to;
    my @cmd = ("$performdir/bin/keys.sh", $from, $to);
    print "Command '@cmd' started.\n" if $verbose;
    system(@cmd)
	and die "Command '@cmd' failed: $?";
    print "Command '@cmd' finished.\n" if $verbose;
}

sub create_html_file {
    my @descs = sort keys %SUBTESTS;
    my $htmltitle = uc($plot). " Performance";
    $htmltitle .= ", run $date" if $date;

    my ($html, $htmlfile) = html_open($prefix);
    print $html <<"HEADER";
<!DOCTYPE html>
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
    input[type="checkbox"]:not(:checked) + img {
      display: none;
    }
    body :nth-child(6n) {
      page-break-after: always;
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
    #back {
      position: absolute;
      top: 4px;
      left: 4px;
      z-index: 4;
    }
  </style>
</head>
<body>
HEADER
    my $PLOT = uc($plot);

    print $html <<"TABLE_HEAD";
  <table>
    <tr>
      <th></th>
      <th></th>
      <th>Description</th>
      <th>Command</th>
    </tr>
TABLE_HEAD

    my $i = 1;
    foreach (@descs) {
	my ($desc, $test, $sub) = split;
	(my $testcmd = $test) =~ s/_/ /g;
	print $html <<"TABLE_ROW";
    <tr>
      <td>
	<input id="checkbox-$i" checked type=checkbox>
	<img src="$prefix\_$i.png" alt="$PLOT $desc $sub">
      </td>
      <td>
	<label for="checkbox-$i">
	  <img class="key" src="key_$i.png" alt="Key $i">
	</label>
      </td>
      <td>
	<label for="checkbox-$i">$desc $sub</label>
      </td>
      <td>
	<label for="checkbox-$i"><code>$testcmd</code></label>
      </td>
    </tr>
TABLE_ROW
	$i++;
    }
    print $html <<"END";
  </table>
  <img id="frame" src="$prefix\_0.png" alt="$PLOT Grid">
  <img id="combined" src="$prefix.png" alt="$PLOT Performance">
  <a id="back" href="../perform.html">Back</a>
END

    html_footer($html);
    html_close($html, $htmlfile, "nozip");
}
