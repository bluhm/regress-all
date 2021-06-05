#!/usr/bin/perl
# convert all test results to a html table

# Copyright (c) 2016-2019 Alexander Bluhm <bluhm@genua.de>
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
use HTML::Entities;
use Getopt::Std;
use POSIX;
use URI::Escape;

use lib dirname($0);
use Html;

my $now = strftime("%FT%TZ", gmtime);

my %opts;
getopts('h:l', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-l] [-h host] mode
    -h host	user and host for version information, user defaults to root
    -l		create latest.html with one column of the latest results
    mode	src ports release
EOF
    exit(2);
};

my %allmodes;
@allmodes{qw(src ports release)} = ();
@ARGV or die "No mode specified";
my %mode = map {
    die "Unknown mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV;
foreach (qw(src ports release)) {
    die "Mode must be used solely: $_" if $mode{$_} && keys %mode != 1;
}

my $regressdir = dirname($0). "/..";
chdir($regressdir)
    or die "Change directory to '$regressdir' failed: $!";
$regressdir = getcwd();
my $resultdir = "$regressdir/results";
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

my ($user, $host) = split('@', $opts{h} || "", 2);
($user, $host) = ("root", $user) unless $host;

my @result_files;
if ($opts{l}) {
    my @latest;
    if ($host) {
	@latest = "latest-$host/test.result";
	-f $latest[0]
	    or die "No latest test.result for $host";
    } else {
	@latest = glob("latest-*/test.result");
    }
    @result_files = sort map { (readlink(dirname($_))
	or die "Readlink latest '$_' failed: $!") . "/test.result" } @latest;
} elsif ($host) {
    @result_files = sort grep { -f dirname($_). "/version-$host.txt" }
	glob("*/test.result");
} else {
    @result_files = sort glob("*/test.result");
}

# %T
# $test				test directory relative to /usr/src/regress/
# $T{$test}{severity}		weighted severity of all failures of this test
# $date				date and time when test was executed as string
# $T{$test}{$date}{status}	result of this test at that day
# $T{$test}{$date}{message}	test printed a pass duration or failure summary
# $T{$test}{$date}{logfile}	relative path to make.log for hyper link
# %D
# $date				date and time when test was executed as string
# $D{$date}{pass}		percentage of not skipped tests that passed
# $D{$date}{short}		date without time
# $D{$date}{result}		path to test.result file
# $D{$date}{setup}		relative path to setup.html for hyper link
# $D{$date}{version}		relative path to version.txt for hyper link
# $D{$date}{host}		hostname of the machine running the regress
# $D{$date}{dmesg}		path to dmesg.txt of machine running regress
# $D{$date}{diff}		path to diff.txt custom build kernel cvs diff
# $D{$date}{kernel}		sysctl kernel version string
# $D{$date}{time}		build time in kernel version string
# $D{$date}{location}		user at location of kernel build
# $D{$date}{build}		snapshot or custom build
# $D{$date}{arch}		sysctl hardware machine architecture
# $D{$date}{core}		sysctl hardware ncpu cores

my (%T, %D);
parse_result_files(@result_files);

my $file = $opts{l} ? "latest" : "regress";
$file .= "-$host" if $host;
my ($html, $htmlfile) = html_open($file);
my $topic = $host ? ($opts{l} ? "latest $host" : $host) :
    ($opts{l} ? "latest" : "all");

my $typename = $mode{src} ? "Regress" : $mode{ports} ? "Ports" :
    $mode{release} ? "Release" : "";
my @nav = (Top => "../../test.html");
push @nav, (All => "regress.html") if $opts{l} || $host;
push @nav, (Latest => "latest.html") if ! $opts{l};
html_header($html, "OpenBSD $typename Results",
    "OpenBSD ". lc($typename). " $topic test results",
    @nav);

print $html <<"HEADER";
<table>
  <tr>
    <th>created at</th>
    <td>$now</td>
  </tr>
  <tr>
    <th>test</th>
    <td><a href=\"run.html\">run info</a></td>
</tr>
</table>
HEADER

my @dates = reverse sort keys %D;
print $html "<table>\n";
print $html "  <tr>\n    <th>pass rate</th>\n";
foreach my $date (@dates) {
    my $pass = $D{$date}{pass};
    my $percent = "";
    $percent = sprintf("%d%%", 100 * $pass) if defined $pass;
    print $html "    <th>$percent</th>\n";
}
print $html "  <tr>\n    <th>run at date</th>\n";
foreach my $date (@dates) {
    my $short = $D{$date}{short};
    my $setup = $D{$date}{setup};
    my $time = encode_entities($date);
    my $link = uri_escape($setup, "^A-Za-z0-9\-\._~/");
    my $href = $setup ? "<a href=\"$link\">" : "";
    my $enda = $href ? "</a>" : "";
    print $html "    <th title=\"$time\">$href$short$enda</th>\n";
}
print $html "  <tr>\n    <th>machine build</th>\n";
foreach my $date (@dates) {
    my $version = $D{$date}{version};
    unless ($version) {
	print $html "    <th></th>\n";
	next;
    }
    my $kernel = encode_entities($D{$date}{kernel});
    my $build = $D{$date}{build};
    my $diff = $D{$date}{diff};
    my $link;
    $link = uri_escape($version, "^A-Za-z0-9\-\._~/") if $build eq "snapshot";
    $link = uri_escape($diff, "^A-Za-z0-9\-\._~/")
	if $build eq "custom" && $diff;
    my $href = $link ? "<a href=\"$link\">" : "";
    my $enda = $href ? "</a>" : "";
    print $html "    <th title=\"$kernel\">$href$build$enda</th>\n";
}
print $html "  <tr>\n    <th>architecture</th>\n";
foreach my $date (@dates) {
    my $arch = $D{$date}{arch};
    my $dmesg = $D{$date}{dmesg};
    my $link = uri_escape($dmesg, "^A-Za-z0-9\-\._~/");
    my $href = $dmesg ? "<a href=\"$link\">" : "";
    my $enda = $href ? "</a>" : "";
    print $html "    <th>$href$arch$enda</th>\n";
}
print $html "  <tr>\n    <th>host</th>\n";
foreach my $date (@dates) {
    my $hostname = $D{$date}{host};
    my $hostlink;
    if (!$host || $opts{l}) {
	$hostlink = "regress-$hostname.html";
	undef $hostlink unless -f $hostlink;
    }
    my $href = $hostlink ? "<a href=\"$hostlink\">" : "";
    my $enda = $href ? "</a>" : "";
    print $html "    <th>$href$hostname$enda</th>\n";
}
print $html "  </tr>\n";

my $cvsweb = "http://cvsweb.openbsd.org/cgi-bin/cvsweb/";
$cvsweb .= "src/regress/" if $mode{src};
$cvsweb .= "ports/" if $mode{ports};
undef $cvsweb if $mode{release};
my @tests = sort { $T{$b}{severity} <=> $T{$a}{severity} || $a cmp $b }
    keys %T;
foreach my $test (@tests) {
    my $href = $cvsweb ? "<a href=\"$cvsweb$test\">" : "";
    my $enda = $href ? "</a>" : "";
    print $html "  <tr>\n    <th>$href$test$enda</th>\n";
    foreach my $date (@dates) {
	my $status = $T{$test}{$date}{status} || "";
	my $class = " class=\"status $status\"";
	my $message = encode_entities($T{$test}{$date}{message});
	my $title = $message ? " title=\"$message\"" : "";
	my $logfile = $T{$test}{$date}{logfile};
	my $link = uri_escape($logfile, "^A-Za-z0-9\-\._~/");
	my $href = $logfile ? "<a href=\"$link\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html "    <td$class$title>$href$status$enda</td>\n";
    }
    print $html "  </tr>\n";
}
print $html "</table>\n";

my $type = $mode{src} ? "regress" : $mode{ports} ? "portstest" :
    $mode{release} ? "release" : "";
html_status_table($html, $type);
html_footer($html);
html_close($html, $htmlfile);

exit;

# fill global hashes %T %D
sub parse_result_files {
    foreach my $result (@_) {

	# parse result file
	my ($date, $short) = $result =~ m,((.+)T.+)/test.result,
	    or next;
	$D{$date} = {
	    short => $short,
	    result => $result,
	};
	$D{$date}{setup} = "$date/setup.html" if -f "$date/setup.html";
	$_->{severity} *= .5 foreach values %T;
	my ($total, $pass) = (0, 0);
	open(my $fh, '<', $result)
	    or die "Open '$result' for reading failed: $!";
	while (<$fh>) {
	    chomp;
	    my ($status, $test, $message) = split(" ", $_, 3);
	    $T{$test}{$date}
		and warn "Duplicate test '$test' at date '$date'";
	    $T{$test}{$date} = {
		status => $status,
		message => $message,
	    };
	    my $severity = status2severity($status);
	    $T{$test}{severity} += $severity;
	    $total++ unless $status eq 'SKIP' || $status eq 'XFAIL';
	    $pass++ if $status eq 'PASS';
	    my $logfile = dirname($result). "/logs/$test/make.log";
	    $T{$test}{$date}{logfile} = $logfile if -f $logfile;
	}
	close($fh)
	    or die "Close '$result' after reading failed: $!";
	$D{$date}{pass} = $pass / $total if $total;

	# parse version file
	foreach my $version (sort glob("$date/version-*.txt")) {
	    $version =~ m,/version-(.+)\.txt$,;
	    my $hostname = $1;

	    next if $D{$date}{version};
	    $D{$date}{version} = $version;
	    $D{$date}{host} ||= $hostname;
	    (my $dmesg = $version) =~ s,/version-,/dmesg-,;
	    $D{$date}{dmesg} ||= $dmesg if -f $dmesg;
	    (my $diff = $version) =~ s,/version-,/diff-,;
	    $D{$date}{diff} ||= $diff if -f $diff;

	    open($fh, '<', $version)
		or die "Open '$version' for reading failed: $!";
	    while (<$fh>) {
		if (/^kern.version=(.*: (\w+ \w+ +\d+ .*))$/) {
		    $D{$date}{kernel} = $1;
		    $D{$date}{time} = $2;
		    <$fh> =~ /(\S+)/;
		    $D{$date}{kernel} .= "\n    $1";
		    $D{$date}{location} = $1;
		}
		/^hw.machine=(\w+)$/ and $D{$date}{arch} ||= $1;
		/^hw.ncpu=(\d+)$/ and $D{$date}{core} ||= $1;
	    }
	    $D{$date}{build} =
		$D{$date}{location} =~ /^deraadt@\w+.openbsd.org:/ ?
		"snapshot" : "custom";
	}
    }
}
