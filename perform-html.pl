#!/usr/bin/perl
# convert all performance results to a html table

# Copyright (c) 2018 Alexander Bluhm <bluhm@genua.de>
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
use List::Util qw(max);
use POSIX;
use URI::Escape;

my $now = strftime("%FT%TZ", gmtime);

my %opts;
getopts('h:l', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-l] [-h host]
    -h host     user and host for version information, user defaults to root
    -l		create latest.html with one column of the latest results
EOF
    exit(2);
};

my $dir = dirname($0). "/..";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";
my $performdir = getcwd();
$dir = "results";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";

my ($user, $host) = split('@', $opts{h} || "", 2);
($user, $host) = ("root", $user) unless $host;

my @results;
if ($opts{l}) {
    my @latest;
    if ($host) {
	@latest = glob("latest-$host/*/test.result");
	-f $latest[0]
	    or die "No latest test.result for $host";
    } else {
	@latest = glob("latest-*/*/test.result");
    }
    @results = map { (readlink(dirname(dirname($_)))
	or die "Readlink latest '$_' failed: $!") . "/".
	    basename(dirname($_))."/test.result" } @latest;
} else {
    @results = sort glob("*/*/test.result");
}

my (%t, %d, %v);
foreach my $result (@results) {

    # parse result file
    my ($date, $short, $cvsdate, $cvsshort) =
	$result =~ m,((.+)T.+)/((.+)T.+)/test.result,
	or next;
    $d{$date}{short} = $short;
    push @{$d{$date}{cvsdates} ||= []}, $cvsdate;
    $d{$date}{$cvsdate} = {
	cvsshort => $cvsshort,
	result => $result,
    };
    $d{$date}{log} = "step.log" if -f "$date/step.log";
    $d{$date}{setup} = "$date/setup.html" if -f "$date/setup.html";
    $d{$date}{$cvsdate}{build} = "$date/$cvsdate/build.html"
	if -f "$date/$cvsdate/build.html";
    $_->{severity} *= .5 foreach values %t;
    my ($total, $pass) = (0, 0);
    open(my $fh, '<', $result)
	or die "Open '$result' for reading failed: $!";
    my @values;
    while (<$fh>) {
	chomp;
	my ($status, $test, $message) = split(" ", $_, 3);
	if ($status =~ /VALUE/) {
	    next if $status =~ /SUBVALUE/;  # XXX not yet
	    my (undef, $number, $unit, $name) = split(" ", $_, 4);
	    $number =~ /^(\d+|\d*\.\d+)$/
		or warn "Number '$number' for value '$name' is invalid";
	    push @values, {
		name => $name || "",
		unit => $unit,
		number => $number,
	    };
	    next;
	}
	$v{$date}{$test}{$cvsdate} = [ @values ];
	undef @values;
	$t{$test}{$date}{$cvsdate}
	    and warn "Duplicate test '$test' date '$date' cvsdate '$cvsdate'";
	$t{$test}{$date}{$cvsdate} = {
	    status => $status,
	    message => $message,
	};
	my $severity =
	    $status eq 'PASS'   ? 1 :
	    $status eq 'SKIP'   ? 2 :
	    $status eq 'FAIL'   ? 5 :
	    $status eq 'NOEXIT' ? 6 :
	    $status eq 'NOTERM' ? 7 :
	    $status eq 'NORUN'  ? 8 : 10;
	if (($t{$test}{$date}{severity} || 0 ) < $severity) {
		$t{$test}{$date}{status} = $status;
		$t{$test}{$date}{severity} = $severity;
	}
	$t{$test}{severity} += $severity;
	$total++ unless $status eq 'SKIP';
	$pass++ if $status eq 'PASS';
	my $logfile = dirname($result). "/logs/$test.log";
	$t{$test}{$date}{$cvsdate}{logfile} = $logfile if -f $logfile;
    }
    close($fh)
	or die "Close '$result' after reading failed: $!";
    $d{$date}{$cvsdate}{pass} = $pass / $total if $total;

    # parse version file
    my ($version, $diff, $dmesg, $quirks);
    if ($host) {
	$version = "$date/$cvsdate/version-$host.txt";
	$diff = "$date/$cvsdate/diff-$host.txt";
	$dmesg = "$date/$cvsdate/dmesg-$host.txt";
	$quirks = "$date/$cvsdate/quirks-$host.txt";
    } else {
	$version = (glob("$date/$cvsdate/version-*.txt"))[0];
	($diff = $version) =~ s,/version-,/diff-,;
	($dmesg = $version) =~ s,/version-,/dmesg-,;
	($quirks = $version) =~ s,/version-,/quirks-,;
    }
    unless (-f $version) {
	# if host is specified, only print result for this one
	delete $d{$date}{$cvsdate} if $host;
	next;
    }
    ($d{$date}{$cvsdate}{version} = $version) =~ s,[^/]+/,,;
    open($fh, '<', $version)
	or die "Open '$version' for reading failed: $!";
    while (<$fh>) {
	if (/^kern.version=(.*(?:cvs : (\w+))?: (\w+ \w+ +\d+ .*))$/) {
	    $d{$date}{$cvsdate}{kernel} = $1;
	    $d{$date}{$cvsdate}{cvs} = $2;
	    $d{$date}{$cvsdate}{time} = $3;
	    <$fh> =~ /(\S+)/;
	    $d{$date}{$cvsdate}{kernel} .= "\n    $1";
	    $d{$date}{$cvsdate}{location} = $1;
	}
	if (/^hw.machine=(\w+)$/) {
	    $d{$date}{arch} ||= $1;
	    $d{$date}{$cvsdate}{arch} = $1;
	}
    }
    ($d{$date}{$cvsdate}{diff} = $diff) =~ s,[^/]+/,, if -f $diff;
    ($d{$date}{$cvsdate}{dmesg} = $dmesg) =~ s,[^/]+/,, if -f $dmesg;
    ($d{$date}{$cvsdate}{quirks} = $quirks) =~ s,[^/]+/,, if -f $quirks;
}

