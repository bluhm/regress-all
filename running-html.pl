#!/usr/bin/perl -T
# collect all install and running logs into one html table

# Copyright (c) 2016-2021 Alexander Bluhm <bluhm@genua.de>
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
use Date::Parse;
use List::Util qw(uniq);
use POSIX;
use URI::Escape;

use lib dirname(($0 =~ m{^([/\w.-]+)$})[0]);
use Html;

my @now = gmtime();
my $now = strftime("%FT%TZ", @now);

my %opts;
getopts('va', \%opts) or do {
    print STDERR <<"EOF";
usage: running-html.pl [-a] [-d date]
    -a		create running.html for all dates
    -v		verbose
EOF
    exit(2);
};
my $verbose = $opts{v};
$| = 1 if $verbose;
@ARGV and die "No arguments allowed";

my $testdir = dirname(($0 =~ m{^([/\w.-]+)$})[0]). "/../..";
chdir($testdir)
    or die "Change directory to '$testdir' failed: $!";
$testdir = (getcwd() =~ m{^([/\w]+)$})[0];
my $resultdir = "$testdir/results";
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

my (%L, %V);

# %L
# $L{$host}{$type}{log}			log file path
# $L{$host}{$type}{mtime}		modified time of log file
# $L{$host}{$type}{hosts}[]		host names with version files
# $L{$host}{$type}{setup}{$host}	setup log file path
# $L{$host}{mtime}			latest modified time of log files
# %V
# $V{$host}{version}			version text file
# $V{$host}{kerntime}			kernel time from version file
# $V{$host}{arch}			sysctl hardware machine architecture
# $V{$host}{ncpu}			sysctl hardware ncpu cores
# $V{$host}{mtime}			latest modified time of version file

my @types = qw(regress perform portstest release netlink);

print "find latest logs" if $verbose;
foreach my $type (@types) {
    my @logs = glob_log_files($type);
    find_latest_logs($type, @logs);
}
print "\n" if $verbose;

print "create html running" if $verbose;
create_html_running();
print "\n" if $verbose;

exit 0;

sub glob_log_files {
    my ($type) = @_;

    print "." if $verbose;
    my $resultdir = "../$type/results";
    my $mon = $now[4];
    my $year = $now[5] + 1900;
    my $dateglob = $opts{a} ? "*" :
	$mon == 0 ? sprintf("{%04d-%02d,%04d-%02d}-*", $year-1, 12, $year, 1) :
	sprintf("%04d-{%02d,%02d}-*", $year, $mon, $mon+1);
    my %logglob = (
	regress   => "run",
	perform   => "{step,once}",
	portstest => "test",
	release   => "make",
	netlink   => "net",
    );

    my @logs = glob("$resultdir/${dateglob}T*Z/$logglob{$type}.log");
    if ($type eq "perform") {
	push @logs, glob(
	    "$resultdir/[0-9]*.[0-9]/${dateglob}T*Z/$logglob{$type}.log");
    }
    return @logs;
}

sub find_latest_logs {
    my ($type, @logs) = @_;

    print "." if $verbose;
    foreach my $log (@logs) {
	my $dir = dirname($log);
	my @hosts = map { m,/setup-(\w+).log$, } glob("$dir/setup-*.log");
	foreach my $version (glob("$dir/version-*.txt")) {
	    my $mtime = (stat($version))[9]
		or die "Stat '$version' failed: $!";
	    my ($host) = $version =~ m,/version-(\w+).txt$,;
	    push @hosts, $host;
	    next if $V{$host}{mtime} && $V{$host}{mtime} > $mtime;
	    $V{$host} = {
		version => $version,
		mtime => $mtime,
	    };
	}
	@hosts = uniq @hosts;
	next unless @hosts;

	my $mtime = (stat($log))[9]
	    or die "Stat '$log' failed: $!";
	next if $L{$hosts[0]}{$type}{mtime} &&
	    $L{$hosts[0]}{$type}{mtime} > $mtime;
	my ($date) = $log =~ m,/([^/]+T[^/]+Z)/,;
	foreach my $host (@hosts) {
	    $L{$host}{$type} = {
		date  => $date,
		log   => $log,
		mtime => $mtime,
	    };
	    my $setup = "$dir/setup-$host.log";
	    if (-f $setup) {
		if ($host ne $hosts[0]) {
		    delete $L{$host}{$type}{date};
		    $L{$host}{$type}{log} = $setup;
		    $L{$host}{$type}{mtime} = (stat($setup))[9]
			or die "Stat '$setup' failed: $!";
		}
	    }
	    next if $L{$host}{mtime} &&
		$L{$host}{mtime} > $L{$host}{$type}{mtime};
	    $L{$host}{mtime} = $L{$host}{$type}{mtime};
	}
    }
}

