#!/usr/bin/perl
# convert all performance results to a html table

# Copyright (c) 2018-2021 Alexander Bluhm <bluhm@genua.de>
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
use Testvars qw(@PLOTORDER %TESTPLOT %TESTORDER %TESTDESC);

my $fgdir = "/home/bluhm/github/FlameGraph";  # XXX

my $now = strftime("%FT%TZ", gmtime);

my %opts;
getopts('d:Ggnv', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-Gg] [-d date]
    -d date	run date of performance test, may be current
    -G		do not regenerate any gnuplot files, allows faster debugging
    -g		generate all gnuplot files, even if they already exist
    -n		do not generate gnuplot files on main release page
    -v		verbose
EOF
    exit(2);
};
!$opts{d} || $opts{d} eq "current" || str2time($opts{d})
    or die "Invalid -d date '$opts{d}'";
my $date = $opts{d};
my $verbose = $opts{v};
$| = 1 if $verbose;

print "glob result files" if $verbose;
my $performdir = dirname($0). "/..";
chdir($performdir)
    or die "Change directory to '$performdir' failed: $!";
$performdir = getcwd();
my $resultdir = "$performdir/results";
if ($date && $date eq "current") {
    my $current = readlink("$resultdir/$date")
	or die "Read link '$resultdir/$date' failed: $!";
    -d "$resultdir/$current"
	or die "Test directory '$resultdir/$current' failed: $!";
    $date = $current;
}
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";
if ($date && $date eq "current") {
    my $current = readlink("$resultdir/$date")
	or die "Read link '$resultdir/$date' failed: $!";
    -d "$resultdir/$current"
	or die "Test directory '$resultdir/$current' failed: $!";
    $date = $current;
}

# create the html and gnuplot files only for a single date
my $dateglob = ($opts{n} && $date) ? $date : "*";
# cvs checkout and repeated results
print "." if $verbose;
my @result_files = sort(glob("$dateglob/*/test.result"),
    glob("$dateglob/*/*/test.result"));
print "\n" if $verbose;

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
# $T{$test}{$date}{$cvsdate}{kstack}{btrace}	flame graph svg stack
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
# $V{$date}{$test}{$cvsdate}{summary}[$value]	array of numbers
# %Z @Z
# $Z{$cvsdate}				index in @Z
# $Z[$index]				hash of dates containing cvs checkout
# $B{$date}{$cvsdate}{$test}{kstack}	btrace kstack output file

my (%T, %D, %V, %Z, @Z, %B);
print "parse result files" if $verbose;
parse_result_files(@result_files);
print "\nwrite data files" if $verbose;
write_data_files($opts{n} && $date);
unless ($opts{G}) {
    print "\ncreate gnuplot files" if $verbose;
    create_gnuplot_files($date);
}
print "\ncreate cvslog files" if $verbose;
create_cvslog_files($date);
print "\ncreate nmbsd files" if $verbose;
create_nmbsd_files($date);
print "\ncreate btrace files" if $verbose;
create_btrace_files($date);
print "\n" if $verbose;

my @plots = list_plots();
my @tests = list_tests();
my @dates = list_dates($date);

# html per date per cvsdate with repetitions

