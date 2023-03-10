#!/usr/bin/perl
# convert test setup details to a html table

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
use File::Glob qw(:bsd_glob);
use HTML::Entities;
use Getopt::Std;
use Date::Parse;
use POSIX;
use URI::Escape;

use lib dirname($0);
use Html;

my $now = strftime("%FT%TZ", gmtime);

my %opts;
getopts('ad:v', \%opts) or do {
    print STDERR <<"EOF";
usage: setup-html.pl [-a] [-d date]
    -a		create setup.html for all dates
    -d date	create setup.html for a specific date, may be current
    -v		verbose
EOF
    exit(2);
};
$opts{a} && $opts{d}
    and die "Options -a and -d cannot be used together";
!$opts{d} || $opts{d} eq "current" || str2time($opts{d})
    or die "Invalid -d date '$opts{d}'";
my $date = $opts{d};
my $verbose = $opts{v};
$| = 1 if $verbose;
@ARGV and die "No arguments allowed";

my $regressdir = dirname($0). "/..";
chdir($regressdir)
    or die "Change directory to '$regressdir' failed: $!";
$regressdir = getcwd();
my $resultdir = "$regressdir/results";
if ($date && $date eq "current") {
    my $current = readlink("$resultdir/$date")
	or die "Read link '$resultdir/$date' failed: $!";
    -d "$resultdir/$current"
	or die "Test directory '$resultdir/$current' failed: $!";
    $date = $current;
}
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

my (%D, %M, %N);

# %D
# %M
# %N
# $N{regress}		navigation link to regress.html
# $N{perform}		navigation link to perform.html
# $N{latest}		navigation link to latest.html
# $N{run}		navigation link to run.html
# $N{current}		navigation link to current/perform.html
# $N{latest}		navigation link to latest/perform.html
# $N{release}		navigation link to latest release perform.html

my $typename;
{
    print "glob log files" if $verbose;
    my @reldates = glob_log_files($date);
    print "\nparse log files" if $verbose;
    $typename = parse_log_files(@reldates);
    print "\n" if $verbose;
}

if ($opts{a} || $opts{d}) {
    print "create html files" if $verbose;
    create_html_files();
    print "\n" if $verbose;
}

exit if $opts{d};

chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

print "fill navigation links" if $verbose;
fill_navigation_links();
print "\n" if $verbose;

print "create html run" if $verbose;
write_html_run();
print "\n" if $verbose;

exit;

sub glob_log_files {
    my ($date) = @_;

    print "." if $verbose;
    if ($date) {
	return (bsd_glob("$date", GLOB_NOSORT),
	    bsd_glob("[0-9]*.[0-9]/$date", GLOB_NOSORT));
    }

    my @dates =
	map { dirname($_) } (
	bsd_glob("*T*/run.log", GLOB_NOSORT),
	bsd_glob("*T*/step.log", GLOB_NOSORT),
	bsd_glob("*T*/test.log", GLOB_NOSORT),
	bsd_glob("*T*/make.log", GLOB_NOSORT),
	bsd_glob("*T*/net.log", GLOB_NOSORT));
    print "." if $verbose;
    my @reldates =
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
	return sort { basename($a) cmp basename($b) } (
	    splice(@dates), splice(@reldates));
    } else {
	return splice(@dates);
    }
}

