#!/usr/bin/perl
# convert netlink test results to html tables

# Copyright (c) 2016-2025 Alexander Bluhm <bluhm@genua.de>
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
use File::Find;
use File::Glob qw(:bsd_glob);
use HTML::Entities;
use Getopt::Std;
use List::Util qw(first max min sum);
use POSIX;
use URI::Escape;

use lib dirname($0);
use Html;
use Testvars qw(%TESTNAME %TESTDESC @TESTKEYS);

my $fgdir = "/home/bluhm/github/FlameGraph";  # XXX

my %IFTYPERATES = (
    "iface-bge"  =>       10 ** 9,
    "iface-bnxt" =>  10 * 10 ** 9,
    "iface-dwqe" =>       10 ** 9,
    "iface-em"   =>       10 ** 9,
    "iface-ice"  => 100 * 10 ** 9,  # slower devices exist
    "iface-igc"  => 2.5 * 10 ** 9,  # slower devices exist
    "iface-ix"   =>  10 * 10 ** 9,
    "iface-ixl"  =>  25 * 10 ** 9,  # slower devices exist
    "iface-re"   =>  .1 * 10 ** 9,
    "iface-vio"  =>  50 * 10 ** 9,
    "iface-vmx"  =>  20 * 10 ** 9,
);
# more specific dmesg entries
my %DMESGRATES = (
    qr/\Q"Intel I225-IT"/       =>   1 * 10 ** 9,  # igc
    qr/\Q"Intel I225-LM"/       => 2.5 * 10 ** 9,  # igc
    qr/\Q"Intel E810-XXV SFP"/  =>  25 * 10 ** 9,  # ice
    qr/\Q"Intel E810 XXV SFP"/  =>  25 * 10 ** 9,  # legacy name
    qr/\Q"Intel E810-C QSFP"/   => 100 * 10 ** 9,  # ice
    qr/\Q"Intel E810 C QSFP"/   => 100 * 10 ** 9,  # legacy name
    qr/\Q"Intel X710 10GBaseT"/ =>  10 * 10 ** 9,  # ixl
    qr/\Q"Intel X710 SFP+"/     =>  10 * 10 ** 9,  # ixl
    qr/\Q"Intel XXV710 SFP28"/  =>  25 * 10 ** 9,  # ixl
);

my $now = strftime("%FT%TZ", gmtime);

my @allifaces = qw(bge bnxt em ice igc ix ixl re vio vmx);

my %opts;
getopts('d:h:lv', \%opts) or do {
    print STDERR <<"EOF";
usage: netlink-html.pl [-lv] [-d date] [-h host]
    -d date	run date of netlink test, may be current or latest host
    -h host	user and host for version information, user defaults to root
    -l		create latest.html with one column of the latest results
    -v		verbose
EOF
    exit(2);
};
my $date = $opts{d};
my $verbose = $opts{v};
$| = 1 if $verbose;
@ARGV and die "No arguments allowed";

my $netlinkdir = dirname($0). "/..";
chdir($netlinkdir)
    or die "Change directory to '$netlinkdir' failed: $!";
$netlinkdir = getcwd();
my $resultdir = "$netlinkdir/results";
if ($date && $date =~ /^(current|latest|latest-\w+)$/) {
    my $current = readlink("$resultdir/$date")
	or die "Read link '$resultdir/$date' failed: $!";
    -d "$resultdir/$current"
	or die "Test directory '$resultdir/$current' failed: $!";
    $date = basename($current);
}
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

my ($user, $host) = split('@', $opts{h} || "", 2);
($user, $host) = ("root", $user) unless $host;

my @HIERARCHY = qw(date iface cvsdate patch modify pseudo btrace repeat);
my @HIERS;
my (%T, %D, %H, %V, %S, %B);

