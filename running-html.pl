#!/usr/bin/perl
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
use Fcntl qw(SEEK_SET SEEK_CUR SEEK_END);
use File::Basename;
use HTML::Entities;
use Getopt::Std;
use Date::Parse;
use POSIX;
use URI::Escape;

use lib dirname($0);
use Html;

my @now = gmtime();
my $now = strftime("%FT%TZ", @now);

my %opts;
getopts('va', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-a] [-d date]
    -a		create running.html for all dates
    -v          verbose
EOF
    exit(2);
};
my $verbose = $opts{v};
$| = 1 if $verbose;

my $testdir = dirname($0). "/../..";
chdir($testdir)
    or die "Change directory to '$testdir' failed: $!";
$testdir = getcwd();
my $resultdir = "$testdir/results";
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

my %H;

# $H{$host}{$type}{log}			log file path
# $H{$host}{$type}{mtime}		modified time of log file
# $H{$host}{$type}{hosts}[]		host names with version files
# $H{$host}{$type}{setup}{$host}	setup log file path
# $H{$host}{{mtime}			latest modified time of log files

my @types = qw(regress perform portstest release);

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
	my $mtime = (stat($log))[9]
	    or die "stat '$log' failed: $!";
	my $dir = dirname($log);
	my @hosts = map { m,/version-(\w+).txt$, }
	    glob("$dir/version-*.txt");
	next unless @hosts;
	my $tv = $H{$hosts[0]}{$type};
	next if $tv->{mtime} && $tv->{mtime} > $mtime;
	my ($date) = $log =~ m,/([^/]+T[^/]+Z)/,;
	my %setup;
	foreach my $host (@hosts) {
	    my $setup = "$dir/setup-$host.txt";
	    $setup{$host} = $setup if -f $setup;
	    $H{$host}{$type} = {
		date  => $date,
		log   => $log,
		mtime => $mtime,
		hosts => \@hosts,
		setup => \%setup,
	    };
	    next if $H{$host}{mtime} && $H{$host}{mtime} > $mtime;
	    $H{$host}{mtime} = $mtime;
	}
    }
}

sub create_html_running {
    my ($html, $htmlfile) = html_open("running");
    my @nav = (
	Top     => "../test.html",
	Regess  => "../regress/results/run.html",
	Perform => "../perform/results/run.html",
	Ports   => "../portstest/results/run.html",
	Release => "../release/results/run.html",
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
    print $html "  <tr>\n    <th></th>\n";
    foreach my $type (@types) {
	print $html "    <th>$type</th>\n";
    }
    print $html "  </tr>\n";

    my @hosts = sort { $H{$b}{mtime} <=> $H{$a}{mtime} || $a cmp $b } keys %H;
    foreach my $host (@hosts) {
	print "." if $verbose;
	print $html "  <tr>\n    <th>$host</th>\n";
	foreach my $type (@types) {
	    my $tv = $H{$host}{$type};
	    unless ($tv) {
		print $html "    <td></td>\n";
		next;
	    }
	    my $date = $tv->{date};
	    my $log = $tv->{log};
	    my $status = $tv->{status} ||= log_status($log);
	    my $class = $status ? " class=\"status $status\"" : "";
	    my $link = uri_escape($log, "^A-Za-z0-9\-\._~/");
	    my $href = $log ? "<a href=\"$link\">" : "";
	    my $enda = $href ? "</a>" : "";
	    print $html "    <td$class>$href$date$enda";
	    my $mtime = $tv->{mtime};
	    my $start = str2time($date);
	    my $duration = $mtime - $start;
	    print $html "<br>duration ";
	    print $html $duration >= 24*60*60 ?
		($duration / 24*60*60). " days" :
		strftime("%T", gmtime($duration));
	    print $html "</td>\n";
	}
	print $html "  </tr>\n";
    }

    print $html "</table>\n";
    html_footer($html);
    html_close($html, $htmlfile, "nozip");
}

# extract status from log file
sub log_status {
    my ($logfile) = @_;

    open(my $fh, '<', $logfile)
	or return 'NOEXIST';

    defined(my $line = <$fh>)
	or return 'NOLOG';
    $line =~ /^Script .* started/i
	or return 'NORUN';

    # if seek from end fails, file is too short, then read from the beginning
    seek($fh, 0, SEEK_SET);
    seek($fh, -1000, SEEK_END);
    # reread file buffer at current position, ignore error or end of file
    readline($fh);
    # find final line
    while (<$fh>) {
	$line = $_;
    }

    $line =~ /^Warning:/
	and return 'NOTERM';
    $line =~ /^[A-Z].* failed/
	and return 'FAIL';
    $line =~ /^Script .* finished/i
	and return 'PASS';
    return 'NOEXIT';
}
__END__

    @reldates =
	map { dirname($_) } (
	bsd_glob("[0-9]*.[0-9]/*T*/step.log", GLOB_NOSORT));
    $date = $reldates[-1];
    if (!$opts{a}) {
	# run times older than two weeks are irrelevant
	@dates =
	    grep { str2time($now) - str2time($_) <= 60*60*24*14 }
	    splice(@dates);
	@reldates =
	    grep { str2time($now) - str2time(basename($_)) <= 60*60*24*14 }
	    splice(@reldates);
	# keep at least the newest date
	@dates = $date unless @dates || @reldates;
    }
    if (@reldates) {
	@reldates = sort { basename($a) cmp basename($b) } (
	    splice(@dates), splice(@reldates));
    } else {
	@reldates = splice(@dates);
    }
}

