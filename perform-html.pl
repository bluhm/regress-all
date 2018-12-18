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
use Date::Parse;
use Errno;
use File::Basename;
use HTML::Entities;
use Getopt::Std;
use List::Util qw(first max min sum);
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
	@latest = (glob("latest-$host/*/test.result"),
	    glob("latest-$host/*/*/test.result"));
	-f $latest[0]
	    or die "No latest test.result for $host";
    } else {
	@latest = (glob("latest-*/*/test.result"),
	    glob("latest-*/*/*/test.result"));
    }
    foreach (@latest) {
	my ($ldir, $res) = split("/", $_, 2);
	my $date = readlink($ldir)
	    or die "Readlink latest '$ldir' failed: $!";
	$_ = "$date/$res";
    }
    @results = sort @latest;
} else {
    # cvs checkout and repeated results
    @results = sort(glob("*/*/test.result"), glob("*/*/*/test.result"));
}

my (%t, %d, %v);
foreach my $result (@results) {

    # parse result file
    my ($date, $short, $cvsdate, $cvsshort, $repeat) =
	$result =~ m,(([^/]+)T[^/]+)/(([^/]+)T[^/]+)/(?:(\d+)/)?test.result,
	or next;
    $d{$date}{short} ||= $short;
    push @{$d{$date}{cvsdates} ||= []}, $cvsdate unless $d{$date}{$cvsdate};
    $d{$date}{$cvsdate}{cvsshort} ||= $cvsshort;
    if (defined $repeat) {
	push @{$d{$date}{$cvsdate}{repeats} ||= []}, $repeat;
	$d{$date}{$cvsdate}{repeat}{$result} = $result;
    } else {
	$d{$date}{$cvsdate}{$result} = $result;
    }
    $d{$date}{log} ||= "step.log" if -f "$date/step.log";
    unless ($d{$date}{stepconf}) {
	my $stepfile = "$date/stepconf.txt";
	if (open (my $fh, '<', $stepfile)) {
	    while (<$fh>) {
		chomp;
		my ($k, $v) = split(/\s+/, $_, 2);
		$d{$date}{stepconf}{lc($k)} = $v;
	    }
	} else {
	    $!{ENOENT}
		or die "Open '$stepfile' for reading failed: $!";
	}
    }
    $d{$date}{setup} ||= "$date/setup.html" if -f "$date/setup.html";
    $d{$date}{$cvsdate}{build} ||= "$date/$cvsdate/build.html"
	if -f "$date/$cvsdate/build.html";
    if (defined $repeat) {
	$d{$date}{$cvsdate}{$repeat}{reboot} ||=
	    "$date/$cvsdate/$repeat/reboot.html"
	    if -f "$date/$cvsdate/$repeat/reboot.html";
    }
    $_->{severity} *= .5 foreach values %t;
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
	my $severity =
	    $status eq 'PASS'   ? 1 :
	    $status eq 'SKIP'   ? 2 :
	    $status eq 'FAIL'   ? 5 :
	    $status eq 'NOEXIT' ? 6 :
	    $status eq 'NOTERM' ? 7 :
	    $status eq 'NORUN'  ? 8 : 10;
	if (defined $repeat) {
	    $v{$date}{$test}{$cvsdate}{$repeat} = [ @values ];
	    $t{$test}{$date}{$cvsdate}{$repeat}
		and warn "Duplicate test '$test' date '$date' ".
		    "cvsdate '$cvsdate' repeat '$repeat'";
	    $t{$test}{$date}{$cvsdate}{$repeat} = {
		status => $status,
		message => $message,
	    };
	    if (($t{$test}{$date}{$cvsdate}{severity} || 0 ) < $severity) {
		$t{$test}{$date}{$cvsdate}{status} = $status;
		$t{$test}{$date}{$cvsdate}{severity} = $severity;
	    }
	} else {
	    $v{$date}{$test}{$cvsdate} = [ @values ];
	    $t{$test}{$date}{$cvsdate}
		and warn "Duplicate test '$test' date '$date' ".
		    "cvsdate '$cvsdate'";
	    $t{$test}{$date}{$cvsdate} = {
		status => $status,
		message => $message,
	    };
	}
	undef @values;
	if (($t{$test}{$date}{severity} || 0 ) < $severity) {
	    $t{$test}{$date}{status} = $status;
	    $t{$test}{$date}{severity} = $severity;
	}
	$t{$test}{severity} += $severity;
    }
    close($fh)
	or die "Close '$result' after reading failed: $!";

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

