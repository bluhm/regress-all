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
	chdir("$dir/$cvsdate")
	    or die "Chdir to '$dir/$cvsdate' failed: $!";

	my @repeats = grep { -d $_ } glob("[0-9][0-9][0-9]");
	$d{$date}{$cvsdate}{repeats} = \@repeats if $cvsdate;

	foreach my $repeat ("", @repeats) {
	    chdir("$dir/$cvsdate/$repeat")
		or die "Chdir to '$dir/$cvsdate/$repeat' failed: $!";

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
		my $subdir = "";
		$subdir .= "$cvsdate/" if $cvsdate;
		$subdir .= "$repeat/" if $repeat;
		$h{$host} = {
		    version   => $subdir.$version,
		    time      => $time,
		    short     => $short,
		    arch      => $arch,
		    dmesg     => -f $dmesg ? $subdir.$dmesg : undef,
		    dmesgboot => -f $dmesgboot ? $subdir.$dmesgboot : undef,
		    diff      => -f $diff ? $subdir.$diff : undef,
		    quirks    => -f $quirks ? $subdir.$quirks : undef,
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
	    foreach my $reboot (glob("reboot-*.log")) {
		my ($host) = $reboot =~ m,reboot-(.*)\.log,;
		$h{$host}{reboot} = "$cvsdate/$repeat/$reboot",
	    }
	    if ($repeat) {
		$d{$date}{$cvsdate}{$repeat}{host} = \%h;
	    } elsif ($cvsdate) {
		$d{$date}{$cvsdate}{host} = \%h;
	    } else {
		$d{$date}{host} = \%h;
	    }
	}
    }
    chdir($dir)
	or die "Chdir to '$dir' failed: $!";
    $typename = "regress" if -f "run.log";
    $typename = "perform" if -f "step.log";

    my $h = $d{$date}{host};
    next unless keys %$h;

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
    print $html "<h1>OpenBSD $typename test machine setup</h1>\n";
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
    print $html "    <th>repeat</th>\n"
	if @cvsdates && @{$d{$date}{$cvsdates[0]}{repeats}};
    print $html "    <th>checkout</th>\n"
	if @cvsdates;
    print $html "    <th>kernel</th>\n";
    print $html "    <th>arch</th>\n";
    print $html "    <th>setup</th>\n";
    print $html "    <th colspan=\"2\">dmesg</th>\n";
    print $html "    <th>diff</th>\n";
    print $html "    <th>quirks</th>\n";
    print $html "  </tr>\n";
    foreach my $cvsdate ("", @cvsdates) {
	$h = $d{$date}{$cvsdate}{host} if $cvsdate;
	my @repeats = $cvsdate ? @{$d{$date}{$cvsdate}{repeats}} : ();
	foreach my $repeat ("", @repeats) {
	    $h = $d{$date}{$cvsdate}{$repeat}{host} if $repeat;
	    foreach my $host (sort keys %$h) {
		print $html "  <tr>\n    <th>$host</th>\n";
		if ($repeat) {
		    print $html "    <td>$repeat</td>\n";
		} elsif (@cvsdates && @{$d{$date}{$cvsdates[0]}{repeats}}) {
		    print $html "    <td></td>\n";
		}
		if ($cvsdate) {
		    (my $cvsshort = $cvsdate) =~ s/T.*//;
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
		my $dmesg = $h->{$host}{dmesg};
		my $dmesgboot = $h->{$host}{dmesgboot};
		my $diff = $h->{$host}{diff};
		my $quirks = $h->{$host}{quirks};
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
		print $html "  </tr>\n";
	    }
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

	my $h = $d{$date}{$cvsdate}{host};
	next unless keys %$h;
	my @repeats = @{$d{$date}{$cvsdate}{repeats}};

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
	print $html "  </tr>\n";
	foreach my $repeat ("", @repeats) {
	    $h = $d{$date}{$cvsdate}{$repeat}{host} if $repeat;
	    foreach my $host (sort keys %$h) {
		print $html "  <tr>\n    <th>$host</th>\n";
		if ($repeat) {
		    print $html "    <td>$repeat</td>\n";
		} elsif (@repeats) {
		    print $html "    <td></td>\n";
		}
		(my $cvsshort = $cvsdate) =~ s/T.*//;
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
		print $html "  </tr>\n";
	    }
	}
	print $html "</table>\n";
	print $html "</body>\n";

	print $html "</html>\n";
	close($html)
	    or die "Close 'build.html.new' after writing failed: $!";
	rename("build.html.new", "build.html")
	    or die "Rename 'build.html.new' to 'build.html' failed: $!";

	foreach my $repeat (@repeats) {
	    my $subdir = "$dir/$cvsdate/$repeat";
	    chdir($subdir)
		or die "Chdir to '$subdir' failed: $!";

	    $h = $d{$date}{$cvsdate}{$repeat}{host};
	    next unless keys %$h;

	    unlink("reboot.html.new");
	    open(my $html, '>', "reboot.html.new")
		or die "Open 'reboot.html.new' for writing failed: $!";
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
	    print $html "  </tr>\n";
	    foreach my $host (sort keys %$h) {
		print $html "  <tr>\n    <th>$host</th>\n";
		print $html "    <td>$repeat</td>\n";
		(my $cvsshort = $cvsdate) =~ s/T.*//;
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
		print $html "  </tr>\n";
	    }
	    print $html "</table>\n";
	    print $html "</body>\n";

	    print $html "</html>\n";
	    close($html)
		or die "Close 'reboot.html.new' after writing failed: $!";
	    rename("reboot.html.new", "reboot.html")
		or die "Rename 'reboot.html.new' to 'reboot.html' failed: $!";
	}
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
  <title>OpenBSD Test Run</title>
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
    my @cvsdates = @{$d{$date}{cvsdates} || []};
    foreach my $cvsdate (reverse "", @cvsdates) {
	my @repeats = $cvsdate ? @{$d{$date}{$cvsdate}{repeats} || []} : ();
	foreach my $repeat (reverse "", @repeats) {
	    my $h;
	    if ($repeat) {
		print $html "  <tr>\n    <th></th>\n";
		$h = $d{$date}{$cvsdate}{$repeat}{host};
	    } elsif ($cvsdate) {
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
		my $time = encode_entities($repeat || $cvsdate ||
		    $h->{$host}{time}) || "";
		my $setup = $h->{$host}{setup} || $h->{$host}{build} ||
		    $h->{$host}{reboot} || "";
		$time ||= "log" if $setup;
		my $log = "$date/$setup";
		my $href = $setup ? "<a href=\"$log\">" : "";
		my $enda = $href ? "</a>" : "";
		print $html "    <td>$href$time$enda</td>\n";
	    }
	    print $html "  </tr>\n";
	}
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