print "create html per repeat files" if $verbose;
foreach my $date (@dates) {
    my $short = $D{$date}{short};
    foreach my $cvsdate (@{$D{$date}{cvsdates}}) {
	print "." if $verbose;
	my $cvsshort = $D{$date}{$cvsdate}{cvsshort};
	my @repeats = sort @{$D{$date}{$cvsdate}{repeats} || []}
	    or next;

	my ($html, $htmlfile) = html_open("$date/$cvsdate/perform");
	my @nav = (
	    Top      => "../../../../test.html",
	    All      => "../../perform.html",
	    Checkout => "../perform.html",
	    Repeat   => undef,
	    Running  => "../../run.html");
	html_header($html, "OpenBSD Perform Repeat",
	    "OpenBSD perform $short checkout $cvsshort repeat test results",
	    @nav);
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
print "\n" if $verbose;

# html per date with cvsdate

print "create html per cvsdate files" if $verbose;
foreach my $date (@dates) {
    print "." if $verbose;
    my $short = $D{$date}{short};
    my @cvsdates = @{$D{$date}{cvsdates}};

    my ($html, $htmlfile) = html_open("$date/perform");
    my @nav = (
	Top      => "../../../test.html",
	All      => "../perform.html",
	Checkout => undef,
	Repeat   => undef,
	Running  => "../run.html");
    html_header($html, "OpenBSD Perform CVS",
	"OpenBSD perform $short checkout test results",
	@nav);
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
	next unless -f "$date/gnuplot/$plot.png";
	print $html "  <tr class=\"IMG\">\n";
	html_plot_data($html, $plot);
	print $html "  </tr>\n";
    }
    print $html "</table>\n";

    html_quirks_table($html, $html);
    html_status_table($html, "perform");
    html_footer($html);
    html_close($html, $htmlfile);
}
print "\n" if $verbose;

exit if $opts{n};

# html with date

# the main page must contain all dates, call without specific date
@dates = list_dates();

print "create html per cvsdate files" if $verbose;
my ($html, $htmlfile) = html_open("perform");
my @nav = (
    Top     => "../../test.html",
    All     => undef,
    Current => (-f "current/perform.html" ? "current/perform.html" : undef),
    Latest  => (-f "latest/perform.html" ? "latest/perform.html" : undef),
    Running => "run.html");
html_header($html, "OpenBSD Perform Results",
    "OpenBSD perform all test results",
    @nav);
html_date_top($html);

print $html "<table>\n";
html_date_test_head($html, @dates);
foreach my $test (@tests) {
    my $td = $T{$test};
    html_date_test_row($html, $test, $td, @dates);
}
print $html "</table>\n";
print "." if $verbose;

print $html "<table>\n";
foreach my $plot (@plots) {
    print $html "  <tr>\n";
    print $html "    <th></th>\n";
    print $html "    <th>all</th>\n";
    my @releases = sort keys %{{quirk_releases()}};
    for (my $i = 0; $i <= $#releases; $i++) {
	my $prev = $releases[$i];
	my $next = $releases[$i+1] || "";
	print $html "    <th>release $prev -> $next</th>\n";
    }
    print $html "  </tr>\n";
    print $html "  <tr class=\"IMG\">\n";
    print $html "    <th>". uc($plot). "</th>\n";
    html_plot_data($html, $plot);
    foreach my $release (@releases) {
	html_plot_data($html, $plot, $release);
    }
    print $html "  </tr>\n";
}
print $html "</table>\n";

html_quirks_table($html);
html_status_table($html, "perform");
html_footer($html);
html_close($html, $htmlfile);
print "\n" if $verbose;

exit;

# fill global hashes %T %D %V %Z @Z
sub parse_result_files {
    foreach my $result (@_) {
	# parse result file
	my ($date, $short, $cvsdate, $repeat) = $result =~
	    m,
		(([^/]+)T[^/]+Z)/			# date
		([^/]+T[^/]+Z|patch-[^/]+\.\d+)/	# cvsdate or patch
		(?:(\d+|btrace-[^/]+\.\d+)/)?		# repeat or btrace
		test.result				# result file
	    ,x or next;
	next if ! $opts{n} && $cvsdate =~ /^patch-/;
	my ($cvsshort, $repshort) = ($cvsdate, $repeat);
	$cvsshort =~ s/T.+Z$//;
	$cvsshort =~ s/^patch-(.*)\.\d+$/$1/;
	$repshort =~ s/^btrace-(.*)\.\d+$/$1/ if $repeat;
	print "." if $verbose;
	$D{$date}{short} ||= $short;
	push @{$D{$date}{cvsdates} ||= []}, $cvsdate unless $D{$date}{$cvsdate};
	$D{$date}{$cvsdate}{cvsshort} ||= $cvsshort;
	if (defined $repeat) {
	    push @{$D{$date}{$cvsdate}{repeats} ||= []}, $repeat;
	    $D{$date}{$cvsdate}{$repeat}{repshort} ||= $repshort;
	    $D{$date}{$cvsdate}{$repeat}{result} = $result;
	} else {
	    $D{$date}{$cvsdate}{result} = $result;
	}
	$D{$date}{log} ||= "step.log" if -f "$date/step.log";
	$D{$date}{$cvsdate}{log} ||= "once.log" if -f "$date/$cvsdate/once.log";
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
		if ($repeat =~ /^btrace-/ &&
		    -f "$date/$cvsdate/$repeat/logs/$test-$repshort.btrace") {
			$B{$date}{$cvsdate}{$test}{$repeat} =
			    "$date/$cvsdate/$repeat/logs/$test-$repshort.btrace"
		}
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
	    (my $diff = $version) =~ s,/version-,/diff-,;
	    $D{$date}{$cvsdate}{diff} ||= $diff if -f $diff;

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

sub list_plots {
    return @PLOTORDER;
}

# write test results into gnuplot data file
sub write_data_files {
    my @dates = shift || sort keys %V;
    my $testdata = "gnuplot/test";
    if ($opts{n} && @dates == 1) {
	$testdata = "$dates[0]/$testdata";
    } else {
	unlink map { glob("$_/$testdata-*.data") } @dates;
    }
    my $gnuplotdir = dirname($testdata);
    -d $gnuplotdir || mkdir $gnuplotdir
	or die "Make directory '$gnuplotdir' failed: $!";
    my %plotfh;
    @plotfh{values %TESTPLOT} = ();
    foreach my $plot (keys %plotfh) {
	open($plotfh{$plot}, '>', "$testdata-$plot.data.new")
	    or die "Open '$testdata-$plot.data.new' for writing failed: $!";
	print {$plotfh{$plot}}
	    "# test subtest run checkout repeat value unit host\n";
    }
    my $fh;
    unless ($opts{n}) {
	open($fh, '>', "test.data.new")
	    or die "Open 'test.data.new' for writing failed: $!";
	print $fh "# test subtest run checkout repeat value unit host\n";
    }
    foreach my $date (@dates) {
	my $vd = $V{$date};
	my $run = str2time($date);
	foreach my $test (sort keys %$vd) {
	    print "." if $verbose;
	    my $vt = $vd->{$test};
	    my $checkout;
	    foreach my $cvsdate (sort keys %$vt) {
		next if $testdata =~ /^gnuplot/ && $cvsdate =~ /^patch-/;
		my $vc = $vt->{$cvsdate};
		$checkout = str2time($cvsdate) || $checkout + 1;
		$vc = { 0 => $vc } if ref $vc ne 'HASH';
		foreach my $repeat (sort keys %$vc) {
		    next if $repeat =~ /^btrace-/;
		    my $vr = $vc->{$repeat};
		    foreach my $value (@{$vr || []}) {
			my $number = $value->{number};
			my $unit = $value->{unit};
			my $subtest = $value->{name} || "unknown";
			my $hostname = $D{$date}{host};
			print $fh "$test $subtest ".
			    "$run $checkout $repeat $number $unit $hostname\n"
			    if $fh;
			print {$plotfh{$TESTPLOT{$test}}} "$test $subtest ".
			    "$run $checkout $repeat $number $unit $hostname\n"
			    if $TESTPLOT{$test};
		    }
		}
	    }
	}
    }
    if ($fh) {
	print "." if $verbose;
	close($fh)
	    or die "Close 'test.data.new' after writing failed: $!";
	rename("test.data.new", "test.data")
	    or die "Rename 'test.data.new' to 'test.data' failed: $!";
	system("gzip -f -c test.data >test.data.gz.new")
	    and die "Gzip test.data failed: $?";
	rename("test.data.gz.new", "test.data.gz")
	    or die "Rename 'test.data.gz.new' to 'test.data.gz' failed: $!";
    }
    foreach my $plot (keys %plotfh) {
	my $datafile = "$testdata-$plot.data";
	close($plotfh{$plot})
	    or die "Close '$datafile.new' after writing failed: $!";
	rename("$datafile.new", $datafile)
	    or die "Rename '$datafile.new' to '$datafile' failed: $!";
    }
}

sub list_tests {
    foreach my $test (keys %T) {
	next if $TESTORDER{$test};
	warn "testorder missing test $test\n";
	$TESTORDER{$test} = 0;
    }
    return reverse sort { $TESTORDER{$b} <=> $TESTORDER{$a} } keys %T;
}

sub list_dates {
    my @dates = shift || reverse sort keys %D;
    return @dates;
}

# create gnuplot graphs for all runs
sub create_gnuplot_files {
    my @dates = shift || reverse sort keys %V;
    my ($first, $last);
    if (@dates == 1) {
	my @cvsdates = sort @{$D{$dates[0]}{cvsdates}};
	$first = $cvsdates[0];
	$last = $cvsdates[-1];
    }
    my %releases = quirk_releases();
    foreach my $plot (list_plots()) {
	next if $opts{n};
	print "." if $verbose;
	my @cmd = ("$performdir/bin/gnuplot.pl", "-p", "$plot");
	system(@cmd)
	    and die "Command '@cmd' failed: $?";
	foreach my $rel (reverse sort keys %releases) {
	    my $v = $releases{$rel};
	    next if $first && $v->{end} && $first gt $v->{end};
	    next if $last && $v->{begin} && $last lt $v->{begin};
	    print "." if $verbose;
	    @cmd = ("$performdir/bin/gnuplot.pl", "-p", "$plot", "-r", $rel);
	    push @cmd, "-B", $v->{begin} if $v->{begin};
	    push @cmd, "-E", $v->{end} if $v->{end};
	    system(@cmd)
		and die "Command '@cmd' failed: $?";
	}
    }
    foreach my $date (@dates) {
	foreach my $plot (list_plots()) {
	    next if !$opts{d} && !$opts{g} && -f "$date/gnuplot/$plot.png";
	    print "." if $verbose;
	    my @cmd = ("$performdir/bin/gnuplot.pl", "-p", "$plot",
		"-d", $date);
	    system(@cmd)
		and die "Command '@cmd' failed: $?";
	}
    }
}

# create cvs log file with commits after previous cvsdates
sub create_cvslog_files {
    my @dates = shift || reverse sort keys %D;
    foreach my $dd (@D{@dates}) {
	my %cvsdates;
	@cvsdates{@{$dd->{cvsdates}}} = ();
	@{$dd->{cvsdates}} = sort keys %cvsdates;
	my $prevcvsdate;
	foreach my $cvsdate (@{$dd->{cvsdates}}) {
	    # patch tests have no cvs checkout
	    str2time($cvsdate) or next;
	    if ($prevcvsdate) {
		(my $year = $prevcvsdate) =~ s/-.*//;
		my $cvslog = "cvslog/$year/src/sys/$prevcvsdate--$cvsdate";
		unless (-f "$cvslog.txt" && -f "$cvslog.html") {
		    print "." if $verbose;
		    my @cmd = ("$performdir/bin/cvslog.pl",
			"-B", $prevcvsdate, "-E", $cvsdate, "-P", "src/sys");
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
	    $prevcvsdate = $cvsdate;
	}
    }
}

sub create_nmbsd_files {
    my @dates = shift || reverse sort keys %D;
    foreach my $date (@dates) {
	my $dv = $D{$date};
	next if ($dv->{stepconf}{kernelmodes} || "") ne "align";
	my $hostname = $dv->{host};
	my $prevnmfile;
	foreach my $cvsdate (sort @{$dv->{cvsdates}}) {
	    my $cv = $dv->{$cvsdate};
	    my $nmfile = "$date/$cvsdate/nm-bsd-$hostname.txt";
	    next unless -r $nmfile;
	    if ($prevnmfile) {
		print "." if $verbose;
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
    my ($prev, $cur, $difffile, $stat) = @_;

    my (@cmd, $diff, $fh);
    if (-f $difffile) {
	# if diff file has already been created, reading is faster
	open($diff, '<', "$difffile")
	    or die "Open '$difffile' for reading failed: $!";
    } else {
	@cmd = ('diff', '-up', $prev, $cur);
	open($diff, '-|', @cmd)
	    or die "Open pipe from '@cmd' failed: $!";
	open($fh, '>', "$difffile.new")
	    or die "Open '$difffile.new' for writing failed: $!";
    }

    # diff header
    print $fh $_ if defined($_ = <$diff>) && $fh;
    print $fh $_ if defined($_ = <$diff>) && $fh;
    my ($plus, $minus) = (0, 0);
    while (<$diff>) {
	$plus++ if /^\+/;
	$minus++ if /^-/;
	print $fh $_ if $fh;
    }
    $stat->{plus} = $plus;
    $stat->{minus} = $minus;

    if ($fh) {
	unless (close($diff)) {
	    die "Close pipe from '@cmd' failed: $!" if $!;
	    die "Command '@cmd' failed: $?" if $? != 0 && $? != 256;
	}
	close($fh)
	    or die "Close '$difffile.new' after writing failed: $!";
	rename("$difffile.new", $difffile)
	    or die "Rename '$difffile.new' to '$difffile' failed: $!";
    }
}

sub create_btrace_files {
    my @dates = shift || reverse sort keys %B;
    foreach my $date (@dates) {
	my $dv = $B{$date}
	    or next;
	foreach my $cvsdate (sort keys %{$dv}) {
	    my $cv = $dv->{$cvsdate};
	    my $btdir = "$date/$cvsdate/btrace";
	    -d $btdir || mkdir $btdir
		or die "Make directory '$btdir' failed: $!";
	    foreach my $test (sort keys %{$cv}) {
		my $tv = $cv->{$test};
		foreach my $stack (sort keys %{$tv}) {
		    my $btfile = $tv->{$stack};
		    my $svgfile = "$btdir/$test-$stack.svg";
		    $T{$test}{$date}{$cvsdate}{$stack}{btrace} = $stack;
		    next if -f $svgfile;
		    print "." if $verbose;
		    my $fgcmd = "$fgdir/stackcollapse-bpftrace.pl <$btfile | ".
			"$fgdir/flamegraph.pl >$svgfile.new";
		    system($fgcmd)
			and die "Command '$fgcmd' failed: $?";
		    rename("$svgfile.new", $svgfile)
			or die "Rename '$svgfile.new' to '$svgfile' failed: $!";
		}
	    }
	}
    }
}

sub html_cvsdate_zoom {
    my ($html, $before, $after) = @_;
    my ($start, $stop) = @Z{$before, $after};
    return unless defined($start) && defined($stop);
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
    print $html <<"HEADER";
<table>
  <tr>
    <th>created at</th>
    <td>$now</td>
  </tr>
  <tr>
    <th>run at</th>
    <td><a href="../../$date/$cvsdate/perform.html">$date</a></td>
  </tr>
HEADER
    print $html "  <tr>\n    <th>run</th>\n";
    my $log = $D{$date}{$cvsdate}{log};
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
    print $html "  <tr>\n    <th>cvs checkout at</th>\n";
    print $html "    <td>$cvsdate</td>\n";
    print $html "  </tr>\n";
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
    $link = uri_escape($build, "^A-Za-z0-9\-\._~/");
    $href = $build ? "<a href=\"$link\">" : "";
    $enda = $href ? " info</a>" : "";
    print $html "    <td>$href$kerneltext$enda</td>\n";
    print $html "  </tr>\n";
    print $html "</table>\n";
}

sub html_repeat_test_head {
    my ($html, $date, $cvsdate, @repeats) = @_;
    print $html "  <tr>\n    <td></td>\n";
    print $html "    <th>repeat</th>\n";
    foreach my $repeat (@repeats) {
	my $repshort = $D{$date}{$cvsdate}{$repeat}{repshort};
	my $rep_btrace = encode_entities($repeat);
	print $html "    <th title=\"$rep_btrace\">$repshort</th>\n";
    }
    print $html "    <th></th><th></th><th></th><th></th><th></th>".
	"<th></th>\n";  # dummy for unit and stats below
    print $html "  </tr>\n";
    print $html "  <tr>\n    <td></td>\n";
    print $html "    <th>machine</th>\n";
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
    (my $testcmd = $test) =~ s/_/ /g;
    print $html "  <tr>\n    <th class=\"desc\">$TESTDESC{$test}</th>\n";
    print $html "    <td class=\"test\"><code>$testcmd</code></td>\n";
    foreach my $repeat (@repeats) {
	html_status_data($html, "$date/$cvsdate", $repeat, $test,
	    $td->{$repeat});
    }
    foreach my $stat (qw(unit mean minimum maximum deviation relative)) {
	print $html "    <th>$stat</th>\n";
    }
    print $html "  </tr>\n";
    my $vt = $V{$date}{$test}{$cvsdate};
    my @repeats_nobtrace = grep { /^\d+$/ } @repeats;
    my @btraces;
    @btraces = map { ref eq 'HASH' && $_->{btrace} ? $_->{btrace} : () }
	values %$td if @repeats_nobtrace != @repeats;
    my $maxval = max map { scalar @{$vt->{$_} || []} } @repeats_nobtrace;
    for (my $i = 0; $i < $maxval; $i++) {
	my $value0 = first { $_ } map { $vt->{$_}[$i] } @repeats_nobtrace;
	my ($name0, $unit0) = ($value0->{name}, $value0->{unit});
	print $html "  <tr>\n    <td></td>\n";
	print $html "    <th>$name0</th>\n";
	my @numbers = map { $vt->{$_}[$i]{number} }
	    grep { $td->{$_} && $td->{$_}{status} eq 'PASS' } @repeats_nobtrace;
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
	    $relative = $mean != 0 ? $deviation / $mean : 0;
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
	} else {
	    print $html "    <td></td><td></td><td></td><td></td><td></td>".
		"<td></td>\n";  # dummy for unit and stats above
	}
	print $html "  </tr>\n";
    }
    if (@btraces) {
	print $html "  <tr>\n    <th></th>\n";
	print $html "    <th>btrace</th>\n";
	foreach my $repeat (@repeats) {
	    html_btrace_link($html, "$date/$cvsdate", "", $test,
		$td->{$repeat}{btrace} || ());
	}
	print $html "    <td></td><td></td><td></td><td></td><td></td>".
	    "<td></td>\n";  # dummy for unit and stats above
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
    <td><a href="../$date/perform.html">$date</a></td>
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
    print $html "  <tr>\n    <td></td>\n";
    print $html "    <th>cvs checkout</th>\n";
    foreach my $cvsdate (@cvsdates) {
	my $cvsshort = $D{$date}{$cvsdate}{cvsshort};
	my $cvs_patch = encode_entities($cvsdate);
	my $cvsdatehtml = "$cvsdate/perform.html";
	my $link = uri_escape($cvsdatehtml, "^A-Za-z0-9\-\._~/");
	my $href = -f "$date/$cvsdatehtml" ? "<a href=\"$link\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html "    <th title=\"$cvs_patch\">$href$cvsshort$enda</th>\n";
    }
    print $html "    <th></th><th></th><th></th><th></th><th></th>".
	"<th></th>\n";  # dummy for unit and stats below
    print $html "  </tr>\n";
    print $html "  <tr>\n    <td></td>\n";
    print $html "    <th>machine</th>\n";
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
    if (grep { ref eq 'HASH' && $_->{version} } values %{$D{$date}} ) {
	print $html "  <tr>\n    <td></td>\n";
	print $html "    <th>kernel build</th>\n";
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
    }
    if (grep { ref eq 'HASH' && $_->{cvslog} } values %{$D{$date}} ) {
	print $html "  <tr>\n    <td></td>\n";
	print $html "    <th>kernel commits</th>\n";
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
	    print $html
		"    <th$title><a href=\"../$link\">cvslog</a>$num</th>\n";
	}
	print $html "    <th></th><th></th><th></th><th></th><th></th>".
	    "<th></th>\n";  # dummy for unit and stats below
	print $html "  </tr>\n";
    }
    if (grep { ref eq 'HASH' && $_->{diff} } values %{$D{$date}} ) {
	print $html "  <tr>\n    <td></td>\n";
	print $html "    <th>kernel patches</th>\n";
	foreach my $cvsdate (@cvsdates) {
	    my $diff = $D{$date}{$cvsdate}{diff};
	    unless ($diff) {
		print $html "    <th></th>\n";
		next;
	    }
	    my $link = uri_escape($diff, "^A-Za-z0-9\-\._~/");
	    print $html "    <th><a href=\"../$link\">diff</a></th>\n";
	}
	print $html "    <th></th><th></th><th></th><th></th><th></th>".
	    "<th></th>\n";  # dummy for unit and stats below
	print $html "  </tr>\n";
    }
    if (grep { ref eq 'HASH' && $_->{nmstat} } values %{$D{$date}} ) {
	print $html "  <tr>\n    <td></td>\n";
	print $html "    <th>kernel name list</th>\n";
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
    if (grep { ref eq 'HASH' && $_->{quirks} } values %{$D{$date}} ) {
	print $html "  <tr>\n    <td></td>\n";
	print $html "    <th>build quirks</th>\n";
	my $prevcvsdate;
	my $index = keys %{{quirks(undef, $cvsdates[0])}};
	foreach my $cvsdate (@cvsdates) {
	    unless (str2time($cvsdate)) {
		print $html "    <th></th>\n";
		next;
	    }
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
			quirk_index2letters($index++)
		    } @quirks) if @quirks;
	    }
	    print $html "</th>\n";
	    $prevcvsdate = $cvsdate;
	}
	print $html "    <th></th><th></th><th></th><th></th><th></th>".
	    "<th></th>\n";  # dummy for unit and stats below
	print $html "  </tr>\n";
    }
    if (grep { ref eq 'HASH' && $_->{repeats} } values %{$D{$date}} ) {
	print $html "  <tr>\n    <td></td>\n";
	print $html "    <th>repetitions kernel mode</th>\n";
	my $kernelmode = $D{$date}{stepconf}{kernelmodes} ||
	    $D{$date}{stepconf}{repmodes};
	foreach my $cvsdate (@cvsdates) {
	    my $repeats = @{$D{$date}{$cvsdate}{repeats} || []} || "";
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
    }
    if (grep { str2time($_) } @cvsdates > 1) {
	print $html "  <tr>\n    <td></td>\n";
	print $html "    <th>zoom</th>\n";
	my $prevcvsdate;
	foreach my $cvsdate (@cvsdates) {
	    unless (str2time($cvsdate)) {
		print $html "    <th></th>\n";
		next;
	    }
	    print $html "    <th>";
	    html_cvsdate_zoom($html, $prevcvsdate, $cvsdate) if $prevcvsdate;
	    print $html "</th>\n";
	    $prevcvsdate = $cvsdate;
	}
	print $html "    <th></th><th></th><th></th><th></th><th></th>".
	    "<th></th>\n";  # dummy for unit and stats below
	print $html "  </tr>\n";
    }
}

sub html_cvsdate_test_row {
    my ($html, $date, $test, $td, @cvsdates) = @_;
    (my $testcmd = $test) =~ s/_/ /g;
    print $html "  <tr>\n    <th class=\"desc\">$TESTDESC{$test}</th>\n";
    print $html "    <td class=\"test\"><code>$testcmd</code></td>\n";
    foreach my $cvsdate (@cvsdates) {
	html_status_data($html, $date, $cvsdate, $test, $td->{$cvsdate});
    }
    foreach my $stat (qw(unit mean minimum maximum deviation relative)) {
	print $html "    <th>$stat</th>\n";
    }
    print $html "  </tr>\n";
    my $vt = $V{$date}{$test};
    my (@vals, @btraces);
    foreach my $cvsdate (@cvsdates) {
	if ($D{$date}{$cvsdate}{repeats}) {
	    push @vals, map { $vt->{$cvsdate}{$_} }
		@{$D{$date}{$cvsdate}{repeats}}
	} else {
	    push @vals, $vt->{$cvsdate};
	}
	push @btraces,
	    map { ref eq 'HASH' && $_->{btrace} ? $_->{btrace} : () }
	    values %{$td->{$cvsdate}} if $td->{$cvsdate};
    }
    my $maxval = max map { scalar @{$_ || []} } @vals;
    for (my $i = 0; $i < $maxval; $i++) {
	my $rp0 = $D{$date}{$cvsdates[0]}{repeats};
	my $value0 = $rp0 ?
	    first { $_ } map { $vt->{$cvsdates[0]}{$_}[$i] } @$rp0 :
	    first { $_ } map { $vt->{$_}[$i] } @cvsdates;
	my ($name0, $unit0) = ($value0->{name}, $value0->{unit});
	print $html "  <tr>\n    <td></td>\n";
	print $html "    <th>$name0</th>\n";
	my @numbers = map { ref($vt->{$_}) eq 'HASH' ?
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
	    $relative = $mean != 0 ? $deviation / $mean : 0;
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
	} else {
	    print $html "    <td></td><td></td><td></td><td></td><td></td>".
		"<td></td>\n";  # dummy for unit and stats above
	}
	print $html "  </tr>\n";
    }
    if (@btraces) {
	print $html "  <tr>\n    <th></th>\n";
	print $html "    <th>btrace</th>\n";
	foreach my $cvsdate (@cvsdates) {
	    html_btrace_link($html, $date, $cvsdate, $test,
		$td->{$cvsdate} ?
		map { ref eq 'HASH' && $_->{btrace} ? $_->{btrace} : () }
		values %{$td->{$cvsdate}} : ());
	}
	print $html "    <td></td><td></td><td></td><td></td><td></td>".
	    "<td></td>\n";  # dummy for unit and stats above
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
	if ($number && $summary && $summary != 0) {
	    my $reldev = ($number - $summary) / $summary;
	    $title = " title=\"$reldev\"";
	}
	$class = ' class="outlier"' if $vv->{outlier}[$i];
    } else {
	$number = $vv->[$i]{number};
	if ($number && $summary && $summary != 0) {
	    my $reldev = ($number - $summary) / $summary;
	    $title = " title=\"$reldev\"";
	    $class = ' class="outlier"' if abs($reldev) >= 0.1;
	}
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
</table>
HEADER
}

sub html_date_test_head {
    my ($html, @dates) = @_;
    print $html "  <tr>\n    <td></td>\n";
    print $html "    <th>run</th>\n";
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
    print $html "  <tr>\n    <td></td>\n";
    print $html "    <th>host cores</th>\n";
    foreach my $date (@dates) {
	my $hostname = $D{$date}{host};
	my $core = $D{$date}{core};
	print $html "    <th>$hostname/$core</th>\n";
    }
    print $html "  </tr>\n";
    print $html "  <tr>\n    <td></td>\n";
    print $html "    <th>release setup</th>\n";
    foreach my $date (@dates) {
	my $release = $D{$date}{stepconf}{release};
	my $setupmodes = $D{$date}{stepconf}{setupmodes} ||
	    $D{$date}{stepconf}{modes};
	print $html "    <th>$release/$setupmodes</th>\n";
    }
    print $html "  </tr>\n";
    print $html "  <tr>\n    <td></td>\n";
    print $html "    <th>first cvs checkout</th>\n";
    foreach my $date (@dates) {
	my $cvsdate = $D{$date}{cvsdates}[0];
	my $cvsshort = $D{$date}{$cvsdate}{cvsshort};
	my $cvs_patch = encode_entities($cvsdate);
	print $html "    <th title=\"$cvs_patch\">$cvsshort</th>\n";
    }
    print $html "  </tr>\n";
    print $html "  <tr>\n    <td></td>\n";
    print $html "    <th>last cvs checkout</th>\n";
    foreach my $date (@dates) {
	my $cvsdate = $D{$date}{cvsdates}[-1];
	my $cvsshort = $D{$date}{$cvsdate}{cvsshort};
	my $cvs_patch = encode_entities($cvsdate);
	print $html "    <th title=\"$cvs_patch\">$cvsshort</th>\n";
    }
    print $html "  </tr>\n";
    print $html "  <tr>\n    <td></td>\n";
    print $html "    <th>steps</th>\n";
    foreach my $date (@dates) {
	my $steps = @{$D{$date}{cvsdates}};
	my $interval = $D{$date}{stepconf}{step};
	my $steptext = $steps && $interval && $steps > 1 ?
	    "$steps / $interval" : $steps || $interval;
	$steptext =~ s/\s//g;
	print $html "    <th>$steptext</th>\n";
    }
    print $html "  </tr>\n";
    print $html "  <tr>\n    <td></td>\n";
    print $html "    <th>repetitions kernel mode</th>\n";
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
    (my $testcmd = $test) =~ s/_/ /g;
    print $html "  <tr>\n    <th class=\"desc\">$TESTDESC{$test}</th>\n";
    print $html "    <td class=\"test\"><code>$testcmd</code></td>\n";
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

sub html_btrace_link {
    my ($html, $dir, $subdir, $test, @stacks) = @_;
    unless (@stacks) {
	print $html "    <td></td>\n";
	return;
    }
    my @svgs;
    foreach my $stack (@stacks) {
	my $svgfile = "btrace/$test-$stack.svg";
	$svgfile = "$subdir/$svgfile" if $subdir;
	my $link = uri_escape($svgfile, "^A-Za-z0-9\-\._~/");
	my $href = -f "$dir/$svgfile" ? "<a href=\"$link\">" : "";
	my $enda = $href ? "</a>" : "";
	$stack =~ s/^btrace-//;
	push @svgs, "$href$stack$enda";
    }
    print $html "    <td>", join(" ", sort @svgs), "</td>\n";
}

sub html_plot_data {
    my ($html, $plot, $release) = @_;
    my $prefix = "gnuplot/";
    $prefix .= "$release-" if $release;
    $prefix .= $plot;
    my $src = "$prefix.png";
    my $href = "$prefix.html";
    my $alt = uc($plot)." Performance";
    print $html <<"IMAGE";
    <td>
      <a href="$href">
	<img src="$src" alt="$alt">
      </a>
    </td>
IMAGE
}