# write test results into gnuplot data file

my %testplot = (
    "iperf3_-c10.3.0.33_-w1m"				=> "tcp",
    "iperf3_-c10.3.0.33_-w1m_-t60"			=> "tcp",
    "iperf3_-c10.3.0.33_-w1m_-R"			=> "tcp",
    "iperf3_-c10.3.0.33_-w1m_-t60_-R"			=> "tcp",
    "tcpbench_-S1000000_-t10_10.3.0.33"			=> "tcp",
    "tcpbench_-S1000000_-t60_10.3.0.33"			=> "tcp",
    "tcpbench_-S1000000_-t10_-n100_10.3.0.33"		=> "tcp",
    "tcpbench_-S1000000_-t60_-n100_10.3.0.33"		=> "tcp",
    "iperf3_-c10.3.0.33_-u_-b0_-w1m"			=> "udp",
    "iperf3_-c10.3.0.33_-u_-b0_-w1m_-t60"		=> "udp",
    "iperf3_-c10.3.0.33_-u_-b0_-w1m_-R"			=> "udp",
    "iperf3_-c10.3.0.33_-u_-b0_-w1m_-t60_-R"		=> "udp",
    "time_-lp_make_-CGENERIC.MP_-j8_-s"			=> "make",
);

unless ($opts{l} || $opts{h}) {
    -d "gnuplot" || mkdir "gnuplot"
	or die "Create directory 'gnuplot' failed: $!";
    my $testdata = "gnuplot/test";
    my %plotfh;
    @plotfh{values %testplot} = ();
    foreach my $plot (keys %plotfh) {
	open($plotfh{$plot}, '>', "$testdata-$plot.data.new")
	    or die "Open '$testdata-$plot.data.new' for writing failed: $!";
	print {$plotfh{$plot}}
	    "# test subtest run checkout repeat value unit\n";
    }
    open(my $fh, '>', "$testdata.data.new")
	or die "Open '$testdata.data.new' for writing failed: $!";
    print $fh "# test subtest run checkout repeat value unit\n";
    foreach my $date (sort keys %v) {
	my $vd = $v{$date};
	my $run = str2time($date);
	foreach my $test (sort keys %$vd) {
	    my $vt = $vd->{$test};
	    foreach my $cvsdate (sort keys %$vt) {
		my $vc = $vt->{$cvsdate};
		my $checkout = str2time($cvsdate);
		$vc = { 0 => $vc } if ref $vc ne 'HASH';
		foreach my $repeat (sort keys %$vc) {
		    my $vr = $vc->{$repeat};
		    foreach my $value (@{$vr || []}) {
			my $number = $value->{number};
			my $unit = $value->{unit};
			my $subtest = $value->{name} || "unknown";
			print $fh "$test $subtest ".
			    "$run $checkout $repeat $number $unit\n";
			print {$plotfh{$testplot{$test}}} "$test $subtest ".
			    "$run $checkout $repeat $number $unit\n"
			    if $testplot{$test};
		    }
		}
	    }
	}
    }
    close($fh)
	or die "Close '$testdata.data.new' after writing failed: $!";
    rename("$testdata.data.new", "$testdata.data")
	or die "Rename '$testdata.data.new' to '$testdata.data' failed: $!";
    foreach my $plot (keys %plotfh) {
	my $datafile = "$testdata-$plot.data";
	close($plotfh{$plot})
	    or die "Close '$datafile.new' after writing failed: $!";
	rename("$datafile.new", $datafile)
	    or die "Rename '$datafile.new' to '$datafile' failed: $!";
    }
}

# create gnuplot graphs for all runs

foreach my $date (keys %v) {
    foreach my $plot (qw(make tcp udp)) {
	my $outfile = "$date-$plot.svg";
	unless (-f "gnuplot/$outfile") {
	    my @cmd = ("$performdir/bin/gnuplot.pl", "-D", $date,
		"-T", "$plot");
	    system(@cmd)
		and die "Command '@cmd' failed: $?";
	}
    }
}

# create cvs log file with commits after previous cvsdates