my @dates = reverse sort keys %d;

# html per date with cvsdate

foreach my $date (@dates) {
    my $htmlfile = "$date/perform.html";
    unlink("$htmlfile.new");
    open(my $html, '>', "$htmlfile.new")
	or die "Open '$htmlfile.new' for writing failed: $!";

    my $short = $d{$date}{short};
    print $html <<"HEADER";
<!DOCTYPE html>
<html>

<head>
  <title>OpenBSD Perform Date Results</title>
  <style>
    th { text-align: left; white-space: nowrap; }
    tr:hover {background-color: #e0e0e0}
    td.PASS {background-color: #80ff80;}
    td.FAIL {background-color: #ff8080;}
    td.SKIP {background-color: #8080ff;}
    td.NOEXIT, td.NOTERM, td.NORUN {background-color: #ffff80;}
    td.NOLOG, td.NOCLEAN, td.NOEXIST {background-color: #ffffff;}
    td.result, td.result a {color: black;}
  </style>
</head>

<body>
<h1>OpenBSD perform $short test results</h1>
<table>
  <tr>
    <th>created at</th>
    <td>$now</td>
  </tr>
  <tr>
    <th>run at</th>
    <td>$date</td>
  </tr>
HEADER

    print $html "  <tr>\n    <th>run</th>\n";
    my $log = $d{$date}{log};
    my $href = $log ? "<a href=\"$log\">" : "";
    my $enda = $href ? "</a>" : "";
    print $html "    <th>${href}log$enda</th>\n";
    print $html "  </tr>\n";
    print $html "</table>\n";

    print $html "<table>\n";
    my @cvsdates = @{$d{$date}{cvsdates}};

    print $html "  <tr>\n    <th>run at cvs checkout</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $cvsshort = $d{$date}{$cvsdate}{cvsshort};
	my $build = $d{$date}{$cvsdate}{build};
	$build =~ s,[^/]+/,, if $build;
	my $time = encode_entities($cvsdate);
	my $href = $build ? "<a href=\"$build\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html "    <th title=\"$time\">$href$cvsshort$enda</th>\n";
    }
    print $html "  <tr>\n    <th>kernel build</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $version = $d{$date}{$cvsdate}{version};
	unless ($version) {
	    print $html "    <th/>\n";
	    next;
	}
	my $kernel = encode_entities($d{$date}{$cvsdate}{kernel});
	print $html "    <th title=\"$kernel\">".
	    "<a href=\"$version\">version</a></th>\n";
    }
    print $html "  <tr>\n    <th>build quirks</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $quirks = $d{$date}{$cvsdate}{quirks};
	unless ($quirks) {
	    print $html "    <th/>\n";
	    next;
	}
	print $html "    <th><a href=\"$quirks\">quirks<a></th>\n";
    }
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>dmesg after run</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $arch = $d{$date}{$cvsdate}{arch} || "dmesg";
	my $dmesg = $d{$date}{$cvsdate}{dmesg};
	my $href = $dmesg ? "<a href=\"$dmesg\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html "    <th>$href$arch$enda</th>\n";
    }
    print $html "  </tr>\n";
    my @tests = sort keys %t;
    foreach my $test (@tests) {
	my $td = $t{$test}{$date} or next;
	print $html "  <tr>\n    <th>$test</th>\n";
	foreach my $cvsdate (@cvsdates) {
	    my $status = $td->{$cvsdate}{status} || "";
	    my $class = " class=\"result $status\"";
	    my $message = encode_entities($td->{$cvsdate}{message});
	    my $title = $message ? " title=\"$message\"" : "";
	    my $logfile = $td->{$cvsdate}{logfile};
	    my $href = $logfile ? "<a href=\"../$logfile\">" : "";
	    my $enda = $href ? "</a>" : "";
	    print $html "    <td$class$title>$href$status$enda</td>\n";
	}
	print $html "  </tr>\n";
	my $vt = $v{$date}{$test};
	my $maxval = max map { scalar @{$vt->{$_}} } @cvsdates;
	for (my $i = 0; $i < $maxval; $i++) {
	    my $value0 = $vt->{$cvsdates[0]}[$i];
	    my ($name0, $unit0) = ($value0->{name}, $value0->{unit});
	    print $html "  <tr>\n    <th>$name0</th>\n";
	    foreach my $cvsdate (@cvsdates) {
		my $status = $td->{$cvsdate}{status};
		my $value = $vt->{$cvsdate}[$i];
		my $number = $status eq 'PASS' ?
		    $vt->{$cvsdate}[$i]{number} : "";
		print $html "    <td>$number</td>\n";
	    }
	    print $html "    <th>$unit0</th>\n";
	    print $html "  </tr>\n";
	}
    }
    print $html "</table>\n";

    print $html <<"FOOTER";
</body>
</html>
FOOTER

    close($html)
	or die "Close '$htmlfile.new' after writing failed: $!";
    rename("$htmlfile.new", "$htmlfile")
	or die "Rename '$htmlfile.new' to '$htmlfile' failed: $!";

    system("gzip -f -c $htmlfile >$htmlfile.gz.new")
	and die "gzip $htmlfile failed: $?";
    rename("$htmlfile.gz.new", "$htmlfile.gz")
	or die "Rename '$htmlfile.new.gz' to '$htmlfile.gz' failed: $!";
}

# html with date

my $htmlfile = $opts{l} ? "latest" : "perform";
$htmlfile .= "-$host" if $host;
$htmlfile .= ".html";
unlink("$htmlfile.new");
open(my $html, '>', "$htmlfile.new")
    or die "Open '$htmlfile.new' for writing failed: $!";
my $htmltitle = $opts{l} ? "Latest" : "Test";
my $bodytitle = $host ? ($opts{l} ? "latest $host" : $host) :
    ($opts{l} ? "latest" : "all");

print $html <<"HEADER";
<!DOCTYPE html>
<html>

<head>
  <title>OpenBSD Perform $htmltitle Results</title>
  <style>
    th { text-align: left; white-space: nowrap; }
    tr:hover {background-color: #e0e0e0}
    td.PASS {background-color: #80ff80;}
    td.FAIL {background-color: #ff8080;}
    td.SKIP {background-color: #8080ff;}
    td.NOEXIT, td.NOTERM, td.NORUN {background-color: #ffff80;}
    td.NOLOG, td.NOCLEAN, td.NOEXIST {background-color: #ffffff;}
    td.result, td.result a {color: black;}
  </style>
</head>

<body>
<h1>OpenBSD perform $bodytitle test results</h1>
<table>
  <tr>
    <th>created at</th>
    <td>$now</td>
  </tr>
  <tr>
    <th>test</th>
    <td><a href=\"run.html\">run</a></td>
  </tr>
</table>
HEADER

print $html "<table>\n";
print $html "  <tr>\n    <th>run at date</th>\n";
foreach my $date (@dates) {
    my $short = $d{$date}{short};
    my $setup = $d{$date}{setup};
    my $time = encode_entities($date);
    my $href = $setup ? "<a href=\"$setup\">" : "";
    my $enda = $href ? "</a>" : "";
    print $html "    <th title=\"$time\">$href$short$enda</th>\n";
}
print $html "  <tr>\n    <th>first cvs checkout</th>\n";
foreach my $date (@dates) {
    my $cvsdate = (sort @{$d{$date}{cvsdates}})[0];
    my $cvsshort = $d{$date}{$cvsdate}{cvsshort};
    my $time = encode_entities($cvsdate);
    print $html "    <th title=\"$time\">$cvsshort</th>\n";
}
print $html "  <tr>\n    <th>last cvs checkout</th>\n";
foreach my $date (@dates) {
    my $cvsdate = (sort @{$d{$date}{cvsdates}})[-1];
    my $cvsshort = $d{$date}{$cvsdate}{cvsshort};
    my $time = encode_entities($cvsdate);
    print $html "    <th title=\"$time\">$cvsshort</th>\n";
}
print $html "  <tr>\n    <th>checkout steps</th>\n";
foreach my $date (@dates) {
    my $total = @{$d{$date}{cvsdates}};
    print $html "    <th>$total</th>\n";
}
print $html "  </tr>\n";

my @tests = sort { $t{$b}{severity} <=> $t{$a}{severity} || $a cmp $b }
    keys %t;
foreach my $test (@tests) {
    print $html "  <tr>\n    <th>$test</th>\n";
    foreach my $date (@dates) {
	my $status = $t{$test}{$date}{status} || "";
	my $class = " class=\"result $status\"";
	my $message = encode_entities($t{$test}{$date}{message});
	my $title = $message ? " title=\"$message\"" : "";
	my $datehtml = "$date/perform.html";
	my $href = -f $datehtml ? "<a href=\"$datehtml\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html "    <td$class$title>$href$status$enda</td>\n";
    }
    print $html "  </tr>\n";
}
print $html "</table>\n";

print $html <<"FOOTER";
<table>
  <tr>
    <th>PASS</th>
    <td>performance test passed</td>
  </tr>
  <tr>
    <th>FAIL</th>
    <td>performance test failed to produce value</td>
  </tr>
  <tr>
    <th>NOEXIT</th>
    <td>performance test did not exit with code 0</td>
  </tr>
  <tr>
    <th>NOTERM</th>
    <td>performance test did not terminate, aborted after timeout</td>
  </tr>
  <tr>
    <th>NORUN</th>
    <td>performance test did not run, execute test failed</td>
  </tr>
  <tr>
    <th>NOLOG</th>
    <td>create log file for test output failed</td>
  </tr>
</table>
</body>
</html>
FOOTER

close($html)
    or die "Close '$htmlfile.new' after writing failed: $!";
rename("$htmlfile.new", "$htmlfile")
    or die "Rename '$htmlfile.new' to '$htmlfile' failed: $!";

system("gzip -f -c $htmlfile >$htmlfile.gz.new")
    and die "gzip $htmlfile failed: $?";
rename("$htmlfile.gz.new", "$htmlfile.gz")
    or die "Rename '$htmlfile.new.gz' to '$htmlfile.gz' failed: $!";
