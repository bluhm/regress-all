#!/usr/bin/perl
# convert all test results to a html table

# Copyright (c) 2016-2017 Alexander Bluhm <bluhm@genua.de>
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

my $now = strftime("%FT%TZ", gmtime);

my %opts;
getopts('h:l', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-l] [-h host]
    -h host     optional user and host for version information
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

my @results;
if ($opts{l}) {
    -f "latest/test.result"
	or die "No latest test.result";
    my $date = readlink("latest")
	or die "Readlink 'latest' failed: $!";
    @results = "$date/test.result";
} else {
    @results = sort glob("*/test.result");
}

my ($user, $host) = split('@', $opts{h} || "", 2);
($user, $host) = ("root", $user) unless $host;

my (%t, %d);
foreach my $result (@results) {

    # parse result file
    my ($date, $short) = $result =~ m,((.+)T.+)/test.result,
	or next;
    $d{$date} = {
	short => $short,
	result => $result,
    };
    $d{$date}{setup} = "$date/setup.html" if -f "$date/setup.html";
    $_->{severity} *= .5 foreach values %t;
    my ($total, $pass) = (0, 0);
    open(my $fh, '<', $result)
	or die "Open '$result' for reading failed: $!";
    while (<$fh>) {
	chomp;
	my ($status, $test, $message) = split(" ", $_, 3);
	$t{$test}{$date}
	    and warn "Duplicate test '$test' at date '$date'";
	$t{$test}{$date} = {
	    status => $status,
	    message => $message,
	};
	my $severity =
	    $status eq 'PASS'   ? 1 :
	    $status eq 'SKIP'   ? 2 :
	    $status eq 'FAIL'   ? 3 :
	    $status eq 'NOEXIT' ? 4 :
	    $status eq 'NOTERM' ? 5 :
	    $status eq 'NORUN'  ? 6 : 7;
	$t{$test}{severity} += $severity;
	$total++ unless $status eq 'SKIP';
	$pass++ if $status eq 'PASS';
	my $logfile = dirname($result). "/logs/$test/make.log";
	$t{$test}{$date}{logfile} = $logfile if -f $logfile;
    }
    close($fh)
	or die "Close '$result' after reading failed: $!";
    $d{$date}{pass} = $pass / $total if $total;

    # parse version file
    my ($version, $diff, $dmesg);
    if ($host) {
	$version = "$date/version-$host.txt";
	$diff = "$date/diff-$host.txt";
	$dmesg = "$date/dmesg-$host.txt";
    } else {
	$version = (glob("$date/version-*.txt"))[0];
	($diff = $version) =~ s,/version-,/diff-,;
	($dmesg = $version) =~ s,/version-,/dmesg-,;
    }
    unless (-f $version) {
	# if host is specified, only print result for this one
	delete $d{$date} if $host;
	next;
    }
    $d{$date}{version} = $version;
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
	/^hw.machine=(\w+)$/ and $d{$date}{arch} = $1;
    }
    $d{$date}{build} = $d{$date}{location} =~ /^deraadt@\w+.openbsd.org:/ ?
	"snapshot" : "custom";
    $d{$date}{diff} = $diff if -f $diff;
    $d{$date}{dmesg} = $dmesg if -f $dmesg;
}

my $htmlfile = $opts{l} ? "latest.html" : "regress.html";
unlink("$htmlfile.new");
open(my $html, '>', "$htmlfile.new")
    or die "Open '$htmlfile.new' for writing failed: $!";
print $html "<!DOCTYPE html>\n";
print $html "<html>\n";
print $html "<head>\n";
my $htmltitle = $opts{l} ? "Latest" : "Test";
print $html "  <title>OpenBSD Regress $htmltitle Results</title>\n";
print $html "  <style>\n";
print $html "    th { text-align: left; white-space: nowrap; }\n";
print $html "    tr:hover {background-color: #e0e0e0}\n";
print $html "    td.PASS {background-color: #80ff80;}\n";
print $html "    td.FAIL {background-color: #ff8080;}\n";
print $html "    td.SKIP {background-color: #8080ff;}\n";
print $html "    td.NOEXIT, td.NOTERM, td.NORUN ".
    "{background-color: #ffff80;}\n";
print $html "    td.NOLOG, td.NOCLEAN, td.NOEXIST ".
    "{background-color: #ffffff;}\n";
print $html "    td.result, td.result a {color: black;}\n";
print $html "  </style>\n";
print $html "</head>\n";