# %T
# $test				test command as executed by netlink
# $desc				generic test description as defined by testvars
# $T{$desc}{severity}		weighted severity of all failures of this test
# $date				date and time when test was executed as string
# $T{$desc}{$date}(test}		test command in a specifc test run
# $T{$desc}{$date}{$hk}{status}		result of this test at that day
# $T{$desc}{$date}{$hk}{message}	test printed a duration or summary
# $T{$desc}{$date}{$hk}{logfile}	relative path to net.log for hyper link
# $T{$desc}{$date}{$hk}{stats}		relative path to stats diff file
# $T{$desc}{$date}{$hk}{btrace}		name of btrace, usually ktrace
# $T{$desc}{$date}{$hk}{svgfile}	relative path to btrace-kstat.svg file
# %D
# $date				date and time when test was executed as string
# $D{$date}{pass}		percentage of not skipped tests that passed
# $D{$date}{short}		date without time
# $D{$date}{result}		path to test.result file
# $D{$date}{setup}		relative path to setup.html for hyper link
# $D{$date}{version}		relative path to version.txt for hyper link
# $D{$date}{host}		hostname of the machine running the regress
# $D{$date}{dmesg}		path to dmesg.txt of machine running regress
# $D{$date}{diff}		path to diff.txt custom build kernel cvs diff
# $D{$date}{kernel}		sysctl kernel version string
# $D{$date}{kerntime}		build time in kernel version string
# $D{$date}{location}		user at location of kernel build
# $D{$date}{build}		snapshot or custom build
# $D{$date}{arch}		sysctl hardware machine architecture
# $D{$date}{ncpu}		sysctl hardware ncpu cores
# $D{$data}{rate}{$ifname}	bit rate of interface according to dmesg
# $S{$test}{$hk}{stdir}		directory of stats diff output file
# $S{$test}{$hk}{stinput}	array of statistics input files
# $S{$test}{$hk}{stats}		relative path to stats-diff.txt
# $B{$test}{$hk}{btdir}		directory of btrace output file
# $B{$test}{$hk}{btfile}	btrace input file
# $B{$test}{$hk}{btrace}	name of btrace, usually ktrace
# $B{$test}{$hk}{svgfile}	relative path to btrace-kstat.svg file

{
    print "glob result files" if $verbose;
    my @results = glob_result_files($date);
    print "\nparse result files" if $verbose;
    parse_result_files(@results);
}
print "\ncreate stats files" if $verbose;
create_stats_files();
print "\ncreate btrace files" if $verbose;
create_btrace_files();

print "\ncreate html hier files" if $verbose;
write_html_hier_files();
print "\nwrite html date file" if $verbose;
if ($opts{d}) {
    print "\n" if $verbose;
    exit;
}
write_html_date_file();
print "\n" if $verbose;

exit;

sub html_hier_top {
    my ($html, $date, @cvsdates) = @_;
    my $dv = $D{$date};
    my $setup = $dv->{setup};
    my $link = uri_escape($setup, "^A-Za-z0-9\-\._~/");
    my $href = $setup ? "<a href=\"../$link\">" : "";
    my $enda = $href ? "</a>" : "";
    my $hostname = $dv->{host};
    my $ncpu = $dv->{ncpu};
    print $html <<"HEADER";
<table>
  <tr>
    <th>created at</th>
    <td>$now</td>
  </tr>
  <tr>
    <th>run at</th>
    <td><a href="../$date/netlink.html">$date</a></td>
  </tr>
  <tr>
    <th>test host with cpu cores</th>
    <td>$hostname/$ncpu</td>
  </tr>
  <tr>
    <th>machine setup</th>
    <td>${href}info$enda</td>
  </tr>
</table>
HEADER
}

sub html_hier_test_head {
    my ($html, $dv, @hiers) = @_;

    foreach my $hier (@HIERS) {
	print $html "  <tr>\n";
	print $html "    <td>$hier</td>\n";
	foreach my $hv (@hiers) {
	    my $title = "";
	    my $name = $hv->{$hier} || "";
	    if ($hier =~ /date$/) {
		my $time = encode_entities($name);
		$title = "  title=\"$time\"";
		$name =~ s/T.*//;
	    } elsif ($hier eq "iface" && $dv->{ifdmesg}) {
		my $ifdmesg = encode_entities($dv->{ifdmesg}{$name});
		$title = "  title=\"$ifdmesg\"";
	    } elsif ($hier eq "patch" && $hv->{diff}) {
		my $link = uri_escape($hv->{diff}, "^A-Za-z0-9\-\._~/");
		$name = "<a href=\"../$link\">$name</a>";
	    } else {
		$name =~ s/.*-none$//;
	    }
	    print $html "    <th class=\"hier\"$title>$name</th>\n";
	}
	print $html "    <th></th>\n  </tr>\n";
    }
}

