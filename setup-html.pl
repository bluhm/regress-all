#!/usr/bin/perl
# convert test setup details to a html table

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
    print STDERR "usage: $0 -d date\n";
    exit(2);
};

my $dir = dirname($0). "/..";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";
my $regressdir = getcwd();
$dir = "results";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";

my @dates = $opts{d} || grep { m/T/ } map { dirname($_) } glob("*/run.log");
my (%d, %m);
foreach my $date (@dates) {
    $dir = "$regressdir/results/$date";
    chdir($dir)
	or die "Chdir to '$dir' failed: $!";

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
	$h{$host} = {
	    version   => $version,
	    time      => $time,
	    short     => $short,
	    arch      => $arch,
	    dmesg     => -f $dmesg ? $dmesg : undef,
	    dmesgboot => -f $dmesgboot ? $dmesgboot : undef,
	};
	$m{$host}++;
    }
    foreach my $setup (glob("setup-*.log")) {
	my ($host) = $setup =~ m,setup-(.*)\.log,;
	$h{$host}{setup} = $setup,
    }
    $d{$date}{host} = \%h;

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
    print $html "<h1>OpenBSD regress test machine</h1>\n";
    print $html "<table>\n";
    print $html "  <tr>\n    <th>created at</th>\n";
    print $html "    <td>$now</td>\n";
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>run at</th>\n";
    print $html "    <td>$date</td>\n";
    print $html "  </tr>\n";
    if (-f "run.log") {
	$d{$date}{run} = "run.log";
	print $html "  <tr>\n    <th>run</th>\n";
	print $html "    <td><a href=\"run.log\">log</a></td>\n";
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
    print $html "    <th>version</th>\n";
    print $html "    <th>arch</th>\n";
    print $html "    <th>setup</th>\n";
    print $html "    <th colspan=\"2\">dmesg</th>\n";
    print $html "  </tr>\n";

    foreach my $host (sort keys %h) {
	print $html "  <tr>\n    <th>$host</th>\n";
	my $version = uri_escape($h{$host}{version});
	my $time = encode_entities($h{$host}{time});
	my $short = $h{$host}{short};
	my $arch = encode_entities($h{$host}{arch}) || "";
	my $setup = uri_escape($h{$host}{setup});
	my $dmesg = uri_escape($h{$host}{dmesg});
	my $dmesgboot = uri_escape($h{$host}{dmesgboot});
	if ($version) {
	    print $html "    <td title=\"$time\">".
		"<a href=\"$version\">$short</a></td>\n";
	} else {
	    print $html "    <td></td>\n";
	}
	print $html "    <td>$arch</td>\n";
	if ($setup) {
	    print $html "    <td><a href=\"$setup\">log</a></td>\n";
	} else {
	    print $html "    <td></td>\n";
	}
	if ($dmesgboot) {
	    print $html "    <td><a href=\"$dmesgboot\">boot</a></td>\n";
	} else {
	    print $html "    <td></td>\n";
	}
	if ($dmesg) {
	    print $html "    <td><a href=\"$dmesg\">run</a></td>\n";
	} else {
	    print $html "    <td></td>\n";
	}
	print $html "  </tr>\n";
    }
    print $html "</table>\n";
    print $html "</body>\n";

    print $html "</html>\n";
    close($html)
	or die "Close 'setup.html.new' after writing failed: $!";
    rename("setup.html.new", "setup.html")
	or die "Rename 'setup.html.new' to 'setup.html' failed: $!";
}

exit if $opts{d};

$dir = "$regressdir/results";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";

unlink("run.html.new");
open(my $html, '>', "run.html.new")
    or die "Open 'run.html.new' for writing failed: $!";
print $html "<!DOCTYPE html>\n";
print $html "<html>\n";
print $html "<head>\n";
print $html "  <title>OpenBSD Regress Run</title>\n";
print $html "  <style>th { text-align: left; }</style>\n";
print $html "</head>\n";

print $html "<body>\n";
print $html "<h1>OpenBSD regress test run</h1>\n";
print $html "<table>\n";
print $html "  <tr>\n    <th>created at</th>\n";
print $html "    <td>$now</td>\n";
print $html "  </tr>\n";
print $html "</table>\n";

print $html "<table>\n";
print $html "  <tr>\n    <th>run log</th>\n";
foreach my $host (sort keys %m) {
    print $html "    <th>$host setup log</th>\n";
}
print $html "  </tr>\n";

foreach my $date (reverse sort keys %d) {
    my $run = $d{$date}{run} || "";
    my $log = uri_escape($date). "/$run";
    my $href = $run ? "<a href=\"$log\">" : "";
    my $enda = $href ? "</a>" : "";
    print $html "  <tr>\n    <th>$href$date$enda</th>\n";
    my $h = $d{$date}{host};
    foreach my $host (sort keys %m) {
	my $time = encode_entities($h->{$host}{time}) || "";
	my $setup = uri_escape($h->{$host}{setup}) || "";
	$time ||= "log" if $setup;
	$log = uri_escape($date). "/$setup";
	$href = $setup ? "<a href=\"$log\">" : "";
	$enda = $href ? "</a>" : "";
	print $html "    <td>$href$time$enda</td>\n";
    }
    print $html "  </tr>\n";
}
print $html "</table>\n";
print $html "</body>\n";

print $html "</html>\n";
close($html)
    or die "Close 'run.html.new' after writing failed: $!";
rename("run.html.new", "run.html")
    or die "Rename 'run.html.new' to 'run.html' failed: $!";