my (%D, %M, %H);
foreach my $reldate (@reldates) {
    $date = basename($reldate);
    $D{$date}{reldate} = $reldate;
    my $dir = "$regressdir/results/$reldate";
    chdir($dir)
	or die "Change directory to '$dir' failed: $!";

    my @cvsdates = grep { -d $_ } (
	bsd_glob("*T*", GLOB_NOSORT),
	bsd_glob("patch-*", GLOB_NOSORT));
    $D{$date}{cvsdates} = [ @cvsdates ];

    foreach my $cvsdate ("", @cvsdates) {
	chdir("$dir/$cvsdate")
	    or die "Change directory to '$dir/$cvsdate' failed: $!";

	my @repeats = grep { -d $_ } (
	    bsd_glob("[0-9][0-9][0-9]", GLOB_NOSORT),
	    bsd_glob("btrace-*", GLOB_NOSORT));
	$D{$date}{$cvsdate}{repeats} = [ @repeats ] if $cvsdate;

	foreach my $repeat ("", @repeats) {
	    chdir("$dir/$cvsdate/$repeat")
		or die "Change directory to '$dir/$cvsdate/$repeat' failed: $!";

	    my %h;
	    foreach my $version (glob("version-*.txt")) {
		my ($host) = $version =~ m,version-(.*)\.txt,;
		open(my $fh, '<', $version)
		    or die "Open '$version' for reading failed: $!";
		my ($time, $short, $arch);
		while (<$fh>) {
		    /^kern.version=.*: ((\w+ \w+ +\d+) .*)$/ and
			($time, $short) = ($1, $2);
		    /^hw.machine=(\w+)$/ and $arch = $1;
		}
		$time or next;
		(my $bsdcons = $version) =~ s,version,bsdcons,;
		(my $dmesg = $version) =~ s,version,dmesg,;
		(my $dmesgboot = $version) =~ s,version,dmesg-boot,;
		(my $diff = $version) =~ s,version,diff,;
		(my $quirks = $version) =~ s,version,quirks,;
		(my $nmbsd = $version) =~ s,version,nm-bsd,;
		my $subdir = "";
		$subdir .= "$cvsdate/" if $cvsdate;
		$subdir .= "$repeat/" if $repeat;
		$h{$host} = {
		    version   => $subdir.$version,
		    time      => $time,
		    short     => $short,
		    arch      => $arch,
		    bsdcons   => -f $bsdcons ? $subdir.$bsdcons : undef,
		    dmesg     => -f $dmesg ? $subdir.$dmesg : undef,
		    dmesgboot => -f $dmesgboot ? $subdir.$dmesgboot : undef,
		    diff      => -f $diff ? $subdir.$diff : undef,
		    quirks    => -f $quirks ? $subdir.$quirks : undef,
		    nmbsd     => -f $nmbsd ? $subdir.$nmbsd : undef,
		};
		$M{$host}++;
	    }
	    foreach my $setup (glob("setup-*.log")) {
		my ($host) = $setup =~ m,setup-(.*)\.log,;
		$h{$host}{setup} = $setup,
	    }
	    foreach my $build (glob("cvsbuild-*.log")) {
		my ($host) = $build =~ m,cvsbuild-(.*)\.log,;
		$h{$host}{build} = "$cvsdate/$build",
	    }
	    foreach my $reboot (glob("reboot-*.log")) {
		my ($host) = $reboot =~ m,reboot-(.*)\.log,;
		$h{$host}{reboot} = "$cvsdate/$repeat/$reboot",
	    }
	    if ($repeat) {
		$D{$date}{$cvsdate}{$repeat}{host} = \%h;
	    } elsif ($cvsdate) {
		$D{$date}{$cvsdate}{host} = \%h;
	    } else {
		$D{$date}{host} = \%h;
	    }
	}
    }
    chdir($dir)
	or die "Change directory to '$dir' failed: $!";

    if (-f "run.log") {
	$D{$date}{log} = "run.log";
	$typename = "Regress";
    } elsif (-f "step.log") {
	$D{$date}{log} = "step.log";
	$typename = "Perform";
    } elsif (-f "test.log") {
	$D{$date}{log} = "test.log";
	$typename = "Ports";
    } elsif (-f "make.log") {
	$D{$date}{log} = "make.log";
	$typename = "Release";
    }
    if (-f "test.log.tgz") {
	$D{$date}{logtgz} = "test.log.tgz";
    }
    if (-f "test.obj.tgz") {
	$D{$date}{objtgz} = "test.obj.tgz";
    }
}