sub parse_log_files {
    my @reldates = @_;

    my $typename;
    foreach my $reldate (@reldates) {
	print "." if $verbose;
	my $date = basename($reldate);
	$D{$date}{reldate} = $reldate;
	my $dir = "$regressdir/results/$reldate";
	chdir($dir)
	    or die "Change directory to '$dir' failed: $!";

	my @cvsdates = grep { -d $_ } (
	    bsd_glob("*T*", GLOB_NOSORT),
	    bsd_glob("[a-z]*.[0-9]", GLOB_NOSORT));
	$D{$date}{cvsdates} = [ @cvsdates ];

	foreach my $cvsdate ("", @cvsdates) {
	    chdir("$dir/$cvsdate")
		or die "Change directory to '$dir/$cvsdate' failed: $!";

	    my @repeats = grep { -d $_ } (
		bsd_glob("[0-9][0-9][0-9]", GLOB_NOSORT),
		bsd_glob("btrace-*", GLOB_NOSORT));
	    $D{$date}{$cvsdate}{repeats} = [ @repeats ] if $cvsdate;

	    foreach my $repeat ("", @repeats) {
		chdir("$dir/$cvsdate/$repeat") or die
		    "Change directory to '$dir/$cvsdate/$repeat' failed: $!";

		my %h;
		foreach my $version (glob("version-*.txt")) {
		    my ($host) = $version =~ m,version-(.*)\.txt,;
		    my %v = parse_version_file($version);
		    $v{kerntime} or next;
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
			%v,
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
		    $D{$date}{$cvsdate}{$repeat}{log} = "once.log"
			if -f "once.log";
		} elsif ($cvsdate) {
		    $D{$date}{$cvsdate}{host} = \%h;
		    $D{$date}{$cvsdate}{log} = "once.log" if -f "once.log";
		} else {
		    $D{$date}{host} = \%h;
		    $D{$date}{log} = "once.log" if -f "once.log";
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
	} elsif (-f "net.log") {
	    $D{$date}{log} = "net.log";
	    $typename = "Net";
	}
	$D{$date}{logmtime} = (stat($D{$date}{log}))[9] if $D{$date}{log};
	if (-f "test.log.tgz") {
	    $D{$date}{logtgz} = "test.log.tgz";
	}
	if (-f "test.obj.tgz") {
	    $D{$date}{objtgz} = "test.obj.tgz";
	}
	if (-f "perform.html") {
	    $D{$date}{result} = "$reldate/perform.html";
	}
    }
    return $typename;
}

sub create_html_files {
    foreach my $date (sort keys %D) {
	my $dv = $D{$date};
	my $reldate = $dv->{reldate};
	print "." if $verbose;
	my $dir = "$regressdir/results/$reldate";
	chdir($dir)
	    or die "Change directory to '$dir' failed: $!";

	next unless keys %{$dv->{host}};
	my @cvsdates = @{$dv->{cvsdates}};
	write_html_setup($date, @cvsdates);

	foreach my $cvsdate (@cvsdates) {
	    print "." if $verbose;
	    my $subdir = "$dir/$cvsdate";
	    chdir($subdir)
		or die "Change directory to '$subdir' failed: $!";

	    my $cv = $dv->{$cvsdate};
	    next unless keys %{$cv->{host}};
	    my @repeats = @{$cv->{repeats}};
	    write_html_build($date, $cvsdate, @repeats);

	    foreach my $repeat (@repeats) {
		print "." if $verbose;
		my $subdir = "$dir/$cvsdate/$repeat";
		chdir($subdir)
		    or die "Change directory to '$subdir' failed: $!";

		my $rv = $cv->{$repeat};
		next unless keys %{$rv->{host}};
		write_html_reboot($date, $cvsdate, $repeat);
	    }
	}
    }
}

sub write_html_setup {
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
	my $start = str2time($date);
	my $duration = $D{$date}{logmtime} - $start;
	print $html "  <tr>\n    <th>duration</th>\n";
	print $html "    <td>", $duration >= 24*60*60 ?
	    sprintf("%.2f days", $duration / (24*60*60)) :
	    strftime("%T", gmtime($duration)), "</td>\n";
	print $html "  </tr>\n";
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
    print $html "  <thead>\n";
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
    print $html "  </thead>\n  <tbody>\n";

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
		    $cvsshort =~ s/^(\w+)\.\d+$/$1/;
		    print $html "    <td title=\"$cvsdate\">$cvsshort</td>\n";
		} elsif (@cvsdates) {
		    print $html "    <td></td>\n";
		}
		my $version = $h->{$host}{version};
		my $time = encode_entities($h->{$host}{kerntime});
		my $short = $h->{$host}{kernshort};
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
    print $html "  </tbody>\n";
    print $html "</table>\n";

    html_footer($html);
    html_close($html, $htmlfile, "nozip");
}

sub write_html_build {
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
    print $html "  <thead>\n";
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
    print $html "  </thead>\n  <tbody>\n";

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
	    $cvsshort =~ s/^(\w+)\.\d+$/$1/;
	    print $html "    <td title=\"$cvsdate\">$cvsshort</td>\n";
	    my $version = $h->{$host}{version};
	    my $time = encode_entities($h->{$host}{kerntime});
	    my $short = $h->{$host}{kernshort};
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
    print $html "  </tbody>\n";
    print $html "</table>\n";

    html_footer($html);
    html_close($html, $htmlfile, "nozip");
}

sub write_html_reboot {
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
    print $html "  <thead>\n";
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
    print $html "  </thead>\n  <tbody>\n";

    foreach my $host (sort keys %$h) {
	print $html "  <tr>\n    <th>$host</th>\n";
	(my $repshort = $repeat) =~ s/^btrace-(.*)\.\d+$/$1/;
	print $html "    <td title=\"$repeat\">$repshort</td>\n";
	(my $cvsshort = $cvsdate) =~ s/T.*//;
	$cvsshort =~ s/^patch-(.*)\.\d+$/$1/;
	$cvsshort =~ s/^(\w+)\.\d+$/$1/;
	print $html "    <td title=\"$cvsdate\">$cvsshort</td>\n";
	my $version = $h->{$host}{version};
	my $time = encode_entities($h->{$host}{kerntime});
	my $short = $h->{$host}{kernshort};
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
    print $html "  </tbody>\n";
    print $html "</table>\n";

    html_footer($html);
    html_close($html, $htmlfile, "nozip");
}

sub fill_navigation_links {
    foreach my $result (qw(regress perform latest run)) {
	$N{$result} = "$result.html" if -f "$result.html";
    }
    foreach my $result (qw(current latest)) {
	$N{$result} = "$result/perform.html" if -f "$result/perform.html";
    }
    if (my @releases = glob("[0-9]*.[0-9]/perform.html")) {
	$N{release} = $releases[-1];
    }
}

sub write_html_run {
    my ($html, $htmlfile) = html_open("run");
    my @nav = (
	Top     => "../../test.html",
	All     => $N{regress} || $N{perform},
	$N{release} ? (Release => $N{release}) : (),
	$N{current} ? (Current => $N{current}) : (),
	Latest  => $N{latest},
	Running => "../../results/running.html");
    html_header($html, "OpenBSD $typename Run",
	"OpenBSD ". lc($typename). " test run",
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
    print $html "  <tr>\n    <th>run log</th>\n";
    foreach my $host (sort keys %M) {
	print $html "    <th>$host setup log</th>\n";
    }
    print $html "  </tr>\n";
    print $html "  </thead>\n  <tbody>\n";

    foreach my $date (reverse sort keys %D) {
	print "." if $verbose;
	my $reldate = $D{$date}{reldate};
	my @cvsdates = @{$D{$date}{cvsdates}};
	foreach my $cvsdate (reverse "", @cvsdates) {
	    my @repeats = $cvsdate ? @{$D{$date}{$cvsdate}{repeats}} : ();
	    foreach my $repeat (reverse "", @repeats) {
		print $html "  <tr>\n";
		my ($h, $log, $logdir, $result);
		if ($repeat) {
		    $h = $D{$date}{$cvsdate}{$repeat}{host};
		    $log = $D{$date}{$cvsdate}{$repeat}{log};
		    $logdir = "$reldate/$cvsdate/$repeat";
		} elsif ($cvsdate) {
		    $h = $D{$date}{$cvsdate}{host};
		    $log = $D{$date}{$cvsdate}{log};
		    $logdir = "$reldate/$cvsdate";
		} else {
		    $h = $D{$date}{host};
		    $log = $D{$date}{log};
		    $logdir = "$reldate";
		    $result = $D{$date}{result};
		}
		my ($mtime, $status);
		if ($log) {
		    my $logfile = "$logdir/$log";
		    $mtime = (stat($logfile))[9];
		    $status = log2status($logfile);
		    my $class = " class=\"status $status\"";
		    my $link = uri_escape($logfile, "^A-Za-z0-9\-\._~/");
		    my $href = $log ? "<a href=\"$link\">" : "";
		    my $enda = $href ? "</a>" : "";
		    print $html "    <td$class>$href$date$enda";
		} else {
		    print $html "    <td>";
		}
		my $console = 0;
		foreach my $host (sort keys %M) {
		    $h->{$host}
			or next;
		    my $bsdcons = $h->{$host}{bsdcons}
			or next;
		    print $html "<br>console" unless $console++;
		    my $logfile = "$reldate/$bsdcons";
		    my $link = uri_escape($logfile, "^A-Za-z0-9\-\._~/");
		    print $html " <a href=\"$link\">$host</a>";
		}
		if ($mtime && $status !~ /^(NOEXIT|NOTERM)$/) {
		    my $start = str2time($date);
		    my $duration = $mtime - $start;
		    print $html "<br>duration ";
		    print $html $duration >= 24*60*60 ?
			sprintf("%.2f days", $duration / (24*60*60)) :
			strftime("%T", gmtime($duration));
		}
		if ($result) {
		    my $link = uri_escape($result, "^A-Za-z0-9\-\._~/");
		    print $html "<br><a href=\"$link\">result</a>";
		}
		print $html "</td>\n";
		foreach my $host (sort keys %M) {
		    unless ($D{$date}{host}{$host} ||
			$D{$date}{$cvsdate}{host}{$host} ||
			$D{$date}{$cvsdate}{$repeat}{host}{$host}) {
			print $html "    <td></td>\n";
			next;
		    }
		    my $time = encode_entities($repeat || $cvsdate ||
			$h->{$host}{kerntime}) || "";
		    my $setup = $h->{$host}{setup} || $h->{$host}{build} ||
			$h->{$host}{reboot} || "";
		    $time ||= "setup" if $setup;
		    my $logfile = "$reldate/$setup";
		    my $status = $setup ? log2status($logfile) : "";
		    my $class = $status ? " class=\"status $status\"" : "";
		    my $link = uri_escape($logfile, "^A-Za-z0-9\-\._~/");
		    my $href = $setup ? "<a href=\"$link\">" : "";
		    my $enda = $href ? "</a>" : "";
		    print $html "    <td$class>$href$time$enda";
		    print $html "</td>\n";
		}
		print $html "  </tr>\n";
	    }
	}
    }
    print $html "  </tbody>\n";
    print $html "</table>\n";

    print $html "Each row displays one running test setup.\n";
    print $html "If a row is completely green, the test has finished.\n";
    print $html "Red means the failure should be examined.\n";
    print $html "If a row has any yellow, wait for the test to finish.\n";
    html_running_table($html);
    html_footer($html);
    html_close($html, $htmlfile);
}