sub html_hier_test_head_utilization {
    my ($html, $dv, @hiers) = @_;

    foreach my $hier (@HIERS) {
	my $te = $hier eq "date" ? "th" : "td";
	print $html "  <tr>\n";
	print $html "    <td></td>", "<td></td>" x @TESTKEYS, "\n";
	foreach my $hv (@hiers) {
	    my $title = "";
	    my $name = $hv->{$hier} || "";
	    if ($hier =~ /date$/) {
		my $time = encode_entities($name);
		$title = "  title=\"$time\"";
		$name =~ s/T.*//;
	    } elsif ($hier eq "iface" && $dv->{ifdmesg}) {
		my $ifdmesg = encode_entities($dv->{ifdmesg}{$name});
		$title = "  title=\"$ifdmesg\"";
	    } elsif ($hier eq "patch" && $hv->{diff}) {
		my $link = uri_escape($hv->{diff}, "^A-Za-z0-9\-\._~/");
		$name = "<a href=\"../$link\">$name</a>";
	    } else {
		$name =~ s/.*-none$//;
	    }
	    print $html "    <$te class=\"hier $hier\"$title>$name</$te>\n";
	}
	print $html "    <th></th>\n  </tr>\n";
    }
    print $html "  <tr>\n";
    print $html "    <td></td>", "<td></td>" x @TESTKEYS, "\n";
    foreach my $hv (@hiers) {
	my $iface = $hv->{iface};
	unless ($iface) {
	    printf $html "    <td style=\"background-color: red\"></td>\n";
	    next;
	}
	(my $iftype = $iface) =~ s/\d+$//;
	my $rate = $dv->{rate}{$iface} || $IFTYPERATES{$iftype};
	unless ($rate) {
	    printf $html "    <td style=\"background-color: red\"></td>\n";
	    next;
	}
	my $bits = "$rate bit";
	$bits =~ s/000 bit$/ Kbit/;
	$bits =~ s/000 Kbit$/ Mbit/;
	$bits =~ s/000 Mbit$/ Gbit/;
	$bits =~ s/000 Gbit$/ Tbit/;
	my $style = " style=\"background-color: rgba(128, 255, 128, 1.0)\"";
	print $html "    <td class=\"hier bits\"$style>$bits</td>\n";
    }
    print $html "    <th></th>\n  </tr>\n";
}

sub html_hier_test_row {
    my ($html, $desc, $td, @hiers) = @_;

    my $test = $td->{test};
    my $testcmd = $desc;
    my $testname = $TESTNAME{$desc} || "";
    print $html "  <tr>\n";
    print $html "    <th class=\"desc\" id=\"$desc\" title=\"$testcmd\">".
	"$testname</th>\n";
    foreach my $hv (@hiers) {
	my $tv = $td->{$hv->{key}};
	my $status = $tv->{status} || "";
	my $class = " class=\"status $status\"";
	my $message = encode_entities($tv->{message});
	my $title = $message ? " title=\"$message\"" : "";
	my $logfile = $tv->{logfile};
	my $link = uri_escape($logfile, "^A-Za-z0-9\-\._~/");
	my $href = $logfile ? "<a href=\"../$link\">" : "";
	my $enda = $href ? "</a>" : "";
	my $stats = $tv->{stats};
	my $stats_link = uri_escape($stats, "^A-Za-z0-9\-\._~/");
	my $stats_href = $stats ?
	    "<a style='float: right' href=\"../$stats_link\">stats</a>" : "";

	print $html "    <td$class$title>$href$status$enda$stats_href</td>\n";
    }
    ($testcmd = $test) =~ s/_/ /g;
    $testcmd =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;  # uri_unescape
    print $html "    <td class=\"test\"><code>$testcmd</code></td>\n";
    print $html "  </tr>\n";

    my $vt = $V{$desc};
    my $maxval = max map { scalar @{$_ || []} } values %$vt;
    for (my $i = 0; $i < $maxval; $i++) {
	my $value0 = first { $_ } map { $_->[$i] } values %$vt;
	my ($name0, $unit0) = ($value0->{name}, $value0->{unit});
	print $html "  <tr>\n";
	print $html "    <td><code>$name0</code></td>\n";
	foreach my $hv (@hiers) {
	    my $tv = $td->{$hv->{key}};
	    if ($tv && ($tv->{status} =~ /^X?PASS$/)) {
		my $vv = $vt->{$hv->{key}};
		print $html "    <td>$vv->[$i]{number}</td>\n";
	    } else {
		print $html "    <td></td>\n";
	    }
	}
	print $html "    <td>$unit0</td>\n  </tr>\n";
    }
    if ($B{$test}) {
	print $html "  <tr>\n";
	print $html "    <td><code>btrace</code></td>\n";
	foreach my $hv (@hiers) {
	    my $tv = $td->{$hv->{key}};
	    my $btrace = $tv->{btrace};
	    if ($btrace) {
		my $svgfile = $tv->{svgfile};
		my $link = uri_escape("../$svgfile", "^A-Za-z0-9\-\._~/");
		my $href = -f $svgfile ? "<a href=\"$link\">" : "";
		my $enda = $href ? "</a>" : "";
		print $html "    <td>$href$btrace$enda</td>\n";
	    } else {
		print $html "    <td></td>\n";
	    }
	}
	print $html "    <th></th>\n  </tr>\n";
    }
}

