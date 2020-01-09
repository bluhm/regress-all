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
usage: $0 [-l] [-h host]
    -h host	user and host for version information, user defaults to root
    -l		create latest.html with one column of the latest results
EOF
    exit(2);
};

my $dir = dirname($0). "/..";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";
my $regressdir = getcwd();
$dir = "results";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";

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
    @result_files = map { (readlink(dirname($_))
	or die "Readlink latest '$_' failed: $!") . "/test.result" } @latest;
} else {
    @result_files = sort glob("*/test.result");
}

# %T
# $test				test directory relative to /usr/src/regress/
# $T{$test}{severity}		weighted severity of all failures of this test
# $date				date when test was executed as ISO string
# $T{$test}{$date}{status}	result of this test at that day
# $T{$test}{$date}{message}	test printed a pass duration or failure summary
# $T{$test}{$date}{logfile}	relative path to make.log to create link

my (%T, %d);
parse_result_files(@result_files);

my $htmlfile = $opts{l} ? "latest" : "regress";
$htmlfile .= "-$host" if $host;
$htmlfile .= ".html";
unlink("$htmlfile.new");
open(my $html, '>', "$htmlfile.new")
    or die "Open '$htmlfile.new' for writing failed: $!";
my $htmltitle = $opts{l} ? "Latest" : "Test";
my $bodytitle = $host ? ($opts{l} ? "latest $host" : $host) :
    ($opts{l} ? "latest" : "all");

html_header($html, "OpenBSD Regress $htmltitle Results",
    "OpenBSD regress $bodytitle test results");

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

my @dates = reverse sort keys %d;
print $html "<table>\n";
print $html "  <tr>\n    <th>pass rate</th>\n";
foreach my $date (@dates) {
    my $pass = $d{$date}{pass};
    my $percent = "";
    $percent = sprintf("%d%%", 100 * $pass) if defined $pass;
    print $html "    <th>$percent</th>\n";
}
print $html "  <tr>\n    <th>run at date</th>\n";
foreach my $date (@dates) {
    my $short = $d{$date}{short};
    my $setup = $d{$date}{setup};
    my $time = encode_entities($date);
    my $link = uri_escape($setup, "^A-Za-z0-9\-\._~/");
    my $href = $setup ? "<a href=\"$link\">" : "";
    my $enda = $href ? "</a>" : "";
    print $html "    <th title=\"$time\">$href$short$enda</th>\n";
}
print $html "  <tr>\n    <th>machine build</th>\n";
foreach my $date (@dates) {
    my $version = $d{$date}{version};
    unless ($version) {
	print $html "    <th/>\n";
	next;
    }
    my $kernel = encode_entities($d{$date}{kernel});
    my $build = $d{$date}{build};
    my $diff = $d{$date}{diff};
    my $link;
    $link = uri_escape($version, "^A-Za-z0-9\-\._~/") if $build eq "snapshot";
    $link = uri_escape($diff, "^A-Za-z0-9\-\._~/")
	if $build eq "custom" && $diff;
    my $href = $link ? "<a href=\"$link\">" : "";
    my $enda = $href ? "</a>" : "";
    print $html "    <th title=\"$kernel\">$href$build$enda</th>\n";
}
print $html "  <tr>\n    <th>host architecture</th>\n";
foreach my $date (@dates) {
    my $arch = $d{$date}{arch};
    unless ($arch) {
	print $html "    <th/>\n";
	next;
    }
    my $hostname = $d{$date}{host};
    my $hostlink;
    $hostlink = "regress-$hostname.html" if !$host || $opts{l};
    my $hhref = $hostlink ? "<a href=\"$hostlink\">" : "";
    my $henda = $hhref ? "</a>" : "";
    my $dmesg = $d{$date}{dmesg};
    my $alink = uri_escape($dmesg, "^A-Za-z0-9\-\._~/");
    my $ahref = $dmesg ? "<a href=\"$alink\">" : "";
    my $aenda = $ahref ? "</a>" : "";
    print $html "    <th>$hhref$hostname$henda/$ahref$arch$aenda</th>\n";
}
print $html "  </tr>\n";

