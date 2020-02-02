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

# %T
# $test					performance test tool command line
# $T{$test}{severity}			weighted severity of all failures
# $date					date when test was executed as string
# $T{$test}{$date}
# $T{$test}{$date}{status}		worst status of this test run
# $T{$test}{$date}{message}		never set
# $T{$test}{$date}{severity}		worst severity of this test run
# $cvsdate				date of the cvs checkout as string
# $T{$test}{$date}{$cvsdate}
# $T{$test}{$date}{$cvsdate}{status}	result of this test or worst status
# $T{$test}{$date}{$cvsdate}{message}	test printed a summary unless repeat
# $T{$test}{$date}{$cvsdate}{severity}	worst severity of repeats
# $repeat				number of the repetition as string
# $T{$test}{$date}{$cvsdate}{$repeat}
# $T{$test}{$date}{$cvsdate}{$repeat}{status}	result of this test
# $T{$test}{$date}{$cvsdate}{$repeat}{message}	test printed a summary
# %D
# $date					date when test was executed as string
# $D{$date}{short}			date without time
# $D{$date}{setup}			path to setup.html
# $D{$date}{host}			hostname of the machine running perform
# $D{$date}{arch}			sysctl hardware machine architecture
# $D{$date}{core}			sysctl hardware ncpu cores
# $D{$date}{log}			path to setp.log
# $D{$date}{stepconf}			config options of step.pl
# $D{$date}{stepconf}{release}		release version for setup
# $D{$date}{stepconf}{setupmodes}	mode for machine setup
# $D{$date}{stepconf}{modes}		deprecated
# $D{$date}{stepconf}{kernelmodes}	mode for building kernel
# $D{$date}{stepconf}{repmodes}		deprecated
# $D{$date}{stepconf}{step}		step interval and unit
# $cvsdate				date of the cvs checkout as string
# $D{$date}{cvsdates}			array of cvsdates
# $D{$date}{$cvsdate}{cvsshort}		cvsdate without time
# $D{$date}{$cvsdate}{result}		path to test.result file
# $D{$date}{$cvsdate}{version}		version.txt of machine running perform
# $D{$date}{$cvsdate}{quirks}		quirks.txt of machine running perform
# $D{$date}{$cvsdate}{build}		path to build.html
# $D{$date}{$cvsdate}{kernel}		sysctl kernel version string
# $D{$date}{$cvsdate}{cvs}		cvs checkout date in kernel version
# $D{$date}{$cvsdate}{time}		build time in kernel version string
# $D{$date}{$cvsdate}{location}		user at location of kernel build
# $D{$date}{$cvsdate}{nmdiff}		path to nm-bsd-diff.txt if align
# $D{$date}{$cvsdate}{nmstat}		diffstat of nm-bsd-diff if align
# $hostname				hostname of the machine
# $D{$date}{$cvsdate}{hosts}		array of hosts
# $D{$date}{$cvsdate}{$hostname}{version}	path to version.txt
# $D{$date}{$cvsdate}{$hostname}{dmesg}		path to version.txt
# $repeat				number of the repetition as string
# $D{$date}{$cvsdate}{repeats}		array of repetition numbers as string
# $D{$date}{$cvsdate}{$repeat}{result}	path to test.result file
# $D{$date}{$cvsdate}{$repeat}{reboot}	path to reboot.html
# $D{$date}{$cvsdate}{cvslog}		path to cvslog.html or cvslog.txt
# $D{$date}{$cvsdate}{cvscommits}	number of cvs commits
# $D{$date}{$cvsdate}{cvsfiles}		array of files changes in cvs commit
# %V
# $date					date when test was executed as string
# $test					performance test tool command line
# $cvsdate				date of the cvs checkout as string
# $V{$date}{$test}{$cvsdate}		array of values
# $repeat				number of the repetition as string
# $V{$date}{$test}{$cvsdate}{$repeat}	array of values
# $value				index of value
# [$value]{name}			name of subtest
# [$value]{unit}			unit of number
# [$value]{number}			numeric value
# %Z @Z
# $Z{$cvsdate}				index in @Z
# $Z[$index]				hash of dates containing cvs checkout