print $html "<body>\n";
my $bodytitle = $opts{l} ? "latest" : "all";
print $html "<h1>OpenBSD regress $bodytitle test results</h1>\n";
print $html "<table>\n";
print $html "  <tr>\n    <th>created at</th>\n";
print $html "    <td>$now</td>\n";
print $html "  </tr>\n";
print $html "  <tr>\n    <th>test</th>\n";
print $html "    <td><a href=\"run.html\">run</a></td>\n";
print $html "  </tr>\n";
print $html "</table>\n";
my @dates = reverse sort keys %d;
print $html "<table>\n";
print $html "  <tr>\n    <th>pass rate</th>\n";
foreach my $date (@dates) {
    my $pass = $d{$date}{pass};
    my $percent = "";
    $percent = sprintf("%d%%", 100 * $pass) if defined $pass;
    print $html "    <th>$percent</th>\n";
}
print $html "  <tr>\n    <th>test at date</th>\n";
foreach my $date (@dates) {
    my $short = $d{$date}{short};
    my $setup = $d{$date}{setup};
    $setup = join("/", map { uri_escape($_) } split("/", $setup)) if $setup;
    my $time = encode_entities($date);
    my $href = $setup ? "<a href=\"$setup\">" : "";
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
    $version = join("/", map { uri_escape($_) } split("/", $version));
    my $diff = join("/", map { uri_escape($_) }
	split("/", $d{$date}{diff} || ""));
    my $href = "";
    $href = "<a href=\"$version\">" if $build eq "snapshot";
    $href = "<a href=\"$diff\">" if $build eq "custom" && $diff;
    my $enda = $href ? "</a>" : "";
    print $html "    <th title=\"$kernel\">$href$build$enda</th>\n";
}
print $html "  <tr>\n    <th>architecture</th>\n";
foreach my $date (@dates) {
    my $arch = $d{$date}{arch};
    unless ($arch) {
	print $html "    <th/>\n";
    }
    my $dmesg = join("/", map { uri_escape($_) }
	split("/", $d{$date}{dmesg} || ""));
    my $href = $dmesg ? "<a href=\"$dmesg\">" : "";
    my $enda = $href ? "</a>" : "";
    print $html "    <th>$href$arch$enda</th>\n";
}
print $html "  </tr>\n";

my $cvsweb = "http://cvsweb.openbsd.org/cgi-bin/cvsweb/src/regress/";
my @tests = sort { $t{$b}{severity} <=> $t{$a}{severity} || $a cmp $b }
    keys %t;
foreach my $test (@tests) {
    print $html "  <tr>\n    <th><a href=\"$cvsweb$test/\">$test</a></th>\n";
    foreach my $date (@dates) {
	my $status = $t{$test}{$date}{status} || "";
	my $class = " class=\"result $status\"";
	my $message = encode_entities($t{$test}{$date}{message});
	my $title = $message ? " title=\"$message\"" : "";
	my $logfile = uri_escape($t{$test}{$date}{logfile});
	my $href = $logfile ? "<a href=\"$logfile\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html "    <td$class$title>$href$status$enda</td>\n";
    }
    print $html "  </tr>\n";
}
print $html "</table>\n";
print $html "<table>\n";
print $html "  <tr>\n    <th>PASS</th>\n";
print $html "    <td>make regress passed</td>\n  </tr>\n";
print $html "  <tr>\n    <th>FAIL</th>\n";
print $html "    <td>make regress failed, ";
print $html "string FAILED in test output</td>\n  </tr>\n";
print $html "  <tr>\n    <th>SKIP</th>\n";
print $html "    <td>make regress skipped itself, ";
print $html "string SKIPPED in test output</td>\n  </tr>\n";
print $html "  <tr>\n    <th>NOEXIT</th>\n";
print $html "    <td>make regress did not exit with code 0, ";
print $html "make failed</td>\n  </tr>\n";
print $html "  <tr>\n    <th>NOTERM</th>\n";
print $html "    <td>make regress did not terminate, ";
print $html "aborted after timeout</td>\n  </tr>\n";
print $html "  <tr>\n    <th>NORUN</th>\n";
print $html "    <td>make regress did not run, ";
print $html "execute make failed</td>\n  </tr>\n";
print $html "  <tr>\n    <th>NOLOG</th>\n";
print $html "    <td>create log file for make output failed</td>\n  </tr>\n";
print $html "  <tr>\n    <th>NOCLEAN</th>\n";
print $html "    <td>make clean before running test failed</td>\n  </tr>\n";
print $html "  <tr>\n    <th>NOEXIST</th>\n";
print $html "    <td>test directory not found</td>\n  </tr>\n";
print $html "</table>\n";
print $html "</body>\n";

print $html "</html>\n";
close($html)
    or die "Close '$htmlfile.new' after writing failed: $!";
rename("$htmlfile.new", "$htmlfile")
    or die "Rename '$htmlfile.new' to '$htmlfile' failed: $!";

system("gzip -f -c $htmlfile >$htmlfile.gz.new")
    and die "gzip $htmlfile failed: $?";
rename("$htmlfile.gz.new", "$htmlfile.gz")
    or die "Rename '$htmlfile.new.gz' to '$htmlfile.gz' failed: $!";