sub html_hier_test_row_utilization {
    my ($html, $dv, $desc, $td, @hiers) = @_;

    my $test = $td->{test};
    my $testcmd = $desc;
    my $testname = $TESTNAME{$desc} || "";
    my $vt = $V{$desc};
    my $maxval = max map { scalar @{$_ || []} } values %$vt;

    my $valsum = 0;
    foreach my $hv (@hiers) {
	my $tv = $td->{$hv->{key}}
	    or next;
	my $status = $tv->{status} || "NONE";
	$status =~ /^X?PASS$/
	    or next;
	for (my $i = 0; $i < $maxval; $i++) {
	    my $value0 = first { $_ } map { $_->[$i] } values %$vt;
	    if (($value0 && $value0->{name} =~ /^(recv|receiver|rx)$/) ||
		$maxval == 1) {
		    my $vv = $vt->{$hv->{key}};
		    $valsum += $vv->[$i]{number};
	    }
	}
    }
    return if ($valsum == 0);

    print $html "  <tr>\n";
    print $html "    <th class=\"desc name\" title=\"$testcmd\">".
	"$testname</th>\n";
    foreach my $testkey (@TESTKEYS) {
	print $html "    <td class=\"desc $testkey\">".
	    "$TESTDESC{$desc}{$testkey}</td>\n";
    }
    foreach my $hv (@hiers) {
	my $tv = $td->{$hv->{key}};
	my $status = $tv->{status} || "NONE";
	my ($unit, $iface, $value);
	for (my $i = 0; $i < $maxval; $i++) {
	    my $value0 = first { $_ } map { $_->[$i] } values %$vt;
	    if ($value0->{name} =~ /^(recv|receiver|rx)$/ || $maxval == 1) {
		$unit = $value0->{unit} || "";
		$iface = $hv->{iface};
		if ($status =~ /^X?PASS$/) {
		    my $vv = $vt->{$hv->{key}};
		    $value = $vv->[$i]{number};
		}
	    }
	}
	unless (defined $value) {
	    printf $html "    <td class=\"status $status\"></td>\n";
	    next;
	}
	my $title = " title=\"$value $unit\"";
	my $class = " class=\"status $status\"";
	(my $iftype = $iface) =~ s/\d+$//;
	my $linerate = $dv->{rate}{$iface} || $IFTYPERATES{$iftype} || 10 ** 9;
	my $rate = $value / $linerate;
	my $rgb = $status eq 'PASS' ? "128, 255, 128" : "255, 128, 192";
	my $style = sprintf(
	    " style=\"background-color: rgba($rgb, %.1f)\"", $rate);
	my ($href, $enda) = ("", "");
	if ($tv->{btrace}) {
	    my $svgfile = $tv->{svgfile};
	    my $link = uri_escape("../$svgfile", "^A-Za-z0-9\-\._~/");
	    $link =~ s,%,%%,g;  # printf escape
	    $href = -f $svgfile ? "<a href=\"$link\">" : "";
	    $enda = $href ? "</a>" : "";
	}
	printf $html "    <td$class$style$title>$href%.1f%%$enda</td>\n",
	    $rate * 100;
    }
    ($testcmd = $test) =~ s/_/ /g;
    $testcmd =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;  # uri_unescape
    print $html "    <td class=\"test\"><code>$testcmd</code></td>\n";
    print $html "  </tr>\n";
}

sub write_html_hier_files {
    my @dates = reverse sort keys %D;
    foreach my $date (@dates) {
	print "." if $verbose;
	my $dv = $D{$date};
	my $short = $dv->{short};

	my ($html, $htmlfile) = html_open("$date/netlink");
	my @nav = (
	    Top     => "../../../test.html",
	    All     => (-f "netlink.html" ? "../netlink.html" : undef),
	    Current => "../current/netlink.html",
	    Latest  => "../latest.html",
	    Running => "../run.html");
	html_header($html, "OpenBSD Netlink Hierarchie",
	    "OpenBSD netlink $short test results",
	    @nav);
	print $html "<script src='/tables.js'></script>\n";

	my @hv = sort { $a->{key} cmp $b->{key} } @{$H{$date}};
	html_hier_top($html, $date, @hv);

	print $html "<table>\n";
	print $html "  <thead>\n";
	html_hier_test_head($html, $dv, @hv);
	print $html "  </thead>\n  <tbody>\n";

	# most frequent and severe errors at top
	my @tests = sort { $T{$b}{severity} <=> $T{$a}{severity} ||
	    $TESTNAME{$a} cmp $TESTNAME{$b} } keys %T;
	foreach my $desc (@tests) {
	    my $td = $T{$desc}{$date}
		or next;
	    html_hier_test_row($html, $desc, $td, @hv);
	}
	print $html "  </tbody>\n";
	print $html "</table>\n";

	print $html "<table class='utilization'>\n";
	print $html "  <thead>\n";
	html_hier_test_head_utilization($html, $dv, @hv);
	print $html "  </thead>\n  <tbody>\n";

	# use the execution order to find interference between tests
	@tests = sort { $T{$b}{order} <=> $T{$a}{order} ||
	    $TESTNAME{$a} cmp $TESTNAME{$b} } keys %T;
	foreach my $desc (@tests) {
	    my $td = $T{$desc}{$date}
		or next;
	    html_hier_test_row_utilization($html, $dv, $desc, $td, @hv);
	}
	print $html "  </tbody>\n";
	print $html "</table>\n";

	html_status_table($html, "netlink");
	html_footer($html);
	html_close($html, $htmlfile);
    }
}

