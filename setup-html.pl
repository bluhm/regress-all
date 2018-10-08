#!/usr/bin/perl
# convert test setup details to a html table

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
getopts('d:', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-d date]
    -d date	create setup.html for a specific date, otherwise for all
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

my $typename = "";
my @dates = $opts{d} || map { dirname($_) }
    (glob("*T*/run.log"), glob("*T*/step.log"));
my (%d, %m);
foreach my $date (@dates) {
    $dir = "$regressdir/results/$date";
    chdir($dir)
	or die "Chdir to '$dir' failed: $!";

    my @cvsdates = grep { -d $_ } glob("*T*");
    $d{$date}{cvsdates} = \@cvsdates;

    foreach my $cvsdate ("", @cvsdates) {
	my $subdir = "$dir/$cvsdate";
	chdir($subdir)
	    or die "Chdir to '$subdir' failed: $!";
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
	    (my $dmesg = $version) =~ s,version,dmesg,;
	    (my $dmesgboot = $version) =~ s,version,dmesg-boot,;
	    (my $diff = $version) =~ s,version,diff,;
	    (my $quirks = $version) =~ s,version,quirks,;
	    my $cvsdir = $cvsdate ? "$cvsdate/" : "";
	    $h{$host} = {
		version   => $cvsdir.$version,
		time      => $time,
		short     => $short,
		arch      => $arch,
		dmesg     => -f $dmesg ? $cvsdir.$dmesg : undef,
		dmesgboot => -f $dmesgboot ? $cvsdir.$dmesgboot : undef,
		diff      => -f $diff ? $cvsdir.$diff : undef,
		quirks    => -f $quirks ? $cvsdir.$quirks : undef,
	    };
	    $m{$host}++;
	}
	foreach my $setup (glob("setup-*.log")) {
	    my ($host) = $setup =~ m,setup-(.*)\.log,;
	    $h{$host}{setup} = $setup,
	}
	foreach my $build (glob("cvsbuild-*.log")) {
	    my ($host) = $build =~ m,cvsbuild-(.*)\.log,;
	    $h{$host}{build} = "$cvsdate/$build",
	}
	if ($cvsdate) {
	    $d{$date}{$cvsdate}{host} = \%h;
	} else {
	    $d{$date}{host} = \%h;
	}
    }
    chdir($dir)
	or die "Chdir to '$dir' failed: $!";

    $typename = "regress" if -f "run.log";
    $typename = "perform" if -f "step.log";
    unlink("setup.html.new");
    open(my $html, '>', "setup.html.new")
	or die "Open 'setup.html.new' for writing failed: $!";
    print $html "<!DOCTYPE html>\n";
    print $html "<html>\n";
    print $html "<head>\n";
    print $html "  <title>OpenBSD Test Setup</title>\n";
    print $html "  <style>th { text-align: left; }</style>\n";
    print $html "</head>\n";

    print $html "<body>\n";
    print $html "<h1>OpenBSD $typename test machine</h1>\n";
    print $html "<table>\n";
    print $html "  <tr>\n    <th>created at</th>\n";
    print $html "    <td>$now</td>\n";
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>run at</th>\n";
    print $html "    <td>$date</td>\n";
    print $html "  </tr>\n";
    if (-f "run.log") {
	$d{$date}{log} = "run.log";
	print $html "  <tr>\n    <th>run</th>\n";
	print $html "    <td><a href=\"run.log\">log</a></td>\n";
	print $html "  </tr>\n";
    } elsif (-f "step.log") {
	$d{$date}{log} = "step.log";
	print $html "  <tr>\n    <th>run</th>\n";
	print $html "    <td><a href=\"step.log\">log</a></td>\n";
	print $html "  </tr>\n";
    }
    if (-f "test.log.tgz") {
	$d{$date}{logtgz} = "test.log.tgz";
	print $html "  <tr>\n    <th>make log</th>\n";
	print $html "    <td><a href=\"test.log.tgz\">tgz</a></td>\n";
	print $html "  </tr>\n";
    }
    if (-f "test.obj.tgz") {
	$d{$date}{objtgz} = "test.obj.tgz";
	print $html "  <tr>\n    <th>make obj</th>\n";
	print $html "    <td><a href=\"test.obj.tgz\">tgz</a></td>\n";
	print $html "  </tr>\n";
    }
    print $html "</table>\n";
    print $html "<table>\n";
    print $html "  <tr>\n    <th>machine</th>\n";
    print $html "    <th>checkout</th>\n";
    print $html "    <th>kernel</th>\n";
    print $html "    <th>arch</th>\n";
    print $html "    <th>setup</th>\n";
    print $html "    <th colspan=\"2\">dmesg</th>\n";
    print $html "    <th>diff</th>\n";
    print $html "    <th>quirks</th>\n";
    print $html "  </tr>\n";

    foreach my $cvsdate ("", @cvsdates) {
	my $h = $cvsdate ? $d{$date}{$cvsdate}{host} : $d{$date}{host};
	foreach my $host (sort keys %$h) {
	    print $html "  <tr>\n    <th>$host</th>\n";
	    if ($cvsdate) {
		(my $cvsshort = $cvsdate) =~ s/T.*//;
		print $html "    <td title=\"$cvsdate\">$cvsshort</td>\n";
	    } else {
		print $html "    <td/>\n";
	    }
	    my $version = $h->{$host}{version};
	    my $time = encode_entities($h->{$host}{time});
	    my $short = $h->{$host}{short};
	    my $arch = encode_entities($h->{$host}{arch}) || "";
	    my $setup = $h->{$host}{setup} || $h->{$host}{build};
	    my $dmesg = $h->{$host}{dmesg};
	    my $dmesgboot = $h->{$host}{dmesgboot};
	    my $diff = $h->{$host}{diff};
	    my $quirks = $h->{$host}{quirks};
	    if ($version) {
		print $html "    <td title=\"$time\">".
		    "<a href=\"$version\">$short</a></td>\n";
	    } else {
		print $html "    <td/>\n";
	    }
	    print $html "    <td>$arch</td>\n";
	    if ($setup) {
		print $html "    <td><a href=\"$setup\">log</a></td>\n";
	    } else {
		print $html "    <td/>\n";
	    }
	    if ($dmesgboot) {
		print $html "    <td><a href=\"$dmesgboot\">boot</a></td>\n";
	    } else {
		print $html "    <td/>\n";
	    }
	    if ($dmesg) {
		print $html "    <td><a href=\"$dmesg\">run</a></td>\n";
	    } else {
		print $html "    <td/>\n";
	    }
	    if ($diff) {
		print $html "    <td><a href=\"$diff\">diff</a></td>\n";
	    } else {
		print $html "    <td/>\n";
	    }
	    if ($quirks) {
		print $html "    <td><a href=\"$quirks\">quirks</a></td>\n";
	    } else {
		print $html "    <td/>\n";
	    }
	    print $html "  </tr>\n";
	}
    }
    print $html "</table>\n";
    print $html "</body>\n";

    print $html "</html>\n";
    close($html)
	or die "Close 'setup.html.new' after writing failed: $!";
    rename("setup.html.new", "setup.html")
	or die "Rename 'setup.html.new' to 'setup.html' failed: $!";

    foreach my $cvsdate (@cvsdates) {
	my $subdir = "$dir/$cvsdate";
	chdir($subdir)
	    or die "Chdir to '$subdir' failed: $!";

	unlink("build.html.new");
	open(my $html, '>', "build.html.new")
	    or die "Open 'build.html.new' for writing failed: $!";
	print $html "<!DOCTYPE html>\n";
	print $html "<html>\n";
	print $html "<head>\n";
	print $html "  <title>OpenBSD CVS Build</title>\n";
	print $html "  <style>th { text-align: left; }</style>\n";
	print $html "</head>\n";

	print $html "<body>\n";
	print $html "<h1>OpenBSD perform test machine</h1>\n";
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
	print $html "    <th>checkout</th>\n";
	print $html "    <th>kernel</th>\n";
	print $html "    <th>arch</th>\n";
	print $html "    <th>build</th>\n";
	print $html "    <th colspan=\"2\">dmesg</th>\n";
	print $html "    <th>diff</th>\n";
	print $html "    <th>quirks</th>\n";
	print $html "  </tr>\n";
	my $h = $d{$date}{$cvsdate}{host};
	foreach my $host (sort keys %$h) {
	    print $html "  <tr>\n    <th>$host</th>\n";
	    (my $cvsshort = $cvsdate) =~ s/T.*//;
	    print $html "    <td title=\"$cvsdate\">$cvsshort</td>\n";
	    my $version = $h->{$host}{version};
	    my $time = encode_entities($h->{$host}{time});
	    my $short = $h->{$host}{short};
	    my $arch = encode_entities($h->{$host}{arch}) || "";
	    my $build = $h->{$host}{build};
	    my $dmesg = $h->{$host}{dmesg};
	    my $dmesgboot = $h->{$host}{dmesgboot};
	    my $diff = $h->{$host}{diff};
	    my $quirks = $h->{$host}{quirks};
	    if ($version) {
		$version =~ s,[^/]+/,,;
		print $html "    <td title=\"$time\">".
		    "<a href=\"$version\">$short</a></td>\n";
	    } else {
		print $html "    <td/>\n";
	    }
	    print $html "    <td>$arch</td>\n";
	    if ($build) {
		$build =~ s,[^/]+/,,;
		print $html "    <td><a href=\"$build\">log</a></td>\n";
	    } else {
		print $html "    <td/>\n";
	    }
	    if ($dmesgboot) {
		$dmesgboot =~ s,[^/]+/,,;
		print $html "    <td><a href=\"$dmesgboot\">boot</a></td>\n";
	    } else {
		print $html "    <td/>\n";
	    }
	    if ($dmesg) {
		$dmesg =~ s,[^/]+/,,;
		print $html "    <td><a href=\"$dmesg\">run</a></td>\n";
	    } else {
		print $html "    <td/>\n";
	    }
	    if ($diff) {
		$diff =~ s,[^/]+/,,;
		print $html "    <td><a href=\"$diff\">diff</a></td>\n";
	    } else {
		print $html "    <td/>\n";
	    }
	    if ($quirks) {
		$quirks =~ s,[^/]+/,,;
		print $html "    <td><a href=\"$quirks\">quirks</a></td>\n";
	    } else {
		print $html "    <td/>\n";
	    }
	    print $html "  </tr>\n";
	}
	print $html "</table>\n";
	print $html "</body>\n";

	print $html "</html>\n";
	close($html)
	    or die "Close 'build.html.new' after writing failed: $!";
	rename("build.html.new", "build.html")
	    or die "Rename 'build.html.new' to 'build.html' failed: $!";
    }
}

