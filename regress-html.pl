#!/usr/bin/perl
# convert all test results to a html table

# Copyright (c) 2016-2023 Alexander Bluhm <bluhm@genua.de>
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

my @allregressmodes = qw(src ports release);

my %opts;
getopts('h:lv', \%opts) or do {
    print STDERR <<"EOF";
usage: regress-html.pl [-l] [-h host] regress
    -h host	user and host for version information, user defaults to root
    -l		create latest.html with one column of the latest results
    -v		verbose
    regress	regress mode: @allregressmodes
EOF
    exit(2);
};
my $verbose = $opts{v};
$| = 1 if $verbose;

@ARGV or die "No mode specified";
my %mode;
foreach my $mode (@ARGV) {
    grep { $_ eq $mode } @allregressmodes
	or die "Unknown regress mode '$mode'";
    $mode{$mode} = 1;
}
foreach my $mode (@allregressmodes) {
    die "Regress mode '$mode' must be used solely"
	if $mode{$mode} && keys %mode != 1;
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

my (%T, %D);

# %T
# $test				test directory relative to /usr/src/regress/
# $T{$test}{severity}		weighted severity of all failures of this test
# $date				date and time when test was executed as string
# $T{$test}{$date}{status}	result of this test at that day
# $T{$test}{$date}{message}	test printed a pass duration or failure summary
# $T{$test}{$date}{logfile}	relative path to make.log for hyper link
# %D
# $date				date and time when test was executed as string
# $D{$date}{passrate}		percentage of not skipped tests that passed
# $D{$date}{short}		date without time
# $D{$date}{result}		path to test.result file
# $D{$date}{setup}		relative path to setup.html for hyper link
# $D{$date}{version}		relative path to version.txt for hyper link
# $D{$date}{host}		hostname of the machine running the regress
# $D{$date}{dmesg}		path to dmesg.txt of machine running regress
# $D{$date}{diff}		path to diff.txt custom build kernel cvs diff
# $D{$date}{kernel}		sysctl kernel version string
# $D{$date}{kerntime}		build time in kernel version string
# $D{$date}{location}		user at location of kernel build
# $D{$date}{build}		snapshot or custom build
# $D{$date}{arch}		sysctl hardware machine architecture
# $D{$date}{ncpu}		sysctl hardware ncpu cores

print "glob_result_files" if $verbose;
my @result_files = glob_result_files();
print "\nparse result files" if $verbose;
parse_result_files(@result_files);
print "\nwrite html date file" if $verbose;
write_html_date_file();
print "\n" if $verbose;

exit;

sub write_html_date_file {
    my $file = $opts{l} ? "latest" : "regress";
    $file .= "-$host" if $host;
    my ($html, $htmlfile) = html_open($file);
    my $topic = $host ? ($opts{l} ? "latest $host" : $host) :
	($opts{l} ? "latest" : "all");

    my $typename = $mode{src} ? "Regress" : $mode{ports} ? "Ports" :
	$mode{release} ? "Release" : "";
    my @nav = (
	Top     => "../../test.html",
	All     => (($opts{l} || $host) && -f "regress.html" ?
	    "regress.html" : undef),
	Latest  => (! $opts{l} ? "latest.html" : undef),
	Running => "run.html");
    html_header($html, "OpenBSD $typename Results",
	"OpenBSD ". lc($typename). " $topic test results",
	@nav);

    print $html <<"HEADER";
<table>
  <tr>
    <th>created at</th>
    <td>$now</td>
  </tr>
</table>
HEADER

    print "." if $verbose;
    my @dates = reverse sort keys %D;
    print $html "<table>\n";
    print $html "  <thead>\n";
    print $html "  <tr>\n    <th>pass rate</th>\n";
    foreach my $date (@dates) {
	my $passrate = $D{$date}{passrate};
	my $percent = "";
	$percent = sprintf("%d%%", 100 * $passrate) if defined $passrate;
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
	$link = uri_escape($version, "^A-Za-z0-9\-\._~/")
	    if $build eq "snapshot";
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
    print $html "  </thead>\n  <tbody>\n";

    my $cvsweb = "http://cvsweb.openbsd.org/cgi-bin/cvsweb/";
    $cvsweb .= "src/regress/" if $mode{src};
    $cvsweb .= "ports/" if $mode{ports};
    if ($mode{release}) {
	undef $cvsweb if $mode{release};
	my $i = 1;
	my %release2severity =
	    map { $_ => $i++ }
	    (qw(clean obj build sysmerge dev destdir reldir release chkflist));
	while (my($k, $v) = each %T) {
	    $v->{severity} = $release2severity{$k} || 0;
	}
    }
    my @tests = sort { $T{$b}{severity} <=> $T{$a}{severity} || $a cmp $b }
	keys %T;
    foreach my $test (@tests) {
	print "." if $verbose;
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
    print $html "  </tbody>\n";
    print $html "</table>\n";

    my $type = $mode{src} ? "regress" : $mode{ports} ? "portstest" :
	$mode{release} ? "release" : "";
    html_status_table($html, $type);
    html_footer($html);
    html_close($html, $htmlfile);
}

sub glob_result_files {
    print "." if $verbose;

    if ($opts{l}) {
	my @latest;
	if ($host) {
	    @latest = "latest-$host/test.result";
	    -f $latest[0]
		or die "No latest test.result for $host";
	} else {
	    @latest = glob("latest-*/test.result");
	}
	return sort map { (readlink(dirname($_)) or die
	    "Readlink latest '$_' failed: $!") . "/test.result" } @latest;
    }

    if ($host) {
	return sort grep { -f dirname($_). "/version-$host.txt" }
	    glob("*/test.result");
    } else {
	return sort glob("*/test.result");
    }
}

# fill global hashes %T %D
sub parse_result_files {
    foreach my $result (@_) {
	print "." if $verbose;

	# parse result file
	my ($date, $short) = $result =~ m,(([^/]+)T[^/]+Z)/test.result,
	    or next;
	my $dv = $D{$date} = {
	    short => $short,
	    result => $result,
	};
	$dv->{setup} = "$date/setup.html" if -f "$date/setup.html";
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
	$dv->{passrate} = $pass / $total if $total;

	# parse version file
	foreach my $version (sort glob("$date/version-*.txt")) {
	    $version =~ m,/version-(.+)\.txt$,;
	    my $hostname = $1;

	    next if $dv->{version};
	    $dv->{version} = $version;
	    $dv->{host} ||= $hostname;
	    (my $dmesg = $version) =~ s,/version-,/dmesg-,;
	    $dv->{dmesg} ||= $dmesg if -f $dmesg;
	    (my $diff = $version) =~ s,/version-,/diff-,;
	    $dv->{diff} ||= $diff if -s $diff;

	    %$dv = (parse_version_file($version), %$dv);
	}
	$dv->{build} = ($dv->{location} =~ /^deraadt@\w+.openbsd.org:/) ?
	    "snapshot" : "custom";
    }
}
