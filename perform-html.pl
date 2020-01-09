#!/usr/bin/perl
# convert all performance results to a html table

# Copyright (c) 2018-2020 Alexander Bluhm <bluhm@genua.de>
# Copyright (c) 2018-2019 Moritz Buhl <mbuhl@genua.de>
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

use lib dirname($0);
use Buildquirks;
use Html;

my $now = strftime("%FT%TZ", gmtime);

my %opts;
getopts('g', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-g]
    -g		generate all gnuplot files, even if they already exist
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

# cvs checkout and repeated results
my @result_files = sort(glob("*/*/test.result"), glob("*/*/*/test.result"));

my (%t, %d, %v);
parse_result_files(@result_files);

write_data_files();
create_gnuplot_files();
create_cvslog_files();
create_nmbsd_files();

my @plots = list_plots();
my @tests = list_tests();
my @dates = list_dates();

# html per date per cvsdate with repetitions

foreach my $date (@dates) {
    my $short = $d{$date}{short};
    my $hostcore = "$d{$date}{host}/$d{$date}{core}";
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
    td.SKIP {background-color: #8080ff;}
    td.FAIL {background-color: #ff8080;}
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
    <th>test host with cpu cores</th>
    <td>$hostcore</td>
  </tr>
  <tr>
    <th>cvs checkout at</th>
    <td>$cvsdate</td>
  </tr>
HEADER

	print $html "  <tr>\n    <th>repetitions kernel mode</th>\n";
	my $kernelmode = $d{$date}{stepconf}{kernelmodes} ||
	    $d{$date}{stepconf}{repmodes};
	my $kerneltext = @repeats;
	if ($kernelmode) {
	    $kerneltext = @repeats && @repeats > 1 ?
		@repeats. " / $kernelmode" : $kernelmode;
	}
	$kerneltext =~ s/\s//g;
	my $build = $d{$date}{$cvsdate}{build};
	$build =~ s,[^/]+/[^/]+/,, if $build;
	my $link = uri_escape($build, "^A-Za-z0-9\-\._~/");
	my $href = $build ? "<a href=\"$link\">" : "";
	my $enda = $href ? " info</a>" : "";
	print $html "    <td>$href$kerneltext$enda</td>\n";
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
	    unless ($kernelmode) {
		print $html "    <th></th>\n";
		next;
	    }
	    my $reboot = $d{$date}{$cvsdate}{$repeat}{reboot};
	    $reboot =~ s,[^/]+/[^/]+/,, if $reboot;
	    my $link = uri_escape($reboot, "^A-Za-z0-9\-\._~/");
	    my $href = $reboot ? "<a href=\"$link\">" : "";
	    my $enda = $href ? " info</a>" : "";
	    print $html "    <th>$href$kernelmode$enda</th>\n";
	}
	print $html "    <th></th><th></th><th></th><th></th><th></th>".
	    "<th></th>\n";  # dummy for unit and stats below
	print $html "  </tr>\n";
	foreach my $test (@tests) {
	    my $td = $t{$test}{$date} && $t{$test}{$date}{$cvsdate}
		or next;
	    print $html "  <tr>\n    <th>$test</th>\n";
	    foreach my $repeat (@repeats) {
		unless ($td->{$repeat}) {
		    print $html "    <td></td>\n";
		    next;
		}
		my $status = $td->{$repeat}{status};
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
	    my $maxval = max map { scalar @{$vt->{$_} || []} } @repeats;
	    for (my $i = 0; $i < $maxval; $i++) {
		my $value0 = first { $_ } map { $vt->{$_}[$i] } @repeats;
		my ($name0, $unit0) = ($value0->{name}, $value0->{unit});
		print $html "  <tr>\n    <th>$name0</th>\n";
		my @numbers = map { $vt->{$_}[$i]{number} }
		    grep { $td->{$_} && $td->{$_}{status} eq 'PASS' } @repeats;
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
		    unless ($td->{$repeat}) {
			print $html "    <td></td>\n";
			next;
		    }
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

	html_table_status($html, "perform");

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
    td.SKIP {background-color: #8080ff;}
    td.FAIL {background-color: #ff8080;}
    td.NOEXIT, td.NOTERM, td.NORUN {background-color: #ffff80;}
    td.NOLOG, td.NOCLEAN, td.NOEXIST {background-color: #ffffff;}
    td.result, td.result a {color: black;}
    td.outlier {color: red;}
    iframe {width: 100%; border: none; min-height: 1200px}
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
    print $html "    <td>${href}log$enda</td>\n";
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>test host with cpu cores</th>\n";
    my $hostname = $d{$date}{host};
    my $core = $d{$date}{core};
    print $html "    <td>$hostname/$core</td>\n";
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>machine release setup</th>\n";
    my $setup = $d{$date}{setup};
    my $release = $d{$date}{stepconf}{release};
    my $setupmodes = $d{$date}{stepconf}{setupmodes} ||
	$d{$date}{stepconf}{modes};
    $link = uri_escape($setup, "^A-Za-z0-9\-\._~/");
    $href = $setup ? "<a href=\"../$link\">" : "";
    $enda = $href ? " info</a>" : "";
    print $html "    <td>$href$release/$setupmodes$enda</td>\n";
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
    print $html "  <tr>\n    <th>machine</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $build = $d{$date}{$cvsdate}{build};
	$build =~ s,[^/]+/,, if $build;
	my $link = uri_escape($build, "^A-Za-z0-9\-\._~/");
	my $href = $build ? "<a href=\"$link\">" : "";
	my $enda = $href ? " info</a>" : "";
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
	$version =~ s,[^/]+/,,;
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
	print $html "    <th$title><a href=\"../$link\">cvslog</a>$num</th>\n";
    }
    print $html "    <th></th>\n";  # dummy for unit below
    print $html "  </tr>\n";
    if (($d{$date}{stepconf}{kernelmodes} || "") eq "align") {
	print $html "  <tr>\n    <th>kernel name list</th>\n";
	foreach my $cvsdate (@cvsdates) {
	    my $nmstat = $d{$date}{$cvsdate}{nmstat};
	    unless ($nmstat) {
		print $html "    <th></th>\n";
		next;
	    }
	    my $difffile = $d{$date}{$cvsdate}{nmdiff};
	    my $link = uri_escape($difffile, "^A-Za-z0-9\-\._~/");
	    my $diffstat = "+$nmstat->{plus} -$nmstat->{minus}";
	    print $html "    <th><a href=\"../$link\">$diffstat</a></th>\n";
	}
	print $html "    <th></th>\n";  # dummy for unit below
	print $html "  </tr>\n";
    }
    print $html "  <tr>\n    <th>build quirks</th>\n";
    my $prevd;
    my $qi = 65 + keys %{{quirks(undef, $cvsdates[0])}};
    foreach my $cvsdate (@cvsdates) {
	my $quirks = $d{$date}{$cvsdate}{quirks};
	print $html "    <th>";
	if ($quirks) {
	    $quirks =~ s,[^/]+/,,;
	    my $link = uri_escape($quirks, "^A-Za-z0-9\-\._~/");
	    print $html "<a href=\"$link\">quirks</a>";
	}
	if ($prevd) {
	    my @quirks = keys %{{quirks($prevd, $cvsdate)}};
	    print $html "/", join(",", map {
		    chr(($qi > 90? 6 + $qi++ : $qi++))
		} @quirks) if @quirks;
	}
	print $html "</th>\n";
	$prevd = $cvsdate;
    }
    print $html "    <th></th>\n";  # dummy for unit below
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>repetitions kernel mode</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $repeats = @{$d{$date}{$cvsdate}{repeats} || []} || "";
	my $kernelmode = $d{$date}{stepconf}{kernelmodes} ||
	    $d{$date}{stepconf}{repmodes};
	my $kerneltext = $repeats;
	if ($kernelmode) {
	    $kerneltext = $repeats && $repeats > 1 ?
		"$repeats / $kernelmode" : $kernelmode;
	}
	$kerneltext =~ s/\s//g;
	print $html "    <th>$kerneltext</th>\n";
    }
    print $html "    <th></th><th></th><th></th><th></th><th></th>".
	"<th></th>\n";  # dummy for unit and stats below
    print $html "  </tr>\n";
    foreach my $test (@tests) {
	my $td = $t{$test}{$date} or next;
	print $html "  <tr>\n    <th>$test</th>\n";
	foreach my $cvsdate (@cvsdates) {
	    unless ($td->{$cvsdate}) {
		print $html "    <td></td>\n";
		next;
	    }
	    my $status = $td->{$cvsdate}{status};
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
	foreach my $stat (qw(unit mean minimum maximum deviation relative)) {
	    print $html "    <th>$stat</th>\n";
	}
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
	my $maxval = max map { scalar @{$_ || []} } @vals;
	for (my $i = 0; $i < $maxval; $i++) {
	    my $rp0 = $d{$date}{$cvsdates[0]}{repeats};
	    my $value0 = $rp0 ?
		first { $_ } map { $vt->{$cvsdates[0]}{$_}[$i] } @$rp0 :
		first { $_ } map { $vt->{$_}[$i] } @cvsdates;
	    my ($name0, $unit0) = ($value0->{name}, $value0->{unit});
	    print $html "  <tr>\n    <th>$name0</th>\n";
	    my @numbers = map { $rp0 ?
		$vt->{$_}{summary}[$i] : $vt->{$_}[$i]{number} }
		grep { $td->{$_} && $td->{$_}{status} eq 'PASS' } @cvsdates;
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
	    foreach my $cvsdate (@cvsdates) {
		unless ($td->{$cvsdate}) {
		    print $html "    <td></td>\n";
		    next;
		}
		my $status = $td->{$cvsdate}{status};
		if ($status ne 'PASS' && !$rp0) {
		    print $html "    <td></td>\n";
		    next;
		}
		my $number = $rp0 ?
		    $vt->{$cvsdate}{summary}[$i] : $vt->{$cvsdate}[$i]{number};
		$number //= "";
		my $outlier = $rp0 && $vt->{$cvsdate}{outlier}[$i];
		my $class = $outlier ? ' class="outlier"' : "";
		print $html "    <td$class>$number</td>\n";
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

    foreach my $plot (@plots) {
	print $html "<iframe src=\"../gnuplot/$date-$plot.html\" alt=\"".
	    uc $plot. " Performance\"></iframe>\n<br>";
    }

    html_table_quirks($html);
    html_table_status($html, "perform");

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

my $htmlfile = "perform.html";
unlink("$htmlfile.new");
open(my $html, '>', "$htmlfile.new")
    or die "Open '$htmlfile.new' for writing failed: $!";
my $htmltitle = "Test";
my $bodytitle = "all";

print $html <<"HEADER";
<!DOCTYPE html>
<html>

<head>
  <title>OpenBSD Perform $htmltitle Results</title>
  <style>
    th { text-align: left; white-space: nowrap; }
    tr:hover {background-color: #e0e0e0}
    td.PASS {background-color: #80ff80;}
    td.SKIP {background-color: #8080ff;}
    td.FAIL {background-color: #ff8080;}
    td.NOEXIT, td.NOTERM, td.NORUN {background-color: #ffff80;}
    td.NOLOG, td.NOCLEAN, td.NOEXIST {background-color: #ffffff;}
    td.result, td.result a {color: black;}
    iframe {width: 100%; border: none; min-height: 1024px;}
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
    <td><a href=\"run.html\">run info</a></td>
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
print $html "  <tr>\n    <th>host cores</th>\n";
foreach my $date (@dates) {
    my $hostname = $d{$date}{host};
    my $core = $d{$date}{core};
    print $html "    <th>$hostname/$core</th>\n";
}
print $html "  </tr>\n";
print $html "  <tr>\n    <th>release setup</th>\n";
foreach my $date (@dates) {
    my $release = $d{$date}{stepconf}{release};
    my $setupmodes = $d{$date}{stepconf}{setupmodes} ||
	$d{$date}{stepconf}{modes};
    print $html "    <th>$release/$setupmodes</th>\n";
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
print $html "  <tr>\n    <th>repetitions kernel mode</th>\n";
foreach my $date (@dates) {
    my $cvsdate0 = $d{$date}{cvsdates}[0];
    my $repeats = @{$d{$date}{$cvsdate0}{repeats} || []} || "";
    my $kernelmode = $d{$date}{stepconf}{kernelmodes} ||
	$d{$date}{stepconf}{repmodes};
    my $kerneltext = $repeats;
    if ($kernelmode) {
	$kerneltext = $repeats && $repeats > 1 ?
	    "$repeats / $kernelmode" : $kernelmode;
    }
    $kerneltext =~ s/\s//g;
    print $html "    <th>$kerneltext</th>\n";
}
print $html "  </tr>\n";

foreach my $test (@tests) {
    print $html "  <tr>\n    <th>$test</th>\n";
    foreach my $date (@dates) {
	my $td = $t{$test}{$date};
	unless ($td) {
	    print $html "    <td></td>\n";
	    next;
	}
	my $status = $td->{status};
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

foreach my $plot (@plots) {
    print $html "<iframe src=\"gnuplot/$plot.html\" alt=\"".
	uc $plot. " Performance\"></iframe>\n<br>";
}

html_table_quirks($html);
html_table_status($html, "perform");

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

exit;

# fill global hashes %t %d %v
sub parse_result_files {
    foreach my $result (@_) {

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
		$status eq 'SKIP'   ? 3 :
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
		if (($t{$test}{$date}{$cvsdate}{severity} || 0) < $severity) {
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
	    if (($t{$test}{$date}{severity} || 0) < $severity) {
		$t{$test}{$date}{status} = $status;
		$t{$test}{$date}{severity} = $severity;
	    }
	    $t{$test}{severity} += $severity;
	}
	close($fh)
	    or die "Close '$result' after reading failed: $!";

	# parse version file
	foreach my $version (sort glob("$date/$cvsdate/version-*.txt")) {
	    $version =~ m,/version-(.+)\.txt$,;
	    my $hostname = $1;

	    next if $d{$date}{$cvsdate}{$hostname};
	    push @{$d{$date}{$cvsdate}{hosts} ||= []}, $hostname;
	    $d{$date}{$cvsdate}{$hostname} = {};
	    $d{$date}{host} ||= $hostname;
	    (my $dmesg = $version) =~ s,/version-,/dmesg-,;
	    $d{$date}{$cvsdate}{$hostname}{dmesg} ||= $dmesg if -f $dmesg;

	    next if $d{$date}{$cvsdate}{version};
	    $d{$date}{$cvsdate}{version} = $version;
	    (my $quirks = $version) =~ s,/version-,/quirks-,;
	    $d{$date}{$cvsdate}{quirks} ||= $quirks if -f $quirks;

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
		/^hw.machine=(\w+)$/ and $d{$date}{arch} ||= $1;
		/^hw.ncpu=(\d+)$/ and $d{$date}{core} ||= $1;
	    }
	}
    }
}

my @plotorder;
my %testplot;
BEGIN {
    @plotorder = qw(tcp udp make fs);
    my @testplot = (
    "iperf3_-c10.3.0.33_-w1m"				=> "tcp",
    "iperf3_-c10.3.0.33_-w1m_-t10"			=> "tcp",
    "iperf3_-c10.3.2.35_-w1m_-t10"			=> "tcp",
    "iperf3_-c10.3.0.33_-w1m_-t60"			=> "tcp",
    "iperf3_-c10.3.0.33_-w1m_-R"			=> "tcp",
    "iperf3_-c10.3.0.33_-w1m_-t10_-R"			=> "tcp",
    "iperf3_-c10.3.2.35_-w1m_-t10_-R"			=> "tcp",
    "iperf3_-c10.3.0.33_-w1m_-t60_-R"			=> "tcp",
    "tcpbench_-S1000000_-t10_10.3.0.33"			=> "tcp",
    "tcpbench_-S1000000_-t10_10.3.2.35"			=> "tcp",
    "tcpbench_-S1000000_-t60_10.3.0.33"			=> "tcp",
    "tcpbench_-S1000000_-t10_-n100_10.3.0.33"		=> "tcp",
    "tcpbench_-S1000000_-t10_-n100_10.3.2.35"		=> "tcp",
    "tcpbench_-S1000000_-t60_-n100_10.3.0.33"		=> "tcp",
    "iperf3_-c10.3.0.33_-u_-b0_-w1m"			=> "udp",
    "iperf3_-c10.3.0.33_-u_-b0_-w1m_-t10"		=> "udp",
    "iperf3_-c10.3.2.35_-u_-b0_-w1m_-t10"		=> "udp",
    "iperf3_-c10.3.0.33_-u_-b0_-w1m_-t60"		=> "udp",
    "iperf3_-c10.3.0.33_-u_-b0_-w1m_-R"			=> "udp",
    "iperf3_-c10.3.0.33_-u_-b0_-w1m_-t10_-R"		=> "udp",
    "iperf3_-c10.3.2.35_-u_-b0_-w1m_-t10_-R"		=> "udp",
    "iperf3_-c10.3.0.33_-u_-b0_-w1m_-t60_-R"		=> "udp",
    "iperf3_-c10.3.0.33_-u_-b10G_-w1m"			=> "udp",
    "iperf3_-c10.3.0.33_-u_-b10G_-w1m_-t10"		=> "udp",
    "iperf3_-c10.3.2.35_-u_-b10G_-w1m_-t10"		=> "udp",
    "iperf3_-c10.3.0.33_-u_-b10G_-w1m_-t60"		=> "udp",
    "iperf3_-c10.3.0.33_-u_-b10G_-w1m_-R"		=> "udp",
    "iperf3_-c10.3.0.33_-u_-b10G_-w1m_-t10_-R"		=> "udp",
    "iperf3_-c10.3.2.35_-u_-b10G_-w1m_-t10_-R"		=> "udp",
    "iperf3_-c10.3.0.33_-u_-b10G_-w1m_-t60_-R"		=> "udp",
    "udpbench_-l36_-t10_-r_ot13_send_10.3.0.33"		=> "udp",
    "udpbench_-l36_-t10_-r_ot13_recv_10.3.0.32"		=> "udp",
    "udpbench_-l1472_-t10_-r_ot13_send_10.3.0.33"	=> "udp",
    "udpbench_-l1472_-t10_-r_ot13_recv_10.3.0.32"	=> "udp",
    "udpbench_-l36_-t10_-r_ot15_send_10.3.2.35"		=> "udp",
    "udpbench_-l36_-t10_-r_ot15_recv_10.3.2.34"		=> "udp",
    "udpbench_-l1472_-t10_-r_ot15_send_10.3.2.35"	=> "udp",
    "udpbench_-l1472_-t10_-r_ot15_recv_10.3.2.34"	=> "udp",
    "time_-lp_make_-CGENERIC.MP_-j4_-s"			=> "make",
    "time_-lp_make_-CGENERIC.MP_-j8_-s"			=> "make",
    "time_-lp_fs_mark_-dfs_mark_-D8_-N16_-n256_-t8"	=> "fs",
    );
    %testplot = @testplot;
    if (2 * keys %testplot != @testplot) {
	die "testplot keys not unique";
    }
    my %plots;
    @plots{@plotorder} = ();
    while (my ($k, $v) = each %testplot) {
	die "invalid plot $v for test $k" unless exists $plots{$v};
    }
}

sub list_plots {
    return @plotorder;
}

# write test results into gnuplot data file
sub write_data_files {
    -d "gnuplot" || mkdir "gnuplot"
	or die "Create directory 'gnuplot' failed: $!";
    my $testdata = "gnuplot/test";
    my %plotfh;
    @plotfh{values %testplot} = ();
    foreach my $plot (keys %plotfh) {
	open($plotfh{$plot}, '>', "$testdata-$plot.data.new")
	    or die "Open '$testdata-$plot.data.new' for writing failed: $!";
	print {$plotfh{$plot}}
	    "# test subtest run checkout repeat value unit host\n";
    }
    open(my $fh, '>', "$testdata.data.new")
	or die "Open '$testdata.data.new' for writing failed: $!";
    print $fh "# test subtest run checkout repeat value unit host\n";
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
			my $hostname = $d{$date}{host};
			print $fh "$test $subtest ".
			    "$run $checkout $repeat $number $unit $hostname\n";
			print {$plotfh{$testplot{$test}}} "$test $subtest ".
			    "$run $checkout $repeat $number $unit $hostname\n"
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

my %testorder;
# explain most significant to least significant digits
# - 0xxxx type
#   1xxxx network ot12/ot13
#   2xxxx network ot14/ot15
#   3xxxx network ot14/lt16
#   4xxxx make kernel
#   5xxxx file system
# - x0xxx family
#   x1xxx network IPv6
#   x2xxx network IPv6
# - xx0xx protocol
#   xx1xx iperf tcp
#   xx2xx tcpbench
#   xx3xx iperf udp
#   xx4xx iperf udp 10Gbit
#   xx5xx udpbench
# - xxx0x aspects
#   xxx1x iperf forward direction
#   xxx2x iperf reverse direction
#   xxx1x tcpbench single connction
#   xxx2x tcpbench 100 connections
#   xxx1x udpbench send large packets
#   xxx2x udpbench receive large packets
#   xxx3x udpbench send small packets
#   xxx4x udpbench receive small packets
#   xxx4x 4 make processes
#   xxx8x 8 make processes
#   xxx8x 8 fs_mark threads
# - xxxx0 tune
#   xxxx1 10 secondes timeout
#   xxxx2 60 secondes timeout
#   xxxx3 iperf udp bandwidth 10G
#   xxxx3 iperf tcp window 1m
#   xxxx4 iperf tcp window 2m
#   xxxx5 iperf tcp window 400k
#   xxxx6 iperf tcp window 410k
BEGIN {
    # put testorder in begin block to check consistency during compile time
    my @testorder = (
    "iperf3_-c10.3.0.33_-w1m_-t10"				=> 11111,
    "iperf3_-c10.3.2.35_-w1m_-t10"				=> 21111,
    "iperf3_-c10.3.0.33_-w1m_-t60"				=> 11112,
    "iperf3_-c10.3.0.33_-w1m_-t10_-R"				=> 11121,
    "iperf3_-c10.3.2.35_-w1m_-t10_-R"				=> 21121,
    "iperf3_-c10.3.0.33_-w1m_-t60_-R"				=> 11122,
    "iperf3_-6_-cfdd7:e83e:66bc:0300::33_-w1m_-t10"		=> 12111,
    "iperf3_-6_-cfdd7:e83e:66bc:0302::35_-w1m_-t10"		=> 22111,
    "iperf3_-6_-cfdd7:e83e:66bc:0300::33_-w1m_-t60"		=> 12112,
    "iperf3_-6_-cfdd7:e83e:66bc:0300::33_-w1m_-t10_-R"		=> 12121,
    "iperf3_-6_-cfdd7:e83e:66bc:0302::35_-w1m_-t10_-R"		=> 22121,
    "iperf3_-6_-cfdd7:e83e:66bc:0300::33_-w1m_-t60_-R"		=> 12122,
    "iperf3_-c10.3.3.36_-t10"					=> 31111,
    "iperf3_-c10.3.3.36_-t60"					=> 31112,
    "iperf3_-c10.3.3.36_-w1m_-t10"				=> 31113,
    "iperf3_-c10.3.3.36_-w2m_-t10"				=> 31114,
    "iperf3_-c10.3.3.36_-w400k_-t10"				=> 31115,
    "iperf3_-c10.3.3.36_-w410k_-t10"				=> 31116,
    "iperf3_-c10.3.3.36_-t10_-R"				=> 31121,
    "iperf3_-c10.3.3.36_-t60_-R"				=> 31122,
    "iperf3_-c10.3.3.36_-w1m_-t10_-R"				=> 31123,
    "iperf3_-c10.3.3.36_-w2m_-t10_-R"				=> 31124,
    "iperf3_-c10.3.3.36_-w400k_-t10_-R"				=> 31125,
    "iperf3_-c10.3.3.36_-w410k_-t10_-R"				=> 31126,
    "iperf3_-6_-cfdd7:e83e:66bc:0303::36_-t10"			=> 32111,
    "iperf3_-6_-cfdd7:e83e:66bc:0303::36_-t60"			=> 32112,
    "iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w1m_-t10"		=> 32113,
    "iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w2m_-t10"		=> 32114,
    "iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w400k-t10"		=> 32115,
    "iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w410k-t10"		=> 32116,
    "iperf3_-6_-cfdd7:e83e:66bc:0303::36_-t10_-R"		=> 32121,
    "iperf3_-6_-cfdd7:e83e:66bc:0303::36_-t60_-R"		=> 32122,
    "iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w1m_-t10_-R"		=> 32123,
    "iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w2m_-t10_-R"		=> 32124,
    "iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w400k-t10_-R"		=> 32125,
    "iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w410k-t10_-R"		=> 32126,
    "tcpbench_-S1000000_-t10_10.3.0.33"				=> 11211,
    "tcpbench_-S1000000_-t10_10.3.2.35"				=> 21211,
    "tcpbench_-S1000000_-t60_10.3.0.33"				=> 11212,
    "tcpbench_-S1000000_-t10_-n100_10.3.0.33"			=> 11221,
    "tcpbench_-S1000000_-t10_-n100_10.3.2.35"			=> 21221,
    "tcpbench_-S1000000_-t60_-n100_10.3.0.33"			=> 11222,
    "tcpbench_-S1000000_-t10_fdd7:e83e:66bc:0300::33"		=> 12211,
    "tcpbench_-S1000000_-t10_fdd7:e83e:66bc:0302::35"		=> 22211,
    "tcpbench_-S1000000_-t60_fdd7:e83e:66bc:0300::33"		=> 12212,
    "tcpbench_-S1000000_-t10_-n100_fdd7:e83e:66bc:0300::33"	=> 12221,
    "tcpbench_-S1000000_-t10_-n100_fdd7:e83e:66bc:0302::35"	=> 22221,
    "tcpbench_-S1000000_-t60_-n100_fdd7:e83e:66bc:0300:33"	=> 12222,
    "iperf3_-c10.3.0.33_-u_-b0_-w1m_-t10"			=> 11311,
    "iperf3_-c10.3.2.35_-u_-b0_-w1m_-t10"			=> 21311,
    "iperf3_-c10.3.0.33_-u_-b0_-w1m_-t60"			=> 11312,
    "iperf3_-c10.3.0.33_-u_-b0_-w1m_-t10_-R"			=> 11321,
    "iperf3_-c10.3.2.35_-u_-b0_-w1m_-t10_-R"			=> 21321,
    "iperf3_-c10.3.0.33_-u_-b0_-w1m_-t60_-R"			=> 11322,
    "iperf3_-c10.3.0.33_-u_-b10G_-w1m_-t10"			=> 11413,
    "iperf3_-c10.3.2.35_-u_-b10G_-w1m_-t10"			=> 21413,
    "iperf3_-c10.3.0.33_-u_-b10G_-w1m_-t10_-R"			=> 11423,
    "iperf3_-c10.3.2.35_-u_-b10G_-w1m_-t10_-R"			=> 21423,
    "iperf3_-6_-cfdd7:e83e:66bc:0300::33_-u_-b0_-w1m_-t10"	=> 12311,
    "iperf3_-6_-cfdd7:e83e:66bc:0302::35_-u_-b0_-w1m_-t10"	=> 22311,
    "iperf3_-6_-cfdd7:e83e:66bc:0300::33_-u_-b0_-w1m_-t60"	=> 12312,
    "iperf3_-6_-cfdd7:e83e:66bc:0300::33_-u_-b0_-w1m_-t10_-R"	=> 12321,
    "iperf3_-6_-cfdd7:e83e:66bc:0302::35_-u_-b0_-w1m_-t10_-R"	=> 22321,
    "iperf3_-6_-cfdd7:e83e:66bc:0300::33_-u_-b0_-w1m_-t60_-R"	=> 12322,
    "iperf3_-6_-cfdd7:e83e:66bc:0300::33_-u_-b10G_-w1m_-t10"	=> 12413,
    "iperf3_-6_-cfdd7:e83e:66bc:0302::35_-u_-b10G_-w1m_-t10"	=> 22413,
    "iperf3_-6_-cfdd7:e83e:66bc:0300::33_-u_-b10G_-w1m_-t10_-R"	=> 12423,
    "iperf3_-6_-cfdd7:e83e:66bc:0302::35_-u_-b10G_-w1m_-t10_-R"	=> 22423,
    "udpbench_-l1472_-t10_-r_ot13_send_10.3.0.33"		=> 11511,
    "udpbench_-l1472_-t10_-r_ot13_recv_10.3.0.32"		=> 11521,
    "udpbench_-l36_-t10_-r_ot13_send_10.3.0.33"			=> 11531,
    "udpbench_-l36_-t10_-r_ot13_recv_10.3.0.32"			=> 11541,
    "udpbench_-l1472_-t10_-r_ot15_send_10.3.2.35"		=> 21511,
    "udpbench_-l1472_-t10_-r_ot15_recv_10.3.2.34"		=> 21521,
    "udpbench_-l36_-t10_-r_ot15_send_10.3.2.35"			=> 21531,
    "udpbench_-l36_-t10_-r_ot15_recv_10.3.2.34"			=> 21541,
    "udpbench_-l1472_-t10_-r_ot13_send_fdd7:e83e:66bc:0300::33"	=> 12511,
    "udpbench_-l1472_-t10_-r_ot13_recv_fdd7:e83e:66bc:0300::32"	=> 12521,
    "udpbench_-l36_-t10_-r_ot13_send_fdd7:e83e:66bc:0300::33"	=> 12531,
    "udpbench_-l36_-t10_-r_ot13_recv_fdd7:e83e:66bc:0300::32"	=> 12541,
    "udpbench_-l1472_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35"	=> 22511,
    "udpbench_-l1472_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34"	=> 22521,
    "udpbench_-l36_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35"	=> 22531,
    "udpbench_-l36_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34"	=> 22541,
    "time_-lp_make_-CGENERIC.MP_-j4_-s"				=> 40040,
    "time_-lp_make_-CGENERIC.MP_-j8_-s"				=> 40080,
    "time_-lp_fs_mark_-dfs_mark_-D8_-N16_-n256_-t8"		=> 50080,
    );
    %testorder = @testorder;
    if (2 * keys %testorder != @testorder) {
	die "testorder keys not unique";
    }
    my %ordervalues = reverse @testorder;
    if (2 * keys %ordervalues != @testorder) {
	my %dup;
	foreach (values %testorder) {
	    warn "duplicate testorder value $_\n" if ++$dup{$_} > 1;
	}
	die "testorder values not unique";
    }
}

sub list_tests {
    foreach my $test (keys %t) {
	next if $testorder{$test};
	warn "testorder missing test $test\n";
	$testorder{$test} = 0;
    }
    return reverse sort { $testorder{$b} <=> $testorder{$a} } keys %t;
}

sub list_dates {
    return reverse sort keys %d;
}

# create gnuplot graphs for all runs
sub create_gnuplot_files {
    foreach my $plot (list_plots()) {
	foreach my $date (keys %v) {
	    my $outfile = "$date-$plot.html";
	    if ($opts{g} || ! -f "gnuplot/$outfile") {
		my @cmd = ("$performdir/bin/gnuplot.pl", "-D", $date,
		    "-T", "$plot");
		system(@cmd)
		    and die "Command '@cmd' failed: $?";
	    }
	}
	my @cmd = ("$performdir/bin/gnuplot.pl", "-T", "$plot");
	system(@cmd)
	    and die "Command '@cmd' failed: $?";
    }
}

# create cvs log file with commits after previous cvsdates
sub create_cvslog_files {
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
		    # If html is available, use its nicer display in link.
		    $dd->{$cvsdate}{cvslog} = "$cvslog.html";
		}
	    }
	    $cvsprev = $cvsdate;
	}
    }
}

sub create_nmbsd_files {
    foreach my $date (sort keys %d) {
	my $dv = $d{$date};
	next if ($dv->{stepconf}{kernelmodes} || "") ne "align";
	my $hostname = $dv->{host};
	my $prevnmfile;
	foreach my $cvsdate (sort @{$dv->{cvsdates}}) {
	    my $cv = $dv->{$cvsdate};
	    my $nmfile = "$date/$cvsdate/nm-bsd-$hostname.txt";
	    next unless -r $nmfile;
	    if ($prevnmfile) {
		my $difffile = "$date/$cvsdate/nm-bsd-diff.txt";
		my %stat;
		diff_stat_file($prevnmfile, $nmfile, $difffile, \%stat);
		$cv->{nmdiff} = $difffile;
		$cv->{nmstat} = \%stat;
	    }
	    $prevnmfile = $nmfile;
	}
    }
}

sub diff_stat_file {
    my ($prev, $cur, $out, $stat) = @_;

    my @cmd = ('diff', '-up', $prev, $cur);
    open(my $diff, '-|', @cmd)
	or die "Open pipe from '@cmd' failed: $!";
    open(my $fh, '>', "$out.new")
	or die "Open '$out.new' for writing failed: $!";

    # diff header
    print $fh $_ if defined($_ = <$diff>);
    print $fh $_ if defined($_ = <$diff>);
    my ($plus, $minus) = (0, 0);
    while (<$diff>) {
	$plus++ if /^\+/;
	$minus++ if /^-/;
	print $fh $_;
    }
    $stat->{plus} = $plus;
    $stat->{minus} = $minus;

    unless (close($diff)) {
	die "Close pipe from '@cmd' failed: $!" if $!;
	die "Command '@cmd' failed: $?" if $? != 0 && $? != 256;
    }
    close($fh)
	or die "Close '$out.new' after writing failed: $!";
    rename("$out.new", $out)
	or die "Rename '$out.new' to '$out' failed: $!";
}