if ($opts{a} || $opts{d}) {
    foreach my $reldate (@reldates) {
	$date = basename($reldate);
	my $dir = "$regressdir/results/$reldate";
	chdir($dir)
	    or die "Change directory to '$dir' failed: $!";

	next unless keys %{$D{$date}{host}};
	my @cvsdates = @{$D{$date}{cvsdates}};
	create_html_setup($date, @cvsdates);

	foreach my $cvsdate (@cvsdates) {
	    my $subdir = "$dir/$cvsdate";
	    chdir($subdir)
		or die "Change directory to '$subdir' failed: $!";

	    next unless keys %{$D{$date}{$cvsdate}{host}};
	    my @repeats = @{$D{$date}{$cvsdate}{repeats}};
	    create_html_build($date, $cvsdate, @repeats);

	    foreach my $repeat (@repeats) {
		my $subdir = "$dir/$cvsdate/$repeat";
		chdir($subdir)
		    or die "Change directory to '$subdir' failed: $!";

		next unless keys %{$D{$date}{$cvsdate}{$repeat}{host}};
		create_html_reboot($date, $cvsdate, $repeat);
	    }
	}
    }
}

chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";
foreach my $result (qw(regress perform latest run)) {
    $H{$result} = "$result.html" if -f "$result.html";
}
foreach my $result (qw(current latest)) {
    $H{$result} = "$result/perform.html" if -f "$result/perform.html";
}
if (my @releases = glob("[0-9]*.[0-9]/perform.html")) {
    $H{release} = $releases[-1];
}

unless ($opts{d}) {
    create_html_run();
}

exit;

