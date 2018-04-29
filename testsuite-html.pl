#!/usr/bin/perl
# collect all os-test results and create a html table
# os-test package must be installed

# Copyright (c) 2018 Alexander Bluhm <bluhm@genua.de>
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
    -t publish	directory where the test suite results are created
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

my $testsuite = "os-test";

my $testdir = "$publish/$testsuite";
-d "$testdir/out" || make_path("$testdir/out")
    or die "make path '$testdir/out' failed: $!";
chdir($testdir)
    or die "Chdir to '$testdir' failed: $!";

if ($latest) {
    my $obj = "$resultsdir/$latest/test.obj.tgz";
    my @pax = ("pax", "-zrf", $obj, "-s,^/misc/$testsuite/,,", "-s,.*,,");
    system(@pax)
	and die "Command '@pax' failed: $?";
}

my $outdir = "$testdir/out";
chdir($outdir)
    or die "Chdir to '$outdir' failed: $!";

foreach my $date (values %latesthost) {
    my $obj = "$resultsdir/$date/test.obj.tgz";
    my @pax = ("pax", "-zrf", $obj, "-s,^/misc/$testsuite/,$date/,", "-s,.*,,");
    system(@pax)
	and die "Command '@pax' failed: $?";
}

my @oslist = reverse sort grep { -d } glob("*");
my @suites = qw(io udp);
my @cmd = ("os-test-html", "--enable-suites-overview", "--suite-list=@suites",
    "--os-list=@oslist");

chdir($testdir)
    or die "Chdir to '$testdir' failed: $!";

my $htmlfile = "os-test.html";
unlink("$htmlfile.new");

defined(my $pid = fork())
    or die "fork failed: $!";
if ($pid == 0) {
    open(STDOUT, '>', "$htmlfile.new")
	or die "Redirect '$htmlfile.new' to stdout failed: $!";
    exec { "/usr/local/bin/os-test-html" } @cmd;
    die "Exec '/usr/local/bin/os-test-html' failed: $!";
}
(my $waitpid = wait()) > 1
    or die "wait failed: $!";
$? and die "Command '@cmd' failed: $?";

rename("$htmlfile.new", "$htmlfile")
    or die "Rename '$htmlfile.new' to '$htmlfile' failed: $!";

system("gzip -f -c $htmlfile >$htmlfile.gz.new")
    and die "gzip $htmlfile failed: $?";
rename("$htmlfile.gz.new", "$htmlfile.gz")
    or die "Rename '$htmlfile.new.gz' to '$htmlfile.gz' failed: $!";