sub create_html_running {
    my ($html, $htmlfile) = html_open("running");
    my @nav = (
	Top     => "../test.html",
	Regress => "../regress/results/latest.html",
	Perform => "../perform/results/perform.html",
	Ports   => "../portstest/results/latest.html",
	Release => "../release/results/latest.html",
	Net => "../netlink/results/latest.html",
	Running => undef);
    html_header($html, "OpenBSD Running",
	"OpenBSD test running",
	@nav);
    print $html <<"HEADER";
<table>
  <tr>
    <th>created at</th>
    <td>$now</td>
  </tr>
</table>
HEADER

    print $html "<table>\n";
    print $html "  <thead>\n";
    print $html "  <tr>\n    <th>host</th>\n";
    foreach my $type (@types) {
	my $link = uri_escape("../$type/results/run.html",
	    "^A-Za-z0-9\-\._~/");
	print $html "    <th><a href=\"$link\">$type</a></th>\n";
    }
    print $html "  <th>ended</th>\n";
    foreach my $label (qw(arch ncpu kernel)) {
	print $html "    <th>$label</th>\n";
    }
    print $html "  </tr>\n";
    print $html "  </thead>\n  <tbody>\n";

    my @hosts = sort { $L{$b}{mtime} <=> $L{$a}{mtime} || $a cmp $b } keys %L;
    foreach my $host (@hosts) {
	print "." if $verbose;
	print $html "  <tr>\n    <th>$host</th>\n";
	foreach my $type (@types) {
	    my $tv = $L{$host}{$type};
	    unless ($tv) {
		print $html "    <td></td>\n";
		next;
	    }
	    my $date = $tv->{date};
	    my $label = $date || "setup";
	    my $log = $tv->{log};
	    my $status = log2status($log);
	    my $class = $status ? " class=\"status $status\"" : "";
	    my $link = uri_escape($log, "^A-Za-z0-9\-\._~/");
	    my $href = $log ? "<a href=\"$link\">" : "";
	    my $enda = $href ? "</a>" : "";
	    print $html "    <td$class>$href$label$enda";
	    my $mtime = $tv->{mtime};
	    if ($date) {
		my $start = str2time($date);
		my $duration = $mtime - $start;
		print $html "<br>duration ";
		print $html $duration >= 24*60*60 ?
		    sprintf("%.2f days", $duration / (24*60*60)) :
		    strftime("%T", gmtime($duration));
	    }
	    print $html "</td>\n";
	}
	print $html strftime("    <td>T%TZ</td>\n", gmtime($L{$host}{mtime}));
	if ($V{$host}) {
	    my $version = $V{$host}{version};
	    my %v = parse_version_file($version);
	    print $html map { "    <td>$v{$_}</td>\n" } qw(arch ncpu);
	    my $link = uri_escape($version, "^A-Za-z0-9\-\._~/");
	    my $href = $version ? "<a href=\"$link\">" : "";
	    my $enda = $href ? "</a>" : "";
	    print $html "    <td>$href$v{kerntime}$enda<td>\n";
	} else {
	    print $html "    <td></td><td></td><td></td>\n";
	}
	print $html "  </tr>\n";
    }
    print $html "  </tbody>\n";
    print $html "</table>\n";

    print $html "Each row displays the status of a host.\n";
    print $html "If a row is completely green, the host is unused now.\n";
    print $html "Red means the failure should be examined.\n";
    print $html "If a row has any yellow, wait for the test to finish.\n";
    html_running_table($html);
    html_footer($html);
    html_close($html, $htmlfile, "nozip");
}