sub create_html_setup {
    my ($date, @cvsdates) = @_;

    my $h = $D{$date}{host};

    my ($html, $htmlfile) = html_open("setup");
    html_header($html, "OpenBSD $typename Setup",
	"OpenBSD ". lc($typename). " test machine setup");
    print $html "<table>\n";
    print $html "  <tr>\n    <th>created at</th>\n";
    print $html "    <td>$now</td>\n";
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>run at</th>\n";
    print $html "    <td>$date</td>\n";
    print $html "  </tr>\n";
    if (my $log = $D{$date}{log}) {
	print $html "  <tr>\n    <th>run</th>\n";
	print $html "    <td><a href=\"$log\">log</a></td>\n";
	print $html "  </tr>\n";
    }
    if (my $logtgz = $D{$date}{logtgz}) {
	print $html "  <tr>\n    <th>make log</th>\n";
	print $html "    <td><a href=\"$logtgz\">tgz</a></td>\n";
	print $html "  </tr>\n";
    }
    if (my $objtgz = $D{$date}{objtgz}) {
	print $html "  <tr>\n    <th>make obj</th>\n";
	print $html "    <td><a href=\"$objtgz\">tgz</a></td>\n";
	print $html "  </tr>\n";
    }
    print $html "</table>\n";
    print $html "<table>\n";
    print $html "  <tr>\n    <th>machine</th>\n";
    print $html "    <th>repeat</th>\n"
	if @cvsdates && @{$D{$date}{$cvsdates[0]}{repeats}};
    print $html "    <th>checkout</th>\n"
	if @cvsdates;
    print $html "    <th>kernel</th>\n";
    print $html "    <th>arch</th>\n";
    print $html "    <th>setup</th>\n";
    print $html "    <th>console</th>\n";
    print $html "    <th colspan=\"2\">dmesg</th>\n";
    print $html "    <th>diff</th>\n";
    print $html "    <th>quirks</th>\n";
    print $html "    <th>nmbsd</th>\n";
    print $html "  </tr>\n";
    foreach my $cvsdate ("", @cvsdates) {
	$h = $D{$date}{$cvsdate}{host} if $cvsdate;
	my @repeats = $cvsdate ? @{$D{$date}{$cvsdate}{repeats}} : ();
	foreach my $repeat ("", @repeats) {
	    $h = $D{$date}{$cvsdate}{$repeat}{host} if $repeat;
	    foreach my $host (sort keys %$h) {
		print $html "  <tr>\n    <th>$host</th>\n";
		if ($repeat) {
		    (my $repshort = $repeat) =~ s/^btrace-(.*)\.\d+$/$1/;
		    print $html "    <td title=\"$repeat\">$repshort</td>\n";
		} elsif (@cvsdates && @{$D{$date}{$cvsdates[0]}{repeats}}) {
		    print $html "    <td></td>\n";
		}
		if ($cvsdate) {
		    (my $cvsshort = $cvsdate) =~ s/T.*//;
		    $cvsshort =~ s/^patch-(.*)\.\d+$/$1/;
		    print $html "    <td title=\"$cvsdate\">$cvsshort</td>\n";
		} elsif (@cvsdates) {
		    print $html "    <td></td>\n";
		}
		my $version = $h->{$host}{version};
		my $time = encode_entities($h->{$host}{time});
		my $short = $h->{$host}{short};
		my $arch = encode_entities($h->{$host}{arch}) || "";
		my $setup = $h->{$host}{setup} || $h->{$host}{build} ||
		    $h->{$host}{reboot};
		my $bsdcons = $h->{$host}{bsdcons};
		my $dmesg = $h->{$host}{dmesg};
		my $dmesgboot = $h->{$host}{dmesgboot};
		my $diff = $h->{$host}{diff};
		my $quirks = $h->{$host}{quirks};
		my $nmbsd = $h->{$host}{nmbsd};
		if ($version) {
		    $version = uri_escape($version, "^A-Za-z0-9\-\._~/");
		    print $html "    <td title=\"$time\">".
			"<a href=\"$version\">$short</a></td>\n";
		} else {
		    print $html "    <td></td>\n";
		}
		print $html "    <td>$arch</td>\n";
		if ($setup) {
		    $setup = uri_escape($setup, "^A-Za-z0-9\-\._~/");
		    print $html "    <td><a href=\"$setup\">log</a></td>\n";
		} else {
		    print $html "    <td></td>\n";
		}
		if ($bsdcons) {
		    $bsdcons = uri_escape($bsdcons, "^A-Za-z0-9\-\._~/");
		    print $html "    <td><a href=\"$bsdcons\">cons</a></td>\n";
		} else {
		    print $html "    <td></td>\n";
		}
		if ($dmesgboot) {
		    $dmesgboot = uri_escape($dmesgboot, "^A-Za-z0-9\-\._~/");
		    print $html
			"    <td><a href=\"$dmesgboot\">boot</a></td>\n";
		} else {
		    print $html "    <td></td>\n";
		}
		if ($dmesg) {
		    $dmesg = uri_escape($dmesg, "^A-Za-z0-9\-\._~/");
		    print $html "    <td><a href=\"$dmesg\">run</a></td>\n";
		} else {
		    print $html "    <td></td>\n";
		}
		if ($diff) {
		    $diff = uri_escape($diff, "^A-Za-z0-9\-\._~/");
		    print $html "    <td><a href=\"$diff\">diff</a></td>\n";
		} else {
		    print $html "    <td></td>\n";
		}
		if ($quirks) {
		    $quirks = uri_escape($quirks, "^A-Za-z0-9\-\._~/");
		    print $html "    <td><a href=\"$quirks\">quirks</a></td>\n";
		} else {
		    print $html "    <td></td>\n";
		}
		if ($nmbsd) {
		    $nmbsd = uri_escape($nmbsd, "^A-Za-z0-9\-\._~/");
		    print $html "    <td><a href=\"$nmbsd\">nmbsd</a></td>\n";
		} else {
		    print $html "    <td></td>\n";
		}
		print $html "  </tr>\n";
	    }
	}
    }
    print $html "</table>\n";
    html_footer($html);
    html_close($html, $htmlfile, "nozip");
}