my (%T, %D, %V, %Z, @Z);
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
    my $short = $D{$date}{short};
    foreach my $cvsdate (@{$D{$date}{cvsdates}}) {
	my $cvsshort = $D{$date}{$cvsdate}{cvsshort};
	my @repeats = sort @{$D{$date}{$cvsdate}{repeats} || []}
	    or next;

	my ($html, $htmlfile) = html_open("$date/$cvsdate/perform");
	html_header($html, "OpenBSD Perform CVS Date Results",
	    "OpenBSD perform $short cvs $cvsshort test results");
	html_repeat_top($html, $date, $cvsdate, @repeats);

	print $html "<table>\n";
	html_repeat_test_head($html, $date, $cvsdate, @repeats);
	foreach my $test (@tests) {
	    my $td = $T{$test}{$date} && $T{$test}{$date}{$cvsdate}
		or next;
	    html_repeat_test_row($html, $date, $cvsdate, $test, $td, @repeats);
	}
	print $html "</table>\n";

	html_status_table($html, "perform");
	html_footer($html);
	html_close($html, $htmlfile);
    }
}

# html per date with cvsdate

foreach my $date (@dates) {
    my $short = $D{$date}{short};
    my @cvsdates = @{$D{$date}{cvsdates}};

    my ($html, $htmlfile) = html_open("$date/perform");
    html_header($html, "OpenBSD Perform Date Results",
	"OpenBSD perform $short test results");
    html_cvsdate_top($html, $date, @cvsdates);

    print $html "<table>\n";
    html_cvsdate_test_head($html, $date, @cvsdates);
    foreach my $test (@tests) {
	my $td = $T{$test}{$date}
	    or next;
	html_cvsdate_test_row($html, $date, $test, $td, @cvsdates);
    }
    print $html "</table>\n";

    print $html "<table>\n";
    foreach my $plot (@plots) {
	print $html "  <tr>\n";
	html_plot_data($plot, $date, "..");
	print $html "  </tr>\n";
    }
    print $html "</table>\n";

    html_quirks_table($html, $html);
    html_status_table($html, "perform");
    html_footer($html);
    html_close($html, $htmlfile);
}

# html with date

my ($html, $htmlfile) = html_open("perform");
html_header($html, "OpenBSD Perform Test Results",
    "OpenBSD perform all test results");
html_date_top($html);

print $html "<table>\n";
html_date_test_head($html, @dates);
foreach my $test (@tests) {
    my $td = $T{$test};
    html_date_test_row($html, $test, $td, @dates);
}
print $html "</table>\n";

print $html "<table>\n";
foreach my $plot (@plots) {
    print $html "  <tr>\n";
    html_plot_data($plot);
    print $html "  </tr>\n";
}
print $html "</table>\n";

html_quirks_table($html);
html_status_table($html, "perform");
html_footer($html);
html_close($html, $htmlfile);

exit;