foreach my $dd (values %d) {
    my %cvsdates;
    @cvsdates{@{$dd->{cvsdates}}} = ();
    @{$dd->{cvsdates}} = sort keys %cvsdates;
    my $cvsprev;
    foreach my $cvsdate (@{$dd->{cvsdates}}) {
	if ($cvsprev) {
	    my $cvslog = "cvslog/src/sys/$cvsprev--$cvsdate";
	    unless (-f "$cvslog.txt") {
		my @cmd = ("$performdir/bin/cvslog.pl",
		    "-B", $cvsprev, "-E", $cvsdate, "-P", "src/sys");
		system(@cmd)
		    and die "Command '@cmd' failed: $?";
	    }
	    if (open (my $fh, '<', "$cvslog.txt")) {
		$dd->{$cvsdate}{cvslog} = "$cvslog.txt";
		$dd->{$cvsdate}{cvscommits} = 0;
		while (<$fh>) {
		    chomp;
		    my ($k, @v) = split(/\s+/)
			or next;
		    $dd->{$cvsdate}{cvscommits}++ if $k eq 'DATE';
		    push @{$dd->{$cvsdate}{cvsfiles}}, @v if $k eq 'FILES';
		}
	    } else {
		$!{ENOENT}
		    or die "Open '$cvslog.txt' for reading failed: $!";
	    }
	    if (-f "$cvslog.html") {
		# If html is available, use its niceer display in link.
		$dd->{$cvsdate}{cvslog} = "$cvslog.html";
	    }
	}
	$cvsprev = $cvsdate;
    }
}

my %testorder = (
    "iperf3_-c10.3.0.33_-w1m"				=> 111,
    "iperf3_-c10.3.0.33_-w1m_-t60"			=> 112,
    "iperf3_-c10.3.0.33_-w1m_-R"			=> 121,
    "iperf3_-c10.3.0.33_-w1m_-t60_-R"			=> 122,
    "tcpbench_-S1000000_-t10_10.3.0.33"			=> 211,
    "tcpbench_-S1000000_-t60_10.3.0.33"			=> 212,
    "tcpbench_-S1000000_-t10_-n100_10.3.0.33"		=> 221,
    "tcpbench_-S1000000_-t60_-n100_10.3.0.33"		=> 222,
    "iperf3_-c10.3.0.33_-u_-b0_-w1m"			=> 311,
    "iperf3_-c10.3.0.33_-u_-b0_-w1m_-t60"		=> 312,
    "iperf3_-c10.3.0.33_-u_-b0_-w1m_-R"			=> 321,
    "iperf3_-c10.3.0.33_-u_-b0_-w1m_-t60_-R"		=> 322,
    "time_-lp_make_-CGENERIC.MP_-j8_-s"			=> 400,
);
my @tests = reverse sort { $testorder{$b} <=> $testorder{$a} } keys %t;
my @dates = reverse sort keys %d;

# html per date per cvsdate with repetitions