sub create_html_build {
    my ($date, $cvsdate, @repeats) = @_;

    my $h = $D{$date}{$cvsdate}{host};

    my ($html, $htmlfile) = html_open("build");
    print $html "<!DOCTYPE html>\n";
    print $html "<html>\n";
    print $html "<head>\n";
    print $html "  <title>OpenBSD CVS Build</title>\n";
    print $html "  <style>th { text-align: left; }</style>\n";
    print $html "</head>\n";

    print $html "<body>\n";
    print $html "<h1>OpenBSD perform test machine build</h1>\n";
    print $html "<table>\n";
    print $html "  <tr>\n    <th>created at</th>\n";
    print $html "    <td>$now</td>\n";
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>run at</th>\n";
    print $html "    <td>$date</td>\n";
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>cvs checkout</th>\n";
    print $html "    <td>$cvsdate</td>\n";
    print $html "  </tr>\n";
    print $html "</table>\n";
    print $html "<table>\n";
    print $html "  <tr>\n    <th>machine</th>\n";
    print $html "    <th>repeat</th>\n" if @repeats;
    print $html "    <th>checkout</th>\n";
    print $html "    <th>kernel</th>\n";
    print $html "    <th>arch</th>\n";
    print $html "    <th>build</th>\n";
    print $html "    <th colspan=\"2\">dmesg</th>\n";
    print $html "    <th>diff</th>\n";
    print $html "    <th>quirks</th>\n";
    print $html "    <th>nmbsd</th>\n";
    print $html "  </tr>\n";
    foreach my $repeat ("", @repeats) {
	$h = $D{$date}{$cvsdate}{$repeat}{host} if $repeat;
	foreach my $host (sort keys %$h) {
	    print $html "  <tr>\n    <th>$host</th>\n";
	    if ($repeat) {
		(my $repshort = $repeat) =~ s/^btrace-(.*)\.\d+$/$1/;
		print $html "    <td title=\"$repeat\">$repshort</td>\n";
	    } elsif (@repeats) {
		print $html "    <td></td>\n";
	    }
	    (my $cvsshort = $cvsdate) =~ s/T.*//;
	    $cvsshort =~ s/^patch-(.*)\.\d+$/$1/;
	    print $html "    <td title=\"$cvsdate\">$cvsshort</td>\n";
	    my $version = $h->{$host}{version};
	    my $time = encode_entities($h->{$host}{time});
	    my $short = $h->{$host}{short};
	    my $arch = encode_entities($h->{$host}{arch}) || "";
	    my $build = $h->{$host}{build} || $h->{$host}{reboot};
	    my $dmesg = $h->{$host}{dmesg};
	    my $dmesgboot = $h->{$host}{dmesgboot};
	    my $diff = $h->{$host}{diff};
	    my $quirks = $h->{$host}{quirks};
	    my $nmbsd = $h->{$host}{nmbsd};
	    if ($version) {
		$version =~ s,[^/]+/,,;
		$version = uri_escape($version, "^A-Za-z0-9\-\._~/");
		print $html "    <td title=\"$time\">".
		    "<a href=\"$version\">$short</a></td>\n";
	    } else {
		print $html "    <td></td>\n";
	    }
	    print $html "    <td>$arch</td>\n";
	    if ($build) {
		$build =~ s,[^/]+/,,;
		$build = uri_escape($build, "^A-Za-z0-9\-\._~/");
		print $html "    <td><a href=\"$build\">log</a></td>\n";
	    } else {
		print $html "    <td></td>\n";
	    }
	    if ($dmesgboot) {
		$dmesgboot =~ s,[^/]+/,,;
		$dmesgboot = uri_escape($dmesgboot, "^A-Za-z0-9\-\._~/");
		print $html
		    "    <td><a href=\"$dmesgboot\">boot</a></td>\n";
	    } else {
		print $html "    <td></td>\n";
	    }
	    if ($dmesg) {
		$dmesg =~ s,[^/]+/,,;
		$dmesg = uri_escape($dmesg, "^A-Za-z0-9\-\._~/");
		print $html "    <td><a href=\"$dmesg\">run</a></td>\n";
	    } else {
		print $html "    <td></td>\n";
	    }
	    if ($diff) {
		$diff =~ s,[^/]+/,,;
		$diff = uri_escape($diff, "^A-Za-z0-9\-\._~/");
		print $html "    <td><a href=\"$diff\">diff</a></td>\n";
	    } else {
		print $html "    <td></td>\n";
	    }
	    if ($quirks) {
		$quirks =~ s,[^/]+/,,;
		$quirks = uri_escape($quirks, "^A-Za-z0-9\-\._~/");
		print $html "    <td><a href=\"$quirks\">quirks</a></td>\n";
	    } else {
		print $html "    <td></td>\n";
	    }
	    if ($nmbsd) {
		$nmbsd =~ s,[^/]+/,,;
		$nmbsd = uri_escape($nmbsd, "^A-Za-z0-9\-\._~/");
		print $html "    <td><a href=\"$nmbsd\">nmbsd</a></td>\n";
	    } else {
		print $html "    <td></td>\n";
	    }
	    print $html "  </tr>\n";
	}
    }
    print $html "</table>\n";
    html_footer($html);
    html_close($html, $htmlfile, "nozip");
}

