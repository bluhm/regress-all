#!/usr/bin/perl
# collect all os-test and posixtestsuite results and create a html table
# os-test and posixtestsuite package must be installed

# Copyright (c) 2018-2019 Alexander Bluhm <bluhm@genua.de>
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
use File::Path qw(make_path);
use Getopt::Std;

my %opts;
getopts('p:', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 -p publish
    -p publish	directory where the test suite results are created
EOF
    exit(2);
};
my $publish = $opts{p} or die "No -p specified";
$publish = getcwd(). "/". $publish if substr($publish, 0, 1) ne "/";

my $dir = dirname($0). "/..";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";
my $regressdir = getcwd();

my $resultsdir = "$regressdir/results";
chdir($resultsdir)
    or die "Chdir to '$resultsdir' failed: $!";
my $latest = readlink "latest";
my %latesthost;
foreach (glob("latest-*")) {
    my $date = readlink $_ or next;
    -d $date or next;
    my (undef, $host) = split(/-/, $_, 2);
    $latesthost{$host} = $date;
}

my $testdir = "$publish/os-test";
-d "$testdir/out" || make_path("$testdir/out")
    or die "Make path '$testdir/out' failed: $!";
$testdir = "$publish/posixtestsuite";
-d "$testdir/out" || make_path("$testdir/out")
    or die "Make path '$testdir/out' failed: $!";
chdir($publish)
    or die "Chdir to '$publish' failed: $!";

if ($latest) {
    my $obj = "$resultsdir/$latest/test.obj.tgz";
    my @pax = ("pax", "-zrf", $obj,
	"-s,^/misc/os-test/,$publish/os-test/,",
	"-s,^/misc/posixtestsuite/,$publish/posixtestsuite/,",
	"-s,.*,,");
    system(@pax)
	and die "Command '@pax' failed: $?";
}

while (my ($host, $date) = each %latesthost) {
    my $version = "$resultsdir/$date/version-$host.txt";
    open(my $fh, '<', $version)
	or die "Open '$version' for reading failed: $!";
    my ($kernel, $time, $location, $arch);
    while (<$fh>) {
	# OpenBSD 6.3-current (GENERIC.MP) #14: Thu Apr 26 21:03:52 MDT 2018
	if (/^kern.version=(.*: (\w+ \w+ +\d+ .*))$/) {
	    $kernel = $1;
	    $time = $2;
	    <$fh> =~ /(\S+)/;
	    $kernel .= "\n    $1";
	    $location = $1;
	}
	/^hw.machine=(\w+)$/ and $arch = $1;
    }
    # test results with kernel from snapshot build only
    next unless $location =~ /^deraadt@\w+.openbsd.org:/;
    # Thu Apr 26 21:03:52 MDT 2018
    my (undef, $monthname, $day, undef, undef, $year) = split(" ", $time);
    my %mn2m;
    my $i = 0;
    foreach (qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)) {
	$mn2m{$_} = ++$i;
    }
    my $snap = sprintf("%04d-%02d-%02d", $year, $mn2m{$monthname}, $day);

    my $obj = "$resultsdir/$date/test.obj.tgz";
    my @pax = ("pax", "-zrf", $obj,
	"-s,.*\.core\$,,",
	"-s,.*\.c\$,,",
	"-s,.*\.sh\$,,",
	"-s,^/misc/os-test/,$publish/os-test/out/$snap-$host/,",
	"-s,^/misc/posixtestsuite/,$publish/posixtestsuite/out/$snap-$host/,",
	"-s,.*,,");
    system(@pax)
	and die "Command '@pax' failed: $?";
}

### os-test

my $outdir = "$publish/os-test/out";
chdir($outdir)
    or die "Chdir to '$outdir' failed: $!";

my @oslist = reverse sort grep { -d } glob("*");
my @suites = qw(io udp);
my @cmd = ("os-test-html", "--enable-suites-overview", "--suite-list=@suites",
    "--os-list=@oslist");

$testdir = "$publish/os-test";
chdir($testdir)
    or die "Chdir to '$testdir' failed: $!";

my $htmlfile = "os-test.html";
unlink("$htmlfile.new");

defined(my $pid = fork())
    or die "Fork failed: $!";
if ($pid == 0) {
    open(STDOUT, '>', "$htmlfile.new")
	or die "Redirect '$htmlfile.new' to stdout failed: $!";
    exec { "/usr/local/bin/os-test-html" } @cmd;
    die "Exec '/usr/local/bin/os-test-html' failed: $!";
}
(my $waitpid = wait()) > 1
    or die "Wait failed: $!";
$? and die "Command '@cmd' failed: $?";

rename("$htmlfile.new", "$htmlfile")
    or die "Rename '$htmlfile.new' to '$htmlfile' failed: $!";

system("gzip -f -c $htmlfile >$htmlfile.gz.new")
    and die "Gzip $htmlfile failed: $?";
rename("$htmlfile.gz.new", "$htmlfile.gz")
    or die "Rename '$htmlfile.gz.new' to '$htmlfile.gz' failed: $!";

### posixtestsuite

$outdir = "$publish/posixtestsuite/out";
chdir($outdir)
    or die "Chdir to '$outdir' failed: $!";
@oslist = reverse sort grep { -d } glob("*");
@cmd = ("posixtestsuite-html", "-o", "@oslist");

$testdir = "$publish/posixtestsuite";
chdir($testdir)
    or die "Chdir to '$testdir' failed: $!";

$htmlfile = "posixtestsuite.html";
unlink("$htmlfile.new");

defined($pid = fork())
    or die "Fork failed: $!";
if ($pid == 0) {
    open(STDOUT, '>', "$htmlfile.new")
	or die "Redirect '$htmlfile.new' to stdout failed: $!";
    exec { "/usr/local/bin/posixtestsuite-html" } @cmd;
    die "Exec '/usr/local/bin/posixtestsuite-html' failed: $!";
}
($waitpid = wait()) > 1
    or die "Wait failed: $!";
$? and die "Command '@cmd' failed: $?";

rename("$htmlfile.new", "$htmlfile")
    or die "Rename '$htmlfile.new' to '$htmlfile' failed: $!";

system("gzip -f -c $htmlfile >$htmlfile.gz.new")
    and die "Gzip $htmlfile failed: $?";
rename("$htmlfile.gz.new", "$htmlfile.gz")
    or die "Rename '$htmlfile.gz.new' to '$htmlfile.gz' failed: $!";