exit if $opts{d};

$dir = "$regressdir/results";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";

unlink("run.html.new");
open(my $html, '>', "run.html.new")
    or die "Open 'run.html.new' for writing failed: $!";

print $html <<"HEADER";
<!DOCTYPE html>
<html>
<head>
  <title>OpenBSD Regress Run</title>
  <style>th { text-align: left; }</style>
</head>

<body>
<h1>OpenBSD $typename test run</h1>
<table>
  <tr>
    <th>created at</th>
    <td>$now</td>
  </tr>
</table>
HEADER

print $html "<table>\n";
print $html "  <tr>\n    <th>run log</th>\n";
foreach my $host (sort keys %m) {
    print $html "    <th>$host setup log</th>\n";
}
print $html "  </tr>\n";

foreach my $date (reverse sort keys %d) {
    foreach my $cvsdate (reverse "", @{$d{$date}{cvsdates} || []}) {
	my $h;
	if ($cvsdate) {
	    print $html "  <tr>\n    <th></th>\n";
	    $h = $d{$date}{$cvsdate}{host};
	} else {
	    my $log = $d{$date}{log} || "";
	    my $logfile = "$date/$log";
	    my $href = $log ? "<a href=\"$logfile\">" : "";
	    my $enda = $href ? "</a>" : "";
	    print $html "  <tr>\n    <th>$href$date$enda</th>\n";
	    $h = $d{$date}{host};
	}
	foreach my $host (sort keys %m) {
	    my $time = encode_entities($h->{$host}{time}) || "";
	    my $setup = $h->{$host}{setup} || $h->{$host}{build} || "";
	    $time ||= "log" if $setup;
	    my $log = "$date/$setup";
	    my $href = $setup ? "<a href=\"$log\">" : "";
	    my $enda = $href ? "</a>" : "";
	    print $html "    <td>$href$time$enda</td>\n";
	}
	print $html "  </tr>\n";
    }
}
print $html "</table>\n";
print $html <<"FOOTER";
</body>
</html>
FOOTER
close($html)
    or die "Close 'run.html.new' after writing failed: $!";
rename("run.html.new", "run.html")
    or die "Rename 'run.html.new' to 'run.html' failed: $!";