sub write_html_date_file {
    my $file = $opts{l} ? "latest" : "netlink";
    $file .= "-$host" if $host;
    my ($html, $htmlfile) = html_open($file);
    my $topic = $host ? ($opts{l} ? "latest $host" : $host) :
	($opts{l} ? "latest" : "all");

    my $typename = "Netlink";
    my @nav = (
	Top     => "../../test.html",
	All     => (($opts{l} || $host) && -f "netlink.html" ?
	    "netlink.html" : undef),
	Current => "current/netlink.html",
	Latest  => ($opts{l} ? undef : "latest/netlink.html"),
	Running => "run.html");
    html_header($html, "OpenBSD $typename Results",
	"OpenBSD ". lc($typename). " $topic test results",
	@nav);

    print $html <<"HEADER";
<table>
  <tr>
    <th>created at</th>
    <td>$now</td>
  </tr>
</table>
HEADER

    print "." if $verbose;
    my @dates = reverse sort keys %D;
    print $html "<table>\n";
    print $html "  <thead>\n";
    print $html "  <tr>\n    <td>pass rate</td>\n";
    foreach my $date (@dates) {
	my $passrate = $D{$date}{pass};
	$passrate /= $D{$date}{total} if $D{$date}{total};
	my $percent = "";
	$percent = sprintf("%d%%", 100 * $passrate) if defined $passrate;
	print $html "    <th>$percent</th>\n";
    }
    print $html "    <th></th>\n  <tr>\n    <td>run at date</td>\n";
    foreach my $date (@dates) {
	my $short = $D{$date}{short};
	my $time = encode_entities($date);
	my $hierhtml = "$date/netlink.html";
	my $link = uri_escape($hierhtml, "^A-Za-z0-9\-\._~/");
	my $href = -f $hierhtml ? "<a href=\"$link\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html "    <th title=\"$time\">$href$short$enda</th>\n";
    }
    print $html "    <th></th>\n  <tr>\n    <td>sub runs</td>\n";
    foreach my $date (@dates) {
	my $num = @{$H{$date}};
	print $html "    <th>$num</th>\n";
    }
    print $html "    <th></th>\n  <tr>\n    <td>machine</td>\n";
    foreach my $date (@dates) {
	my $setup = $D{$date}{setup};
	my $link = uri_escape($setup, "^A-Za-z0-9\-\._~/");
	my $href = $setup ? "<a href=\"$link\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html "    <th>${href}setup info$enda</th>\n";
    }
    print $html "    <th></th>\n  <tr>\n    <td>architecture</td>\n";
    foreach my $date (@dates) {
	my $arch = $D{$date}{arch};
	my $dmesg = $D{$date}{dmesg};
	my $link = uri_escape($dmesg, "^A-Za-z0-9\-\._~/");
	my $href = $dmesg ? "<a href=\"$link\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html "    <th>$href$arch$enda</th>\n";
    }
    print $html "    <th></th>\n  <tr>\n    <td>host</td>\n";
    foreach my $date (@dates) {
	my $hostname = $D{$date}{host};
	my $hostlink;
	if (!$host || $opts{l}) {
	    $hostlink = "netlink-$hostname.html";
	    undef $hostlink unless -f $hostlink;
	}
	my $href = $hostlink ? "<a href=\"$hostlink\">" : "";
	my $enda = $href ? "</a>" : "";
	print $html "    <th>$href$hostname$enda</th>\n";
    }
    print $html "    <th></th>\n  </tr>\n";
    print $html "  </thead>\n  <tbody>\n";

    my @tests = sort { $T{$b}{severity} <=> $T{$a}{severity} ||
	$TESTNAME{$a} cmp $TESTNAME{$b} } keys %T;
    foreach my $desc (@tests) {
	print "." if $verbose;
	my $testcmd = $desc;
	my $testname = $TESTNAME{$desc} || "";
	print $html "  <tr>\n";
	print $html "    <th class=\"desc\" id=\"$desc\" title=\"$testcmd\">".
	    "$testname</th>\n";
	foreach my $date (@dates) {
	    my $tv = $T{$desc}{$date};
	    my $status = $tv->{status} || "";
	    my $class = " class=\"status $status\"";
	    my $message = encode_entities($tv->{message});
	    my $title = $message ? " title=\"$message\"" : "";
	    my $hierhtml = "$date/netlink.html";
	    my $link = uri_escape($hierhtml, "^A-Za-z0-9\-\._~/");
	    $link .= "#$desc";
	    my $href = -f $hierhtml ? "<a href=\"$link\">" : "";
	    my $enda = $href ? "</a>" : "";
	    if ($tv->{test}) {
		($testcmd = $tv->{test}) =~ s/_/ /g;
		$testcmd =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;  # uri_unescape
	    }
	    print $html "    <td$class$title>$href$status$enda</td>\n";
	}
	print $html "    <td class=\"test\"><code>$testcmd</code></td>\n";
	print $html "  </tr>\n";
    }
    print $html "  </tbody>\n";
    print $html "</table>\n";

    html_status_table($html, "netlink");
    html_footer($html);
    html_close($html, $htmlfile);
}