foreach my $date (@dates) {
    my $short = $d{$date}{short};
    foreach my $cvsdate (@{$d{$date}{cvsdates}}) {
	my $cvsshort = $d{$date}{$cvsdate}{cvsshort};
	my @repeats = sort @{$d{$date}{$cvsdate}{repeats} || []}
	    or next;

	my $htmlfile = "$date/$cvsdate/perform.html";
	unlink("$htmlfile.new");
	open(my $html, '>', "$htmlfile.new")
	    or die "Open '$htmlfile.new' for writing failed: $!";

	print $html <<"HEADER";
<!DOCTYPE html>
<html>

<head>
  <title>OpenBSD Perform CVS Date Results</title>
  <style>
    th { text-align: left; white-space: nowrap; }
    tr:hover {background-color: #e0e0e0}
    td.PASS {background-color: #80ff80;}
    td.FAIL {background-color: #ff8080;}
    td.SKIP {background-color: #8080ff;}
    td.NOEXIT, td.NOTERM, td.NORUN {background-color: #ffff80;}
    td.NOLOG, td.NOCLEAN, td.NOEXIST {background-color: #ffffff;}
    td.result, td.result a {color: black;}
    td.outlier {color: red;}
  </style>
</head>

<body>
<h1>OpenBSD perform $short cvs $cvsshort test results</h1>
<table>
  <tr>
    <th>created at</th>
    <td>$now</td>
  </tr>
  <tr>
    <th>run at</th>
    <td>$date</td>
  </tr>
  <tr>
    <th>cvs checkout at</th>
    <td>$cvsdate</td>
  </tr>
HEADER

	print $html "  <tr>\n    <th>repetitions</th>\n";
	my $repmode = $d{$date}{stepconf}{repmodes};
	my $reptext = @repeats && $repmode && @repeats > 1 ?
	    @repeats. " / $repmode" : @repeats;
	$reptext =~ s/\s//g;
	print $html "    <td>$reptext</td>\n";
	print $html "  </tr>\n";
	print $html "</table>\n";

	print $html "<table>\n";
	print $html "  <tr>\n    <th>repeat</th>\n";
	foreach my $repeat (@repeats) {
	    print $html "    <th>$repeat</th>\n";
	}
	print $html "    <th></th><th></th><th></th><th></th><th></th>".
	    "<th></th>\n";  # dummy for unit and stats below
	print $html "  </tr>\n";
	print $html "  <tr>\n    <th>machine</th>\n";
	foreach my $repeat (@repeats) {
	    if ($repmode) {
		my $reboot = $d{$date}{$cvsdate}{$repeat}{reboot};
		$reboot =~ s,[^/]+/[^/]+/,, if $reboot;
		my $link = uri_escape($reboot, "^A-Za-z0-9\-\._~/");
		my $href = $reboot ? "<a href=\"$link\">" : "";
		my $enda = $href ? "</a>" : "";
		print $html "    <th>$href$repmode$enda</th>\n";
	    } else {
		print $html "    <th></th>\n";
	    }
	}
	print $html "    <th></th><th></th><th></th><th></th><th></th>".
	    "<th></th>\n";  # dummy for unit and stats below
	print $html "  </tr>\n";
	foreach my $test (@tests) {
	    my $td = $t{$test}{$date} && $t{$test}{$date}{$cvsdate}
		or next;
	    print $html "  <tr>\n    <th>$test</th>\n";
	    foreach my $repeat (@repeats) {
		my $status = $td->{$repeat}{status} || "";
		my $class = " class=\"result $status\"";
		my $message = encode_entities($td->{$repeat}{message});
		my $title = $message ? " title=\"$message\"" : "";
		my $logfile = "$repeat/logs/$test.log";
		my $link = uri_escape($logfile, "^A-Za-z0-9\-\._~/");
		my $href = -f "$date/$cvsdate/$logfile" ?
		    "<a href=\"$link\">" : "";
		my $enda = $href ? "</a>" : "";
		print $html "    <td$class$title>$href$status$enda</td>\n";
	    }
	    foreach my $stat (qw(unit mean minimum maximum deviation relative))
	    {
		print $html "    <th>$stat</th>\n";
	    }
	    print $html "  </tr>\n";
	    my $vt = $v{$date}{$test}{$cvsdate};
	    my $maxval = max map { scalar @{$vt->{$_}} } @repeats;
	    for (my $i = 0; $i < $maxval; $i++) {
		my $value0 = first { $_ } map { $vt->{$_}[$i] } @repeats;
		my ($name0, $unit0) = ($value0->{name}, $value0->{unit});
		print $html "  <tr>\n    <th>$name0</th>\n";
		my @numbers = map { $vt->{$_}[$i]{number} }
		    grep { $td->{$_}{status} eq 'PASS' } @repeats;
		my ($sum, $mean, $maximum, $minimum, $deviation, $relative,
		    $summary, $outlier);
		if (@numbers) {
		    $sum = sum(@numbers);
		    $mean = $sum / @numbers;
		    $minimum = min @numbers;
		    $maximum = max @numbers;
		    my $variance = 0;
		    foreach my $number (@numbers) {
			my $diff = $number - $mean;
			$variance += $diff * $diff;
		    }
		    $variance /= @numbers;
		    $deviation = sqrt $variance;
		    $relative = $deviation / $mean;
		    $summary = $vt->{summary}[$i] =
			$unit0 eq 'bits/sec' ?  $maximum : $mean;
		    $outlier = $vt->{outlier}[$i] = abs($relative) >= 0.025;
		}
		foreach my $repeat (@repeats) {
		    my $status = $td->{$repeat}{status};
		    if ($status ne 'PASS') {
			print $html "    <td></td>\n";
			next;
		    }
		    my $number = $vt->{$repeat}[$i]{number};
		    my $reldev = ($number - $summary) / $summary;
		    my $title = " title=\"$reldev\"";
		    my $class = abs($reldev) >= 0.1 ? ' class="outlier"' : "";
		    print $html "    <td$title$class>$number</td>\n";
		}
		if (@numbers) {
		    print $html "    <td>$unit0</td>\n";
		    if ($unit0 eq 'bits/sec') {
			print $html "    <td>$mean</td>\n";
		    } else {
			print $html "    <td><em>$mean</em></td>\n";
		    }
		    print $html "    <td>$minimum</td>\n";
		    if ($unit0 eq 'bits/sec') {
			print $html "    <td><em>$maximum</em></td>\n";
		    } else {
			print $html "    <td>$maximum</td>\n";
		    }
		    print $html "    <td>$deviation</td>\n";
		    my $class = $outlier ? ' class="outlier"' : "";
		    print $html "    <td$class>$relative</td>\n";
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
	    or die "Close '$htmlfile.new' after writing failed: $!";
	rename("$htmlfile.new", "$htmlfile")
	    or die "Rename '$htmlfile.new' to '$htmlfile' failed: $!";

	system("gzip -f -c $htmlfile >$htmlfile.gz.new")
	    and die "gzip $htmlfile failed: $?";
	rename("$htmlfile.gz.new", "$htmlfile.gz")
	    or die "Rename '$htmlfile.new.gz' to '$htmlfile.gz' failed: $!";
    }
}

# html per date with cvsdate

foreach my $date (@dates) {
    my $short = $d{$date}{short};
    my @cvsdates = @{$d{$date}{cvsdates}};

    my $htmlfile = "$date/perform.html";
    unlink("$htmlfile.new");
    open(my $html, '>', "$htmlfile.new")
	or die "Open '$htmlfile.new' for writing failed: $!";

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
    td.outlier {color: red;}
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
    my $link = uri_escape($log, "^A-Za-z0-9\-\._~/");
    my $href = $log ? "<a href=\"$link\">" : "";
    my $enda = $href ? "</a>" : "";
    print $html "    <th>${href}log$enda</th>\n";
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>setup modes</th>\n";
    my $modes = $d{$date}{stepconf}{modes} || "";
    print $html "    <td>$modes</td>\n";
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>steps</th>\n";
    my $interval = $d{$date}{stepconf}{step};
    my $steptext = @cvsdates && $interval && @cvsdates > 1 ?
	@cvsdates. " / $interval" : @cvsdates || $interval;
    $steptext =~ s/\s//g;
    print $html "    <td>$steptext</td>\n";
    print $html "  </tr>\n";
    print $html "</table>\n";

    print $html "<table>\n";
    print $html "  <tr>\n    <th>cvs checkout</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $cvsshort = $d{$date}{$cvsdate}{cvsshort};
	my $time = encode_entities($cvsdate);
	my $cvsdatehtml = "$cvsdate/perform.html";
	my $link = uri_escape($cvsdatehtml, "^A-Za-z0-9\-\._~/");
	my $href = -f "$date/$cvsdatehtml" ? "<a href=\"$link\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html "    <th title=\"$time\">$href$cvsshort$enda</th>\n";
    }
    print $html "    <th></th>\n";  # dummy for unit below
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>test</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $build = $d{$date}{$cvsdate}{build};
	$build =~ s,[^/]+/,, if $build;
	my $link = uri_escape($build, "^A-Za-z0-9\-\._~/");
	my $href = $build ? "<a href=\"$link\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html "    <th>${href}build$enda</th>\n";
    }
    print $html "    <th></th>\n";  # dummy for unit below
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>kernel build</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $version = $d{$date}{$cvsdate}{version};
	unless ($version) {
	    print $html "    <th></th>\n";
	    next;
	}
	my $kernel = encode_entities($d{$date}{$cvsdate}{kernel});
	my $link = uri_escape($version, "^A-Za-z0-9\-\._~/");
	print $html "    <th title=\"$kernel\">".
	    "<a href=\"$link\">version</a></th>\n";
    }
    print $html "    <th></th>\n";  # dummy for unit below
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>kernel commits</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $cvslog = $d{$date}{$cvsdate}{cvslog};
	unless ($cvslog) {
	    print $html "    <th></th>\n";
	    next;
	}
	my $title = "";
	if ($d{$date}{$cvsdate}{cvsfiles}) {
	    my %files;
	    @files{@{$d{$date}{$cvsdate}{cvsfiles}}} = ();
	    my $files = encode_entities(join(" ", sort keys %files));
	    $title = " title=\"$files\"";
	}
	my $link = uri_escape($cvslog, "^A-Za-z0-9\-\._~/");
	my $cvscommits = $d{$date}{$cvsdate}{cvscommits};
	my $num = defined($cvscommits) ? "/$cvscommits" : "";
	print $html "    <th$title><a href=\"../$link\">log</a>$num</th>\n";
    }
    print $html "    <th></th>\n";  # dummy for unit below
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>build quirks</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $quirks = $d{$date}{$cvsdate}{quirks};
	unless ($quirks) {
	    print $html "    <th></th>\n";
	    next;
	}
	my $link = uri_escape($quirks, "^A-Za-z0-9\-\._~/");
	print $html "    <th><a href=\"$link\">quirks</a></th>\n";
    }
    print $html "    <th></th>\n";  # dummy for unit below
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>repetitions</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $repeats = @{$d{$date}{$cvsdate}{repeats} || []} || "";
	my $repmode = $d{$date}{stepconf}{repmodes};
	my $reptext = $repeats && $repmode && $repeats > 1 ?
	    "$repeats / $repmode" : $repeats;
	$reptext =~ s/\s//g;
	print $html "    <th>$reptext</th>\n";
    }
    print $html "    <th></th>\n";  # dummy for unit below
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>dmesg after run</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $arch = $d{$date}{$cvsdate}{arch} || "dmesg";
	my $dmesg = $d{$date}{$cvsdate}{dmesg};
	my $link = uri_escape($dmesg, "^A-Za-z0-9\-\._~/");
	my $href = $dmesg ? "<a href=\"$link\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html "    <th>$href$arch$enda</th>\n";
    }
    print $html "    <th></th>\n";  # dummy for unit below
    print $html "  </tr>\n";
    foreach my $test (@tests) {
	my $td = $t{$test}{$date} or next;
	print $html "  <tr>\n    <th>$test</th>\n";
	foreach my $cvsdate (@cvsdates) {
	    my $status = $td->{$cvsdate}{status} || "";
	    my $class = " class=\"result $status\"";
	    my $message = encode_entities($td->{$cvsdate}{message});
	    my $title = $message ? " title=\"$message\"" : "";
	    my $logfile = "$cvsdate/logs/$test.log";
	    my $link = uri_escape($logfile, "^A-Za-z0-9\-\._~/");
	    my $href = -f "$date/$logfile" ? "<a href=\"$link\">" : "";
	    my $cvsdatehtml = "$cvsdate/perform.html";
	    $link = uri_escape($cvsdatehtml, "^A-Za-z0-9\-\._~/");
	    $href = "<a href=\"$link\">" if -f "$date/$cvsdatehtml";
	    my $enda = $href ? "</a>" : "";
	    print $html "    <td$class$title>$href$status$enda</td>\n";
	}
	print $html "    <th>unit</th>\n";
	print $html "  </tr>\n";
	my $vt = $v{$date}{$test};
	my @vals;
	foreach my $cvsdate (@cvsdates) {
	    if ($d{$date}{$cvsdate}{repeats}) {
		push @vals, map { $vt->{$cvsdate}{$_} }
		    @{$d{$date}{$cvsdate}{repeats}}
	    } else {
		push @vals, $vt->{$cvsdate};
	    }
	}
	my $maxval = max map { scalar @$_ } @vals;
	for (my $i = 0; $i < $maxval; $i++) {
	    my $rp0 = $d{$date}{$cvsdates[0]}{repeats};
	    my $value0 = $rp0 ?
		first { $_ } map { $vt->{$cvsdates[0]}{$_}[$i] } @$rp0 :
		first { $_ } map { $vt->{$_}[$i] } @cvsdates;
	    my ($name0, $unit0) = ($value0->{name}, $value0->{unit});
	    print $html "  <tr>\n    <th>$name0</th>\n";
	    foreach my $cvsdate (@cvsdates) {
		my $status = $td->{$cvsdate}{status};
		if ($status ne 'PASS' && !$rp0) {
		    print $html "    <td></td>\n";
		    next;
		}
		my $number = $rp0 ? $vt->{$cvsdate}{summary}[$i] :
		    $vt->{$cvsdate}[$i]{number};
		$number //= "";
		my $outlier = $rp0 && $vt->{$cvsdate}{outlier}[$i];
		my $class = $outlier ? ' class="outlier"' : "";
		print $html "    <td$class>$number</td>\n";
	    }
	    print $html "    <td>$unit0</td>\n";
	    print $html "  </tr>\n";
	}
    }
    print $html "</table>\n";

    print $html "<img src=\"../gnuplot/$date-tcp.svg\" ".
	"alt=\"TCP Performance\">\n<br>";
    print $html "<img src=\"../gnuplot/$date-udp.svg\" ".
	"alt=\"UDP Performance\">\n<br>";
    print $html "<img src=\"../gnuplot/$date-make.svg\" ".
	"alt=\"MAKE Performance\">\n<br>";

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
print $html "  <tr>\n    <th>run</th>\n";
foreach my $date (@dates) {
    my $short = $d{$date}{short};
    my $time = encode_entities($date);
    my $datehtml = "$date/perform.html";
    my $link = uri_escape($datehtml, "^A-Za-z0-9\-\._~/");
    my $href = -f $datehtml ? "<a href=\"$link\">" : "";
    my $enda = $href ? "</a>" : "";
    print $html "    <th title=\"$time\">$href$short$enda</th>\n";
}
print $html "  </tr>\n";
print $html "  <tr>\n    <th>test</th>\n";
foreach my $date (@dates) {
    my $setup = $d{$date}{setup};
    my $modes = $d{$date}{stepconf}{modes};
    $modes = $modes ? "/$modes" : "";
    my $link = uri_escape($setup, "^A-Za-z0-9\-\._~/");
    my $href = $setup ? "<a href=\"$link\">" : "";
    my $enda = $href ? "</a>" : "";
    print $html "    <th>${href}setup$enda$modes</th>\n";
}
print $html "  </tr>\n";
print $html "  <tr>\n    <th>first cvs checkout</th>\n";
foreach my $date (@dates) {
    my $cvsdate = $d{$date}{cvsdates}[0];
    my $cvsshort = $d{$date}{$cvsdate}{cvsshort};
    my $time = encode_entities($cvsdate);
    print $html "    <th title=\"$time\">$cvsshort</th>\n";
}
print $html "  </tr>\n";
print $html "  <tr>\n    <th>last cvs checkout</th>\n";
foreach my $date (@dates) {
    my $cvsdate = $d{$date}{cvsdates}[-1];
    my $cvsshort = $d{$date}{$cvsdate}{cvsshort};
    my $time = encode_entities($cvsdate);
    print $html "    <th title=\"$time\">$cvsshort</th>\n";
}
print $html "  </tr>\n";
print $html "  <tr>\n    <th>steps</th>\n";
foreach my $date (@dates) {
    my $steps = @{$d{$date}{cvsdates}};
    my $interval = $d{$date}{stepconf}{step};
    my $steptext = $steps && $interval && $steps > 1 ?
	"$steps / $interval" : $steps || $interval;
    $steptext =~ s/\s//g;
    print $html "    <th>$steptext</th>\n";
}
print $html "  </tr>\n";
print $html "  <tr>\n    <th>repetitions</th>\n";
foreach my $date (@dates) {
    my $cvsdate0 = $d{$date}{cvsdates}[0];
    my $repeats = @{$d{$date}{$cvsdate0}{repeats} || []} || "";
    my $repmode = $d{$date}{stepconf}{repmodes};
    my $reptext = $repeats && $repmode && $repeats > 1 ?
	"$repeats / $repmode" : $repeats;
    $reptext =~ s/\s//g;
    print $html "    <th>$reptext</th>\n";
}
print $html "  </tr>\n";

foreach my $test (@tests) {
    print $html "  <tr>\n    <th>$test</th>\n";
    foreach my $date (@dates) {
	my $status = $t{$test}{$date}{status} || "";
	my $class = " class=\"result $status\"";
	my $message = encode_entities($t{$test}{$date}{message});
	my $title = $message ? " title=\"$message\"" : "";
	my $datehtml = "$date/perform.html";
	my $link = uri_escape($datehtml, "^A-Za-z0-9\-\._~/");
	my $href = -f $datehtml ? "<a href=\"$link\">" : "";
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