my $cvsweb = "http://cvsweb.openbsd.org/cgi-bin/cvsweb/src/regress/";
my @tests = sort { $T{$b}{severity} <=> $T{$a}{severity} || $a cmp $b }
    keys %T;
foreach my $test (@tests) {
    print $html "  <tr>\n    <th><a href=\"$cvsweb$test/\">$test</a></th>\n";
    foreach my $date (@dates) {
	my $status = $T{$test}{$date}{status} || "";
	my $class = " class=\"result $status\"";
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

html_table_status($html, "regress");
html_footer($html);

close($html)
    or die "Close '$htmlfile.new' after writing failed: $!";
rename("$htmlfile.new", "$htmlfile")
    or die "Rename '$htmlfile.new' to '$htmlfile' failed: $!";

system("gzip -f -c $htmlfile >$htmlfile.gz.new")
    and die "gzip $htmlfile failed: $?";
rename("$htmlfile.gz.new", "$htmlfile.gz")
    or die "Rename '$htmlfile.new.gz' to '$htmlfile.gz' failed: $!";

exit;

# fill global hashes %T %d
sub parse_result_files {
    foreach my $result (@_) {

	# parse result file
	my ($date, $short) = $result =~ m,((.+)T.+)/test.result,
	    or next;
	$d{$date} = {
	    short => $short,
	    result => $result,
	};
	$d{$date}{setup} = "$date/setup.html" if -f "$date/setup.html";
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
	    my $severity =
		$status eq 'PASS'   ? 1 :
		$status eq 'XFAIL'  ? 2 :
		$status eq 'SKIP'   ? 3 :
		$status eq 'XPASS'  ? 4 :
		$status eq 'FAIL'   ? 5 :
		$status eq 'NOEXIT' ? 6 :
		$status eq 'NOTERM' ? 7 :
		$status eq 'NORUN'  ? 8 : 10;
	    $T{$test}{severity} += $severity;
	    $total++ unless $status eq 'SKIP' || $status eq 'XFAIL';
	    $pass++ if $status eq 'PASS';
	    my $logfile = dirname($result). "/logs/$test/make.log";
	    $T{$test}{$date}{logfile} = $logfile if -f $logfile;
	}
	close($fh)
	    or die "Close '$result' after reading failed: $!";
	$d{$date}{pass} = $pass / $total if $total;

	# parse version file
	if ($host && ! -f "$date/version-$host.txt") {
	    # if host is specified, only print result for this one
	    delete $d{$date};
	    next;
	}
	foreach my $version (sort glob("$date/version-*.txt")) {
	    $version =~ m,/version-(.+)\.txt$,;
	    my $hostname = $1;

	    next if $d{$date}{version};
	    $d{$date}{version} = $version;
	    $d{$date}{host} ||= $hostname;
	    (my $dmesg = $version) =~ s,/version-,/dmesg-,;
	    $d{$date}{dmesg} ||= $dmesg if -f $dmesg;
	    (my $diff = $version) =~ s,/version-,/diff-,;
	    $d{$date}{diff} ||= $diff if -f $diff;

	    open($fh, '<', $version)
		or die "Open '$version' for reading failed: $!";
	    while (<$fh>) {
		if (/^kern.version=(.*: (\w+ \w+ +\d+ .*))$/) {
		    $d{$date}{kernel} = $1;
		    $d{$date}{time} = $2;
		    <$fh> =~ /(\S+)/;
		    $d{$date}{kernel} .= "\n    $1";
		    $d{$date}{location} = $1;
		}
		/^hw.machine=(\w+)$/ and $d{$date}{arch} ||= $1;
		/^hw.ncpu=(\d+)$/ and $d{$date}{core} ||= $1;
	    }
	    $d{$date}{build} =
		$d{$date}{location} =~ /^deraadt@\w+.openbsd.org:/ ?
		"snapshot" : "custom";
	}
    }
}