sub glob_result_files {
    my ($date) = @_;

    print "." if $verbose;

    my @files;
    my $wanted = sub {
	/^test.result$/ or return;
	my %f;
	$File::Find::dir =~ s,^\./,,;
	$File::Find::name =~ s,^\./,,;
	my @dirs = split(m,/,, $File::Find::dir);
	$_ = shift @dirs;
	unless (defined && /^[0-9-]+T[0-9:]+Z/) {
	    warn "Invalid date '$_' in result '$File::Find::name'";
	    return;
	}
	$f{date} = $_;
	$_ = shift @dirs;
	if (defined && /^[0-9-]+T[0-9:]+Z$/) {
	    $f{cvsdate} = $_;
	    $_ = shift @dirs;
	}
	if (defined && /^patch-/) {
	    $f{patch} = $_;
	    $_ = shift @dirs;
	}
	if (defined && /^modify-/) {
	    $f{modify} = $_;
	    $_ = shift @dirs;
	}
	if (defined && /^iface-/) {
	    $f{iface} = $_;
	    $_ = shift @dirs;
	}
	if (defined && /^pseudo-/) {
	    $f{pseudo} = $_;
	    $_ = shift @dirs;
	}
	if (defined && /^[0-9]{3}$/) {
	    $f{repeat} = $_;
	    $_ = shift @dirs;
	}
	if (defined && /^btrace-/) {
	    $f{btrace} = $_;
	    $_ = shift @dirs;
	}
	if (defined) {
	    warn "Invalid subdir '$_' in result '$File::Find::name'";
	    return;
	}
	$f{dir} = $File::Find::dir;
	$f{name} = $File::Find::name;
	push @files, \%f;
    };

    if ($opts{l}) {
	my @latest;
	if ($host) {
	    @latest = "latest-$host";
	    -d $latest[0]
		or die "No latest test.result for $host";
	} else {
	    @latest = grep { -d } bsd_glob("latest-*", GLOB_NOSORT);
	}
	find($wanted, map { (readlink($_) or die
	    "Readlink latest '$_' failed: $!") }  @latest);
	return sort { $a->{dir} cmp $b->{dir} } @files;
    }

    # create the html files only for a single date
    my $dateglob = $date ? $date : "*T*Z";

    find($wanted, bsd_glob($dateglob, GLOB_NOSORT));
    if ($host) {
	return sort { $a->{dir} cmp $b->{dir} }
	    grep { -f "$_->{date}/version-$host.txt" } @files;
    } else {
	return sort { $a->{dir} cmp $b->{dir} } @files;
    }
}