# fill global hashes %T %D %V %Z @Z
sub parse_result_files {
    foreach my $result (@_) {

	# parse result file
	my ($date, $short, $cvsdate, $cvsshort, $repeat) =
	    $result =~ m,(([^/]+)T[^/]+)/(([^/]+)T[^/]+)/(?:(\d+)/)?test.result,
	    or next;
	$D{$date}{short} ||= $short;
	push @{$D{$date}{cvsdates} ||= []}, $cvsdate unless $D{$date}{$cvsdate};
	$D{$date}{$cvsdate}{cvsshort} ||= $cvsshort;
	if (defined $repeat) {
	    push @{$D{$date}{$cvsdate}{repeats} ||= []}, $repeat;
	    $D{$date}{$cvsdate}{$repeat}{result} = $result;
	} else {
	    $D{$date}{$cvsdate}{result} = $result;
	}
	$D{$date}{log} ||= "step.log" if -f "$date/step.log";
	unless ($D{$date}{stepconf}) {
	    my $stepfile = "$date/stepconf.txt";
	    if (open (my $fh, '<', $stepfile)) {
		while (<$fh>) {
		    chomp;
		    my ($k, $v) = split(/\s+/, $_, 2);
		    $D{$date}{stepconf}{lc($k)} = $v;
		}
	    } else {
		$!{ENOENT}
		    or die "Open '$stepfile' for reading failed: $!";
	    }
	}
	$D{$date}{setup} ||= "$date/setup.html" if -f "$date/setup.html";
	$D{$date}{$cvsdate}{build} ||= "$date/$cvsdate/build.html"
	    if -f "$date/$cvsdate/build.html";
	if (defined $repeat) {
	    $D{$date}{$cvsdate}{$repeat}{reboot} ||=
		"$date/$cvsdate/$repeat/reboot.html"
		if -f "$date/$cvsdate/$repeat/reboot.html";
	}
	$_->{severity} *= .5 foreach values %T;
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
	    my $severity = status2severity($status);
	    if (defined $repeat) {
		$V{$date}{$test}{$cvsdate}{$repeat} = [ @values ];
		$T{$test}{$date}{$cvsdate}{$repeat}
		    and warn "Duplicate test '$test' date '$date' ".
			"cvsdate '$cvsdate' repeat '$repeat'";
		$T{$test}{$date}{$cvsdate}{$repeat} = {
		    status => $status,
		    message => $message,
		};
		if (($T{$test}{$date}{$cvsdate}{severity} || 0) < $severity) {
		    $T{$test}{$date}{$cvsdate}{status} = $status;
		    $T{$test}{$date}{$cvsdate}{severity} = $severity;
		}
	    } else {
		$V{$date}{$test}{$cvsdate} = [ @values ];
		$T{$test}{$date}{$cvsdate}
		    and warn "Duplicate test '$test' date '$date' ".
			"cvsdate '$cvsdate'";
		$T{$test}{$date}{$cvsdate} = {
		    status => $status,
		    message => $message,
		};
	    }
	    $Z{$cvsdate}{$date} = 1 if @values;
	    undef @values;
	    if (($T{$test}{$date}{severity} || 0) < $severity) {
		$T{$test}{$date}{status} = $status;
		$T{$test}{$date}{severity} = $severity;
	    }
	    $T{$test}{severity} += $severity;
	}
	close($fh)
	    or die "Close '$result' after reading failed: $!";

	# parse version file
	foreach my $version (sort glob("$date/$cvsdate/version-*.txt")) {
	    $version =~ m,/version-(.+)\.txt$,;
	    my $hostname = $1;

	    next if $D{$date}{$cvsdate}{$hostname};
	    push @{$D{$date}{$cvsdate}{hosts} ||= []}, $hostname;
	    $D{$date}{$cvsdate}{$hostname} = {
		version => $version,
	    };
	    $D{$date}{host} ||= $hostname;
	    (my $dmesg = $version) =~ s,/version-,/dmesg-,;
	    $D{$date}{$cvsdate}{$hostname}{dmesg} ||= $dmesg if -f $dmesg;

	    next if $D{$date}{$cvsdate}{version};
	    $D{$date}{$cvsdate}{version} = $version;
	    (my $quirks = $version) =~ s,/version-,/quirks-,;
	    $D{$date}{$cvsdate}{quirks} ||= $quirks if -f $quirks;

	    open($fh, '<', $version)
		or die "Open '$version' for reading failed: $!";
	    while (<$fh>) {
		if (/^kern.version=(.*(?:cvs : (\w+))?: (\w+ \w+ +\d+ .*))$/) {
		    $D{$date}{$cvsdate}{kernel} = $1;
		    $D{$date}{$cvsdate}{cvs} = $2;
		    $D{$date}{$cvsdate}{time} = $3;
		    <$fh> =~ /(\S+)/;
		    $D{$date}{$cvsdate}{kernel} .= "\n    $1";
		    $D{$date}{$cvsdate}{location} = $1;
		}
		/^hw.machine=(\w+)$/ and $D{$date}{arch} ||= $1;
		/^hw.ncpu=(\d+)$/ and $D{$date}{core} ||= $1;
	    }
	}
    }
    foreach my $cvsdate (sort keys %Z) {
	push @Z, $Z{$cvsdate};
	$Z{$cvsdate} = $#Z;
    }
}

