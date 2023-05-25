#!/usr/bin/perl
# collect all os-test and posixtestsuite results and create a html table
# os-test and posixtestsuite package must be installed

# Copyright (c) 2018-2023 Alexander Bluhm <bluhm@genua.de>
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

my @allsuitemodes = qw(os-test posixtestsuite);

my %opts;
getopts('h:p:v', \%opts) or do {
    print STDERR <<"EOF";
usage: testsuite-html.pl [-h host] -p publish [suite ...]
    -h host	user and host for version information, user defaults to root
    -p publish	directory where the test suite results are created
    -v		verbose
    suite ...	test suite: @allsuitemodes
EOF
    exit(2);
};
my $verbose = $opts{v};
$| = 1 if $verbose;
my $publish = $opts{p} or die "No -p specified";
$publish = getcwd(). "/". $publish if substr($publish, 0, 1) ne "/";

@ARGV or @ARGV = @allsuitemodes;

my %mode;
foreach my $mode (@ARGV) {
    grep { $_ eq $mode } @allsuitemodes
	or die "Unknown suite mode '$mode'";
    $mode{$mode} = 1;
}

my $regressdir = dirname($0). "/..";
chdir($regressdir)
    or die "Change directory to '$regressdir' failed: $!";
$regressdir = getcwd();
my $resultdir = "$regressdir/results";
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

my ($user, $host);
if ($opts{h}) {
    ($user, $host) = split('@', $opts{h} || "", 2);
    ($user, $host) = ("root", $user) unless $host;
}

print "glob obj files" if $verbose;
my @obj_files = glob_obj_files($host);
print "\nextract result files" if $verbose;
extract_result_files(@obj_files);
if ($mode{'os-test'}) {
    print "\nwrite html os-test file" if $verbose;
    write_html_ostest_file();
}
if ($mode{posixtestsuite}) {
    print "\nwrite html posixtestsuite file" if $verbose;
    write_html_posixtestsuite_file();
}
print "\n" if $verbose;

exit;

sub glob_obj_files {
    my ($host) = @_;
    $host ||= "*";
    my @obj;
    foreach (glob("latest-$host")) {
	print "." if $verbose;

	my $date = readlink or next;
	-d $date or next;
	my $obj = "$date/test.obj.tgz";
	-f $obj or next;
	push @obj, $obj;
    }
    return @obj;
}

sub extract_result_files {
    my $testdir = "$publish/os-test";
    -d "$testdir/out" || make_path("$testdir/out")
	or die "Make path '$testdir/out' failed: $!";
    $testdir = "$publish/posixtestsuite";
    -d "$testdir/out" || make_path("$testdir/out")
	or die "Make path '$testdir/out' failed: $!";
    chdir($publish)
	or die "Change directory to '$publish' failed: $!";

    foreach my $obj (@_) {
	print "." if $verbose;

	# parse obj file
	my ($date, $short) = $obj =~ m,(([^/]+)T[^/]+Z)/test.obj.tgz,
	    or next;
	my $version = (sort glob("$resultdir/$date/version-*.txt"))[0]
	    or die "No version file for date '$date'";
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
	my $out = "out/$snap-$host";

	my @pax = ("pax", "-zrf", "$resultdir/$obj",
	    "-s,.*\.core\$,,",
	    "-s,.*\.c\$,,",
	    "-s,.*\.sh\$,,");
	push @pax, "-s,^misc/os-test/,$publish/os-test/$out/,"
	    if $mode{'os-test'};
	push @pax, "-s,^misc/posixtestsuite/,$publish/posixtestsuite/$out/,",
	    if $mode{posixtestsuite};
	push @pax, "-s,.*,,";
	system(@pax)
	    and die "Command '@pax' failed: $?";
    }
}

sub write_html_ostest_file {
    my $outdir = "$publish/os-test/out";
    chdir($outdir)
	or die "Change directory to '$outdir' failed: $!";
    my @oslist = reverse sort grep { -d } glob("*");
    my @suites = qw(io udp);
    my @cmd = ("os-test-html", "--enable-suites-overview",
	"--suite-list=@suites", "--os-list=@oslist");

    my $testdir = "$publish/os-test";
    chdir($testdir)
	or die "Change directory to '$testdir' failed: $!";

    my $htmlfile = "os-test.html";
    unlink("$htmlfile.new");

    print "." if $verbose;
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

    print "." if $verbose;
    system("gzip -f -c $htmlfile >$htmlfile.gz.new")
	and die "Gzip '$htmlfile' failed: $?";
    rename("$htmlfile.gz.new", "$htmlfile.gz")
	or die "Rename '$htmlfile.gz.new' to '$htmlfile.gz' failed: $!";
}

sub write_html_posixtestsuite_file {
    my $outdir = "$publish/posixtestsuite/out";
    chdir($outdir)
	or die "Change directory to '$outdir' failed: $!";
    my @oslist = reverse sort grep { -d } glob("*");
    my @cmd = ("posixtestsuite-html", "-o", "@oslist");

    my $testdir = "$publish/posixtestsuite";
    chdir($testdir)
	or die "Change directory to '$testdir' failed: $!";

    my $htmlfile = "posixtestsuite.html";
    unlink("$htmlfile.new");

    print "." if $verbose;
    defined(my $pid = fork())
	or die "Fork failed: $!";
    if ($pid == 0) {
	open(STDOUT, '>', "$htmlfile.new")
	    or die "Redirect '$htmlfile.new' to stdout failed: $!";
	exec { "/usr/local/bin/posixtestsuite-html" } @cmd;
	die "Exec '/usr/local/bin/posixtestsuite-html' failed: $!";
    }
    (my $waitpid = wait()) > 1
	or die "Wait failed: $!";
    $? and die "Command '@cmd' failed: $?";

    rename("$htmlfile.new", "$htmlfile")
	or die "Rename '$htmlfile.new' to '$htmlfile' failed: $!";

    print "." if $verbose;
    system("gzip -f -c $htmlfile >$htmlfile.gz.new")
	and die "Gzip '$htmlfile' failed: $?";
    rename("$htmlfile.gz.new", "$htmlfile.gz")
	or die "Rename '$htmlfile.gz.new' to '$htmlfile.gz' failed: $!";
}