# fill global @HIERS and hashes %T %D %H %V %S %B
sub parse_result_files {
    my %alliftypes;
    @alliftypes{@allifaces} = ();

    my %testdesc;
    my %usedhiers;
    foreach my $file (@_) {
	print "." if $verbose;

	# parse result file
	my ($date, $short) = $file->{date} =~ m,^(([^/]+)T[^/]+Z)$,
	    or next;
	my $dv = $D{$date} ||= {
	    short => $short,
	    result => $file->{name},
	    pass => 0,
	    total => 0,
	};
	$dv->{setup} = "$date/setup.html" if -f "$date/setup.html";
	$_->{severity} *= .5 foreach values %T;
	my %hiers;
	foreach my $hier (@HIERARCHY) {
	    my $subdir = $file->{$hier}
		or next;
	    $hiers{$hier} = $subdir;
	    $usedhiers{$hier}++;
	}
	my $hk = join($;, map { local $_ = $file->{$_} || ""; s/-none$/-/; $_; }
	    @HIERARCHY);
	$hiers{key} = $hk;
	my $hv = $H{$date} ||= [];
	push @$hv, \%hiers;
	my ($total, $pass) = (0, 0);
	open(my $fh, '<', $file->{name})
	    or die "Open '$file->{name}' for reading failed: $!";
	my @values;
	my $order = 0;
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
	    if ($test =~ /{multiple}/) {
		my %sum;
		foreach my $v (@values) {
		    $sum{$v->{name},$v->{unit}} += $v->{number};
		}
		undef @values;
		foreach my $k (sort keys %sum) {
		    my ($n, $u, $v) = (split($;, $k), $sum{$k});
		    push @values, {
			name => $n,
			unit => $u,
			number => $v,
		    };
		}
	    }
	    my $desc = $testdesc{$test};
	    unless ($desc) {
		($desc = $test) =~ s/_/ /g;
		$desc =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;  # uri_unescape
		# direct ssh login happens only to client
		$desc =~ s/(?<=^ssh[ _])root\@lt[0-9]+(?=[ _])/{left}/g;
		if ($desc =~ /^netbench\.pl[ _]/) {
		    # netbench does client and server login
		    $desc =~ s/(?<=[ _]-c)root\@lt[0-9]+(?=[ _])/{left}/g;
		    $desc =~ s/(?<=[ _]-s)root\@lt[0-9]+(?=[ _])/{right}/g;
		    # multicast interfaces depend on test and hardware
		    $desc =~ s/(?<=[ _]-[RS])[1-9][0-9.]+(?=[ _])/{ifaddr}/g;
		    $desc =~ s/(?<=[ _]-[RS])[a-z][a-z0-9.]+(?=[ _])/{ifname}/g;
		}
		if ($desc =~ /iperf3[ _]/) {
		    # iperf needs fine tuning of window size, do not care
		    $desc =~ s/(?<=[ _])-w\d+[kmgt]?(?=[ _])/{window}/g;
		}
		# netlink line is after ipv4 or ipv6 prefix
		$desc =~ s/\.10\.[0-9](?=[0-9]\.)/.10.{line}/g;
		$desc =~ s/:10[0-9](?=[0-9]:)/:10{line}/g;
		$desc =~ s/(?<![0-9.])10\.10\./{prefix}/g;
		$desc =~ s/(?<![:])fdd7:e83e:66bd:10/{prefix}/g;
		$testdesc{$test} = $desc;
	    }
	    my $tv = $T{$desc}{$date}{$hk} ||= {};
	    $tv->{status}
		and warn "Duplicate test '$test' at '$file->{name}'";
	    $tv->{status} = $status;
	    $tv->{message} = $message;
	    my $logfile = "$file->{dir}/logs/$test.log";
	    $tv->{logfile} = $logfile if -f $logfile;
	    (my $stfile = $logfile) =~ s,\.log$,.stats-*-diff.txt,;
	    my @stinput = bsd_glob($stfile, 0);
	    if (@stinput) {
		my $difffile = "$file->{dir}/stats/$test.stats-diff.txt";
		$tv->{stats} = $difffile;
		$S{$test}{$hk} = {
		    stdir    => "$file->{dir}/stats",
		    stinput  => \@stinput,
		    difffile => $difffile,
		} unless -f $difffile;
	    }
	    if ($file->{btrace}) {
		(my $btrace = $file->{btrace}) =~ s,btrace-([^/]*)\.\d+,$1,;
		(my $btfile = $logfile) =~ s,\.log$,-$btrace.btrace,;
		my $svgfile = "$file->{dir}/btrace/$test-btrace-$btrace.svg";
		$tv->{btrace} = $btrace if -s $btfile;
		$tv->{svgfile} = $svgfile;
		my $bt = $B{$test} ||= {};
		$bt->{$hk} = {
		    btdir   => "$file->{dir}/btrace",
		    btfile  => $btfile,
		    btrace  => $btrace,
		    svgfile => $svgfile,
		} if -s $btfile && ! -f $svgfile;
	    }
	    $V{$desc}{$hk} = [ splice @values ];
	    my $severity = status2severity($status);
	    $T{$desc}{severity} += $severity;
	    $total++ unless $status eq 'SKIP' || $status eq 'XFAIL';
	    $pass++ if $status eq 'PASS';
	    $tv = $T{$desc}{$date};
	    $tv->{test} = $test;
	    if (($tv->{severity} || 0) < $severity) {
		$tv->{status} = $status;
		$tv->{severity} = $severity;
	    }
	    $order--;
	    if (($T{$desc}{order} || 0) > $order) {
		$T{$desc}{order} = $order;
	    }
	}
	close($fh)
	    or die "Close '$file->{name}' after reading failed: $!";
	$dv->{pass} += $pass;
	$dv->{total} += $total;

	# parse version file
	foreach my $version (bsd_glob("$date/version-*.txt", 0)) {
	    $version =~ m,/version-(.+)\.txt$,;
	    my $hostname = $1;

	    next if $dv->{version};
	    $dv->{version} = $version;
	    $dv->{host} ||= $hostname;
	    (my $dmesg = $version) =~ s,/version-,/dmesg-,;
	    $dv->{dmesg} ||= $dmesg if -f $dmesg;
	    (my $dmesgboot = $version) =~ s,version,dmesg-boot,;
	    $dv->{dmesgboot} ||= $dmesgboot if -f $dmesgboot;

	    %$dv = (parse_version_file($version), %$dv);
	}
	if ($file->{patch}) {
	    foreach my $diff (bsd_glob("$date/$file->{patch}/diff-*.txt", 0)) {
		$hiers{diff} ||= $diff if -s $diff;
	    }
	}
	$dv->{build} = ($dv->{location} =~ /^deraadt@\w+.openbsd.org:/) ?
	    "snapshot" : "custom";
	if ($dv->{dmesgboot}) {
	    my %ifdmesg;
	    open(my $dh, '<', $dv->{dmesgboot})
		or die "Open '$dv->{dmesgboot}' for reading failed: $!";
	    while (<$dh>) {
		# parse only latest copy of dmesg from current boot
		undef %ifdmesg if /^OpenBSD/;
		# collect known interfaces
		/^(([a-z]+)\d+) at / && exists $alliftypes{$2}
		    or next;
		chomp;
		$ifdmesg{"iface-$1"} = $_;
	    }
	    while (my ($iface, $dmesg) = each %ifdmesg) {
		while (my ($re, $rate) = each %DMESGRATES) {
		    next unless $dmesg =~ /$re/;
		    $dv->{rate}{$iface} = $rate;
		    last;
		}
	    }
	    $dv->{ifdmesg} = \%ifdmesg;
	}
    }
    @HIERS = grep { $usedhiers{$_} } @HIERARCHY;
}