my @plotorder;
my %testplot;
BEGIN {
    @plotorder = qw(tcp tcp6 udp udp6 linux linux6 make fs);
    my @testplot = (
    "iperf3_-c10.3.0.33_-w1m_-t10"			=> "tcp",
    "iperf3_-c10.3.2.35_-w1m_-t10"			=> "tcp",
    "iperf3_-c10.3.0.33_-w1m_-t10_-R"			=> "tcp",
    "iperf3_-c10.3.2.35_-w1m_-t10_-R"			=> "tcp",
    "tcpbench_-S1000000_-t10_10.3.0.33"			=> "tcp",
    "tcpbench_-S1000000_-t10_10.3.2.35"			=> "tcp",
    "tcpbench_-S1000000_-t10_-n100_10.3.0.33"		=> "tcp",
    "tcpbench_-S1000000_-t10_-n100_10.3.2.35"		=> "tcp",
    "iperf3_-c10.3.0.33_-u_-b10G_-w1m_-t10"		=> "udp",
    "iperf3_-c10.3.2.35_-u_-b10G_-w1m_-t10"		=> "udp",
    "iperf3_-c10.3.0.33_-u_-b10G_-w1m_-t10_-R"		=> "udp",
    "iperf3_-c10.3.2.35_-u_-b10G_-w1m_-t10_-R"		=> "udp",
    "udpbench_-l1472_-t10_-r_ot13_send_10.3.0.33"	=> "udp",
    "udpbench_-l1472_-t10_-r_ot15_send_10.3.2.35"	=> "udp",
    "udpbench_-l1472_-t10_-r_ot13_recv_10.3.0.32"	=> "udp",
    "udpbench_-l1472_-t10_-r_ot15_recv_10.3.2.34"	=> "udp",
    "udpbench_-l36_-t10_-r_ot13_send_10.3.0.33"		=> "udp",
    "udpbench_-l36_-t10_-r_ot15_send_10.3.2.35"		=> "udp",
    "udpbench_-l36_-t10_-r_ot13_recv_10.3.0.32"		=> "udp",
    "udpbench_-l36_-t10_-r_ot15_recv_10.3.2.34"		=> "udp",
    "iperf3_-6_-cfdd7:e83e:66bc:0302::35_-w1m_-t10"		=> "tcp6",
    "iperf3_-6_-cfdd7:e83e:66bc:0302::35_-w1m_-t10_-R"		=> "tcp6",
    "tcpbench_-S1000000_-t10_fdd7:e83e:66bc:0302::35"		=> "tcp6",
    "tcpbench_-S1000000_-t10_-n100_fdd7:e83e:66bc:0302::35"	=> "tcp6",
    "iperf3_-6_-cfdd7:e83e:66bc:0302::35_-u_-b10G_-w1m_-t10"	=> "udp6",
    "iperf3_-6_-cfdd7:e83e:66bc:0302::35_-u_-b10G_-w1m_-t10_-R"	=> "udp6",
    "udpbench_-l1452_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35"	=> "udp6",
    "udpbench_-l1452_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34"	=> "udp6",
    "udpbench_-l16_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35"	=> "udp6",
    "udpbench_-l16_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34"	=> "udp6",
    "iperf3_-c10.3.3.36_-w2m_-t10"			=> "linux",
    "iperf3_-c10.3.3.36_-w2m_-t10_-R"			=> "linux",
    "iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w2m_-t10"	=> "linux6",
    "iperf3_-6_-cfdd7:e83e:66bc:0303::36_-w2m_-t10_-R"	=> "linux6",
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
    foreach my $date (sort keys %V) {
	my $vd = $V{$date};
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
			my $hostname = $D{$date}{host};
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
    "iperf3_-c10.3.0.33_-u_-b0_-w1m_-t10_-R"			=> 11321,
    "iperf3_-c10.3.2.35_-u_-b0_-w1m_-t10_-R"			=> 21321,
    "iperf3_-c10.3.0.33_-u_-b10G_-w1m_-t10"			=> 11413,
    "iperf3_-c10.3.2.35_-u_-b10G_-w1m_-t10"			=> 21413,
    "iperf3_-c10.3.0.33_-u_-b10G_-w1m_-t10_-R"			=> 11423,
    "iperf3_-c10.3.2.35_-u_-b10G_-w1m_-t10_-R"			=> 21423,
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
    "udpbench_-l1452_-t10_-r_ot13_send_fdd7:e83e:66bc:0300::33"	=> 12511,
    "udpbench_-l1452_-t10_-r_ot13_recv_fdd7:e83e:66bc:0300::32"	=> 12521,
    "udpbench_-l16_-t10_-r_ot13_send_fdd7:e83e:66bc:0300::33"	=> 12531,
    "udpbench_-l16_-t10_-r_ot13_recv_fdd7:e83e:66bc:0300::32"	=> 12541,
    "udpbench_-l1452_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35"	=> 22511,
    "udpbench_-l1452_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34"	=> 22521,
    "udpbench_-l16_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35"	=> 22531,
    "udpbench_-l16_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34"	=> 22541,
    "udpbench_-l1472_-t10_-r_ot13_send_fdd7:e83e:66bc:0300::33"	=> 12512,
    "udpbench_-l1472_-t10_-r_ot13_recv_fdd7:e83e:66bc:0300::32"	=> 12522,
    "udpbench_-l36_-t10_-r_ot13_send_fdd7:e83e:66bc:0300::33"	=> 12532,
    "udpbench_-l36_-t10_-r_ot13_recv_fdd7:e83e:66bc:0300::32"	=> 12542,
    "udpbench_-l1472_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35"	=> 22512,
    "udpbench_-l1472_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34"	=> 22522,
    "udpbench_-l36_-t10_-r_ot15_send_fdd7:e83e:66bc:0302::35"	=> 22532,
    "udpbench_-l36_-t10_-r_ot15_recv_fdd7:e83e:66bc:0302::34"	=> 22542,
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
    foreach my $test (keys %T) {
	next if $testorder{$test};
	warn "testorder missing test $test\n";
	$testorder{$test} = 0;
    }
    return reverse sort { $testorder{$b} <=> $testorder{$a} } keys %T;
}

sub list_dates {
    return reverse sort keys %D;
}

# create gnuplot graphs for all runs
sub create_gnuplot_files {
    foreach my $plot (list_plots()) {
	foreach my $date (keys %V) {
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
    foreach my $dd (values %D) {
	my %cvsdates;
	@cvsdates{@{$dd->{cvsdates}}} = ();
	@{$dd->{cvsdates}} = sort keys %cvsdates;
	my $cvsprev;
	foreach my $cvsdate (@{$dd->{cvsdates}}) {
	    if ($cvsprev) {
		my $cvslog = "cvslog/src/sys/$cvsprev--$cvsdate";
		unless (-f "$cvslog.txt" && -f "$cvslog.html") {
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
    foreach my $date (sort keys %D) {
	my $dv = $D{$date};
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

sub html_cvsdate_zoom {
    my ($html, $before, $after) = @_;
    my ($start, $stop) = @Z{$before, $after};
    my %dates;
    for (my $i = $start + 1; $i < $stop; $i++) {
	@dates{keys %{$Z[$i]}} = ();
    }
    return unless keys %dates;
    print $html "<table>\n";
    foreach my $date (reverse sort keys %dates) {
	my $short = $D{$date}{short};
	my $interval = $D{$date}{stepconf}{step};
	my $zoomtext = $short && $interval ?
	    "$short / $interval" : $short || $interval;
	$zoomtext =~ s/\s//g;
	my $time = encode_entities($date);
	my $datehtml = "$date/perform.html";
	my $link = uri_escape($datehtml, "^A-Za-z0-9\-\._~/");
	my $href = -f $datehtml ? "<a href=\"../$link\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html
	    "      <tr><td title=\"$time\">$href$zoomtext$enda</td></tr>\n";
    }
    print $html "    </table>";
}

sub html_repeat_top {
    my ($html, $date, $cvsdate, @repeats) = @_;
    my $hostcore = "$D{$date}{host}/$D{$date}{core}";
    print $html <<"HEADER";
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
    my $kerneltext = @repeats;
    my $kernelmode = $D{$date}{stepconf}{kernelmodes} ||
	$D{$date}{stepconf}{repmodes};
    if ($kernelmode) {
	$kerneltext = @repeats && @repeats > 1 ?
	    @repeats. " / $kernelmode" : $kernelmode;
    }
    $kerneltext =~ s/\s//g;
    my $build = $D{$date}{$cvsdate}{build};
    $build =~ s,[^/]+/[^/]+/,, if $build;
    my $link = uri_escape($build, "^A-Za-z0-9\-\._~/");
    my $href = $build ? "<a href=\"$link\">" : "";
    my $enda = $href ? " info</a>" : "";
    print $html "    <td>$href$kerneltext$enda</td>\n";
    print $html "  </tr>\n";
    print $html "</table>\n";
}

sub html_repeat_test_head {
    my ($html, $date, $cvsdate, @repeats) = @_;
    print $html "  <tr>\n    <th>repeat</th>\n";
    foreach my $repeat (@repeats) {
	print $html "    <th>$repeat</th>\n";
    }
    print $html "    <th></th><th></th><th></th><th></th><th></th>".
	"<th></th>\n";  # dummy for unit and stats below
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>machine</th>\n";
    my $kernelmode = $D{$date}{stepconf}{kernelmodes} ||
	$D{$date}{stepconf}{repmodes};
    foreach my $repeat (@repeats) {
	unless ($kernelmode) {
	    print $html "    <th></th>\n";
	    next;
	}
	my $reboot = $D{$date}{$cvsdate}{$repeat}{reboot};
	$reboot =~ s,[^/]+/[^/]+/,, if $reboot;
	my $link = uri_escape($reboot, "^A-Za-z0-9\-\._~/");
	my $href = $reboot ? "<a href=\"$link\">" : "";
	my $enda = $href ? " info</a>" : "";
	print $html "    <th>$href$kernelmode$enda</th>\n";
    }
    print $html "    <th></th><th></th><th></th><th></th><th></th>".
	"<th></th>\n";  # dummy for unit and stats below
    print $html "  </tr>\n";
}

sub html_repeat_test_row {
    my ($html, $date, $cvsdate, $test, $td, @repeats) = @_;
    print $html "  <tr>\n    <th>$test</th>\n";
    foreach my $repeat (@repeats) {
	html_status_data($html, "$date/$cvsdate", $repeat, $test,
	    $td->{$repeat});
    }
    foreach my $stat (qw(unit mean minimum maximum deviation relative)) {
	print $html "    <th>$stat</th>\n";
    }
    print $html "  </tr>\n";
    my $vt = $V{$date}{$test}{$cvsdate};
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
	    html_value_data($html, $i, $summary, $td->{$repeat},
		$vt->{$repeat});
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

sub html_cvsdate_top {
    my ($html, $date, @cvsdates) = @_;
    print $html <<"HEADER";
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
    my $log = $D{$date}{log};
    my $link = uri_escape($log, "^A-Za-z0-9\-\._~/");
    my $href = $log ? "<a href=\"$link\">" : "";
    my $enda = $href ? "</a>" : "";
    print $html "    <td>${href}log$enda</td>\n";
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>test host with cpu cores</th>\n";
    my $hostname = $D{$date}{host};
    my $core = $D{$date}{core};
    print $html "    <td>$hostname/$core</td>\n";
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>machine release setup</th>\n";
    my $setup = $D{$date}{setup};
    my $release = $D{$date}{stepconf}{release};
    my $setupmodes = $D{$date}{stepconf}{setupmodes} ||
	$D{$date}{stepconf}{modes};
    $link = uri_escape($setup, "^A-Za-z0-9\-\._~/");
    $href = $setup ? "<a href=\"../$link\">" : "";
    $enda = $href ? " info</a>" : "";
    print $html "    <td>$href$release/$setupmodes$enda</td>\n";
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>steps</th>\n";
    my $interval = $D{$date}{stepconf}{step};
    my $steptext = @cvsdates && $interval && @cvsdates > 1 ?
	@cvsdates. " / $interval" : @cvsdates || $interval;
    $steptext =~ s/\s//g;
    print $html "    <td>$steptext</td>\n";
    print $html "  </tr>\n";
    print $html "</table>\n";
}

sub html_cvsdate_test_head {
    my ($html, $date, @cvsdates) = @_;
    print $html "  <tr>\n    <th>cvs checkout</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $cvsshort = $D{$date}{$cvsdate}{cvsshort};
	my $time = encode_entities($cvsdate);
	my $cvsdatehtml = "$cvsdate/perform.html";
	my $link = uri_escape($cvsdatehtml, "^A-Za-z0-9\-\._~/");
	my $href = -f "$date/$cvsdatehtml" ? "<a href=\"$link\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html "    <th title=\"$time\">$href$cvsshort$enda</th>\n";
    }
    print $html "    <th></th><th></th><th></th><th></th><th></th>".
	"<th></th>\n";  # dummy for unit and stats below
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>machine</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $build = $D{$date}{$cvsdate}{build};
	$build =~ s,[^/]+/,, if $build;
	my $link = uri_escape($build, "^A-Za-z0-9\-\._~/");
	my $href = $build ? "<a href=\"$link\">" : "";
	my $enda = $href ? " info</a>" : "";
	print $html "    <th>${href}build$enda</th>\n";
    }
    print $html "    <th></th><th></th><th></th><th></th><th></th>".
	"<th></th>\n";  # dummy for unit and stats below
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>kernel build</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $version = $D{$date}{$cvsdate}{version};
	unless ($version) {
	    print $html "    <th></th>\n";
	    next;
	}
	my $kernel = encode_entities($D{$date}{$cvsdate}{kernel});
	$version =~ s,[^/]+/,,;
	my $link = uri_escape($version, "^A-Za-z0-9\-\._~/");
	print $html "    <th title=\"$kernel\">".
	    "<a href=\"$link\">version</a></th>\n";
    }
    print $html "    <th></th><th></th><th></th><th></th><th></th>".
	"<th></th>\n";  # dummy for unit and stats below
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>kernel commits</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $cvslog = $D{$date}{$cvsdate}{cvslog};
	unless ($cvslog) {
	    print $html "    <th></th>\n";
	    next;
	}
	my $title = "";
	if ($D{$date}{$cvsdate}{cvsfiles}) {
	    my %files;
	    @files{@{$D{$date}{$cvsdate}{cvsfiles}}} = ();
	    my $files = encode_entities(join(" ", sort keys %files));
	    $title = " title=\"$files\"";
	}
	my $link = uri_escape($cvslog, "^A-Za-z0-9\-\._~/");
	my $cvscommits = $D{$date}{$cvsdate}{cvscommits};
	my $num = defined($cvscommits) ? "/$cvscommits" : "";
	print $html "    <th$title><a href=\"../$link\">cvslog</a>$num</th>\n";
    }
    print $html "    <th></th><th></th><th></th><th></th><th></th>".
	"<th></th>\n";  # dummy for unit and stats below
    print $html "  </tr>\n";
    if (($D{$date}{stepconf}{kernelmodes} || "") eq "align") {
	print $html "  <tr>\n    <th>kernel name list</th>\n";
	foreach my $cvsdate (@cvsdates) {
	    my $nmstat = $D{$date}{$cvsdate}{nmstat};
	    unless ($nmstat) {
		print $html "    <th></th>\n";
		next;
	    }
	    my $difffile = $D{$date}{$cvsdate}{nmdiff};
	    my $link = uri_escape($difffile, "^A-Za-z0-9\-\._~/");
	    my $diffstat = "+$nmstat->{plus} -$nmstat->{minus}";
	    print $html "    <th><a href=\"../$link\">$diffstat</a></th>\n";
	}
	print $html "    <th></th><th></th><th></th><th></th><th></th>".
	    "<th></th>\n";  # dummy for unit and stats below
	print $html "  </tr>\n";
    }
    print $html "  <tr>\n    <th>build quirks</th>\n";
    my $prevcvsdate;
    my $qi = 65 + keys %{{quirks(undef, $cvsdates[0])}};
    foreach my $cvsdate (@cvsdates) {
	my $quirks = $D{$date}{$cvsdate}{quirks};
	print $html "    <th>";
	if ($quirks) {
	    $quirks =~ s,[^/]+/,,;
	    my $link = uri_escape($quirks, "^A-Za-z0-9\-\._~/");
	    print $html "<a href=\"$link\">quirks</a>";
	}
	if ($prevcvsdate) {
	    my @quirks = keys %{{quirks($prevcvsdate, $cvsdate)}};
	    print $html "/", join(",", map {
		    chr(($qi > 90? 6 + $qi++ : $qi++))
		} @quirks) if @quirks;
	}
	print $html "</th>\n";
	$prevcvsdate = $cvsdate;
    }
    print $html "    <th></th><th></th><th></th><th></th><th></th>".
	"<th></th>\n";  # dummy for unit and stats below
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>repetitions kernel mode</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $repeats = @{$D{$date}{$cvsdate}{repeats} || []} || "";
	my $kernelmode = $D{$date}{stepconf}{kernelmodes} ||
	    $D{$date}{stepconf}{repmodes};
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
    print $html "  <tr>\n    <th>zoom</th>\n";
    $prevcvsdate = undef;
    foreach my $cvsdate (@cvsdates) {
	print $html "    <th>";
	html_cvsdate_zoom($html, $prevcvsdate, $cvsdate) if $prevcvsdate;
	print $html "</th>\n";
	$prevcvsdate = $cvsdate;
    }
    print $html "    <th></th><th></th><th></th><th></th><th></th>".
	"<th></th>\n";  # dummy for unit and stats below
    print $html "  </tr>\n";
}

sub html_cvsdate_test_row {
    my ($html, $date, $test, $td, @cvsdates) = @_;
    print $html "  <tr>\n    <th>$test</th>\n";
    foreach my $cvsdate (@cvsdates) {
	html_status_data($html, $date, $cvsdate, $test, $td->{$cvsdate});
    }
    foreach my $stat (qw(unit mean minimum maximum deviation relative)) {
	print $html "    <th>$stat</th>\n";
    }
    print $html "  </tr>\n";
    my $vt = $V{$date}{$test};
    my @vals;
    foreach my $cvsdate (@cvsdates) {
	if ($D{$date}{$cvsdate}{repeats}) {
	    push @vals, map { $vt->{$cvsdate}{$_} }
		@{$D{$date}{$cvsdate}{repeats}}
	} else {
	    push @vals, $vt->{$cvsdate};
	}
    }
    my $maxval = max map { scalar @{$_ || []} } @vals;
    for (my $i = 0; $i < $maxval; $i++) {
	my $rp0 = $D{$date}{$cvsdates[0]}{repeats};
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
	    html_value_data($html, $i, $summary, $td->{$cvsdate},
		$vt->{$cvsdate});
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

sub html_value_data {
    my ($html, $i, $summary, $tv, $vv) = @_;
    unless ($tv && ($tv->{status} eq 'PASS' || ref($vv) eq 'HASH')) {
	print $html "    <td></td>\n";
	return;
    }
    my $number;
    my $title = "";
    my $class = "";
    if (ref($vv) eq 'HASH') {
	$number = $vv->{summary}[$i] // "";
	if ($number && $summary) {
	    my $reldev = ($number - $summary) / $summary;
	    $title = " title=\"$reldev\"";
	}
	$class = ' class="outlier"' if $vv->{outlier}[$i];
    } else {
	$number = $vv->[$i]{number};
	my $reldev = ($number - $summary) / $summary;
	$title = " title=\"$reldev\"";
	$class = ' class="outlier"' if abs($reldev) >= 0.1;
    }
    print $html "    <td$title$class>$number</td>\n";
}

sub html_date_top {
    my ($html) = @_;
    print $html <<"HEADER";
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
}

sub html_date_test_head {
    my ($html, @dates) = @_;
    print $html "  <tr>\n    <th>run</th>\n";
    foreach my $date (@dates) {
	my $short = $D{$date}{short};
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
	my $hostname = $D{$date}{host};
	my $core = $D{$date}{core};
	print $html "    <th>$hostname/$core</th>\n";
    }
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>release setup</th>\n";
    foreach my $date (@dates) {
	my $release = $D{$date}{stepconf}{release};
	my $setupmodes = $D{$date}{stepconf}{setupmodes} ||
	    $D{$date}{stepconf}{modes};
	print $html "    <th>$release/$setupmodes</th>\n";
    }
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>first cvs checkout</th>\n";
    foreach my $date (@dates) {
	my $cvsdate = $D{$date}{cvsdates}[0];
	my $cvsshort = $D{$date}{$cvsdate}{cvsshort};
	my $time = encode_entities($cvsdate);
	print $html "    <th title=\"$time\">$cvsshort</th>\n";
    }
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>last cvs checkout</th>\n";
    foreach my $date (@dates) {
	my $cvsdate = $D{$date}{cvsdates}[-1];
	my $cvsshort = $D{$date}{$cvsdate}{cvsshort};
	my $time = encode_entities($cvsdate);
	print $html "    <th title=\"$time\">$cvsshort</th>\n";
    }
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>steps</th>\n";
    foreach my $date (@dates) {
	my $steps = @{$D{$date}{cvsdates}};
	my $interval = $D{$date}{stepconf}{step};
	my $steptext = $steps && $interval && $steps > 1 ?
	    "$steps / $interval" : $steps || $interval;
	$steptext =~ s/\s//g;
	print $html "    <th>$steptext</th>\n";
    }
    print $html "  </tr>\n";
    print $html "  <tr>\n    <th>repetitions kernel mode</th>\n";
    foreach my $date (@dates) {
	my $cvsdate0 = $D{$date}{cvsdates}[0];
	my $repeats = @{$D{$date}{$cvsdate0}{repeats} || []} || "";
	my $kernelmode = $D{$date}{stepconf}{kernelmodes} ||
	    $D{$date}{stepconf}{repmodes};
	my $kerneltext = $repeats;
	if ($kernelmode) {
	    $kerneltext = $repeats && $repeats > 1 ?
		"$repeats / $kernelmode" : $kernelmode;
	}
	$kerneltext =~ s/\s//g;
	print $html "    <th>$kerneltext</th>\n";
    }
    print $html "  </tr>\n";
}

sub html_date_test_row {
    my ($html, $test, $td, @dates) = @_;
    print $html "  <tr>\n    <th>$test</th>\n";
    foreach my $date (@dates) {
	html_status_data($html, ".", $date, $test, $td->{$date});
    }
    print $html "  </tr>\n";
}

sub html_status_data {
    my ($html, $dir, $subdir, $test, $tv) = @_;
    unless ($tv) {
	print $html "    <td></td>\n";
	return;
    }
    my $status = $tv->{status};
    my $class = " class=\"status $status\"";
    my $message = encode_entities($tv->{message});
    my $title = $message ? " title=\"$message\"" : "";
    my $href = "";
    my $logfile = "$subdir/logs/$test.log";
    if (-f "$dir/$logfile") {
	my $link = uri_escape($logfile, "^A-Za-z0-9\-\._~/");
	$href = "<a href=\"$link\">";
    }
    my $subhtml = "$subdir/perform.html";
    if (-f "$dir/$subhtml") {
	my $link = uri_escape($subhtml, "^A-Za-z0-9\-\._~/");
	$href = "<a href=\"$link\">";
    }
    my $enda = $href ? "</a>" : "";
    print $html "    <td$class$title>$href$status$enda</td>\n";
}

sub html_plot_data {
    my ($plot, $prefix, $dir) = @_;
    my $file = "";
    $file .= "$dir/" if $dir;
    $file .= "gnuplot/";
    $file .= "$prefix-" if $prefix;
    $file .= $plot;
    my $href = "$file.html";
    my $src = "$file.png";
    my $alt = uc($plot)." Performance";
    print $html <<IMAGE;
    <td>
      <a href="$href">
	<img src="$src" alt="$alt">
      </a>
    </td>
IMAGE
}