sub create_html_reboot {
    my ($date, $cvsdate, $repeat) = @_;

    my $h = $D{$date}{$cvsdate}{$repeat}{host};

    my ($html, $htmlfile) = html_open("reboot");
    print $html "<!DOCTYPE html>\n";
    print $html "<html>\n";
    print $html "<head>\n";
    print $html "  <title>OpenBSD Machine Reboot</title>\n";
    print $html "  <style>th { text-align: left; }</style>\n";
    print $html "</head>\n";

    print $html "<body>\n";
    print $html "<h1>OpenBSD perform test machine reboot</h1>\n";
    print $html "<table>\n";
    print $html "  <tr>\n    <th>created at</th>\n";
    print $html "    <td>$now</td>\n";
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>run at</th>\n";
    print $html "    <td>$date</td>\n";
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>cvs checkout</th>\n";
    print $html "    <td>$cvsdate</td>\n";
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>repetition</th>\n";
    print $html "    <td>$repeat</td>\n";
    print $html "  </tr>\n";
    print $html "</table>\n";
    print $html "<table>\n";
    print $html "  <tr>\n    <th>machine</th>\n";
    print $html "    <th>repeat</th>\n";
    print $html "    <th>checkout</th>\n";
    print $html "    <th>kernel</th>\n";
    print $html "    <th>arch</th>\n";
    print $html "    <th>reboot</th>\n";
    print $html "    <th colspan=\"2\">dmesg</th>\n";
    print $html "    <th>diff</th>\n";
    print $html "    <th>quirks</th>\n";
    print $html "    <th>nmbsd</th>\n";
    print $html "  </tr>\n";
    foreach my $host (sort keys %$h) {
	print $html "  <tr>\n    <th>$host</th>\n";
	(my $repshort = $repeat) =~ s/^btrace-(.*)\.\d+$/$1/;
	print $html "    <td title=\"$repeat\">$repshort</td>\n";
	(my $cvsshort = $cvsdate) =~ s/T.*//;
	$cvsshort =~ s/^patch-(.*)\.\d+$/$1/;
	print $html "    <td title=\"$cvsdate\">$cvsshort</td>\n";
	my $version = $h->{$host}{version};
	my $time = encode_entities($h->{$host}{time});
	my $short = $h->{$host}{short};
	my $arch = encode_entities($h->{$host}{arch}) || "";
	my $reboot = $h->{$host}{reboot};
	my $dmesg = $h->{$host}{dmesg};
	my $dmesgboot = $h->{$host}{dmesgboot};
	my $diff = $h->{$host}{diff};
	my $quirks = $h->{$host}{quirks};
	my $nmbsd = $h->{$host}{nmbsd};
	if ($version) {
	    $version =~ s,[^/]+/[^/]+/,,;
	    $version = uri_escape($version, "^A-Za-z0-9\-\._~/");
	    print $html "    <td title=\"$time\">".
		"<a href=\"$version\">$short</a></td>\n";
	} else {
	    print $html "    <td></td>\n";
	}
	print $html "    <td>$arch</td>\n";
	if ($reboot) {
	    $reboot =~ s,[^/]+/[^/]+/,,;
	    $reboot = uri_escape($reboot, "^A-Za-z0-9\-\._~/");
	    print $html
		"    <td><a href=\"$reboot\">log</a></td>\n";
	} else {
	    print $html "    <td></td>\n";
	}
	if ($dmesgboot) {
	    $dmesgboot =~ s,[^/]+/[^/]+/,,;
	    $dmesgboot = uri_escape($dmesgboot, "^A-Za-z0-9\-\._~/");
	    print $html
		"    <td><a href=\"$dmesgboot\">boot</a></td>\n";
	} else {
	    print $html "    <td></td>\n";
	}
	if ($dmesg) {
	    $dmesg =~ s,[^/]+/[^/]+/,,;
	    $dmesg = uri_escape($dmesg, "^A-Za-z0-9\-\._~/");
	    print $html "    <td><a href=\"$dmesg\">run</a></td>\n";
	} else {
	    print $html "    <td></td>\n";
	}
	if ($diff) {
	    $diff =~ s,[^/]+/[^/]+/,,;
	    $diff = uri_escape($diff, "^A-Za-z0-9\-\._~/");
	    print $html "    <td><a href=\"$diff\">diff</a></td>\n";
	} else {
	    print $html "    <td></td>\n";
	}
	if ($quirks) {
	    $quirks =~ s,[^/]+/[^/]+/,,;
	    $quirks = uri_escape($quirks, "^A-Za-z0-9\-\._~/");
	    print $html "    <td><a href=\"$quirks\">quirks</a></td>\n";
	} else {
	    print $html "    <td></td>\n";
	}
	if ($nmbsd) {
	    $nmbsd =~ s,[^/]+/[^/]+/,,;
	    $nmbsd = uri_escape($nmbsd, "^A-Za-z0-9\-\._~/");
	    print $html "    <td><a href=\"$nmbsd\">nmbsd</a></td>\n";
	} else {
	    print $html "    <td></td>\n";
	}
	print $html "  </tr>\n";
    }
    print $html "</table>\n";
    html_footer($html);
    html_close($html, $htmlfile, "nozip");
}