sub create_stats_files {
    my @tests = reverse sort keys %S;
    foreach my $test (@tests) {
	my $tv = $S{$test};
	foreach my $hk (sort keys %$tv) {
	    print "." if $verbose;
	    my $hv = $tv->{$hk};
	    my $stdir = $hv->{stdir};
	    -d $stdir || mkdir $stdir
		or die "Make directory '$stdir' failed: $!";
	    my $difffile = $hv->{difffile};
	    open(my $out, '>', "$difffile.new")
		or die "Open '$difffile.new' for writing failed: $!";
	    foreach my $stat (@{$hv->{stinput}}) {
		open(my $in, '<', $stat)
		    or die "Open '$stat' for reading failed: $!";
		while (<$in>) {
			print $out $_;
		}
	    }
	    close($out)
		or die "Close '$difffile.new' after writing failed: $!";
	    rename("$difffile.new", $difffile)
		or die "Rename '$difffile.new' to '$difffile' failed: $!";
	    my @gzcmd = (qw(gzip -f -k -S .gz.new), $difffile);
	    system(@gzcmd)
		and die "Gzip '@gzcmd' failed: $?";
	    rename("$difffile.gz.new", "$difffile.gz") or die
		"Rename '$difffile.gz.new' to '$difffile.gz' failed: $!";
	}
    }
}

sub create_btrace_files {
    my @tests = reverse sort keys %B;
    foreach my $test (@tests) {
	my $bt = $B{$test};
	foreach my $hk (sort keys %$bt) {
	    print "." if $verbose;
	    my $bv = $bt->{$hk};
	    my $btdir = $bv->{btdir};
	    -d $btdir || mkdir $btdir
		or die "Make directory '$btdir' failed: $!";
	    my $btfile = $bv->{btfile};
	    my $svgfile = $bv->{svgfile};
	    my $fgcmd = "$fgdir/stackcollapse-bpftrace.pl <$btfile | ".
		"$fgdir/flamegraph.pl >$svgfile.new";
	    system($fgcmd)
		and die "Command '$fgcmd' failed: $?";
	    rename("$svgfile.new", $svgfile)
		or die "Rename '$svgfile.new' to '$svgfile' failed: $!";
	    my @gzcmd = (qw(gzip -f -k -S .gz.new), $svgfile);
	    system(@gzcmd)
		and die "Gzip '@gzcmd' failed: $?";
	    rename("$svgfile.gz.new", "$svgfile.gz") or die
		"Rename '$svgfile.gz.new' to '$svgfile.gz' failed: $!";
	}
    }
}
