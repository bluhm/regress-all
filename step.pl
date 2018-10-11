#!/usr/bin/perl

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
use File::Basename;
use Getopt::Std;
use POSIX;
use Time::Local;

use lib dirname($0);
use Logcmd;
use Hostctl;

my $scriptname = "$0 @ARGV";

my %opts;
getopts('B:E:h:N:R:r:S:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] -h host [-r release] -B date -E date -S date mode ...
    -h host	user and host for performance test, user defaults to root
    -v		verbose
    -r release	use release for install and cvs checkout
    -B date	begin date
    -E date	end date
    -S duration	step in sec, min, hour, day, week, month, year
    -N repeat	number of build, reboot, test repetitions per step
    -R repmode	repetition mode for kernel: relink, reboot, keep
    mode ...	mode for machine setup: install, cvs, build, keep
EOF
    exit(2);
};
$opts{h} or die "No -h specified";
$opts{B} or die "No -B begin date";
my ($begin, $end, $step, $unit, $repeat);
$begin = str2time($opts{B})
    or die "Invalid -B date '$opts{B}'";
$end = str2time($opts{E} || $opts{B})
    or die "Invalid -E date '$opts{E}'";
if ($opts{S}) {
    ($step, $unit) = $opts{S} =~ /^(\d+)(\w+)$/
	or die "Invalid -S step '$opts{S}'";
    # unit syntax check
    add_step(0 , $step, $unit);
} else {
    $step = $end - $begin;
    $unit = "sec";
}
$end >= $begin
    or die "Begin date '$opts{B}' before end date '$opts{E}'";
$end == $begin || $step > 0
    or die "Step '$opts{S}' cannot reach end date";

$repeat = $opts{N} || 1;
$repeat >= 1
    or die "Repeat '$opts{N}' must be positive integer";
$opts{N} && $opts{R} or !$opts{N} && !$opts{R}
    or die "Repeat number and repeat mode must be used together";
my %allrepmodes;
@allrepmodes{qw(relink reboot keep)} = ();
!$opts{R} || exists $allrepmodes{$opts{R}}
    or die "Unknown repetition mode '$opts{R}'";
my %repmode = ($opts{R} => 1);

my %allmodes;
@allmodes{qw(build cvs install keep)} = ();
@ARGV or die "No mode specified";
my %mode = map {
    die "Unknown mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV;
foreach (qw(install keep)) {
    die "Mode must be used solely: $_" if $mode{$_} && keys %mode != 1;
}

# create directory for this test run with timestamp 2016-07-13T12:30:42Z
my $date = strftime("%FT%TZ", gmtime);

my $performdir = dirname($0). "/..";
chdir($performdir)
    or die "Chdir to '$performdir' failed: $!";
$performdir = getcwd();
my $resultdir = "results";
-d $resultdir || mkdir $resultdir
    or die "Make result directory '$resultdir' failed: $!";
$resultdir .= "/$date";
mkdir $resultdir
    or die "Make directory '$resultdir' failed: $!";
unlink("results/current");
symlink($date, "results/current")
    or die "Make symlink 'results/current' failed: $!";
chdir($resultdir)
    or die "Chdir to '$resultdir' failed: $!";

createlog(file => "step.log", verbose => $opts{v});
logmsg("script '$scriptname' started at $date\n");

open(my $fh, '>', "stepconf.txt")
    or die "Open 'stepconf.txt' for writing failed :$!";
print $fh "RELEASE $opts{r}\n";
print $fh strftime("BEGIN %FT%TZ\n", gmtime($begin));
print $fh strftime("END %FT%TZ\n", gmtime($end));
print $fh "STEP $step $unit\n";
print $fh "REPEAT $repeat\n";
print $fh "REPMODES ", join(" ", sort keys %repmode), "\n";
print $fh "MODES ", join(" ", sort keys %mode), "\n";
close($fh);

# setup remote machines

usehosts(bindir => "$performdir/bin", date => $date,
    host => $opts{h}, verbose => $opts{v});
(my $host = $opts{h}) =~ s/.*\@//;

setup_hosts(mode => \%mode, release => $opts{r}) unless $mode{keep};
collect_version();
runcmd("$performdir/bin/setup-html.pl");

# update in single steps

for (my $current = $begin; $current <= $end;) {

    chdir($performdir)
	or die "Chdir to '$performdir' failed: $!";

    my $cvsdate = strftime("%FT%TZ", gmtime($current));
    my $cvsdir = "results/$date/$cvsdate";
    mkdir $cvsdir
	or die "Make directory '$cvsdir' failed: $!";
    chdir($cvsdir)
	or die "Chdir to '$cvsdir' failed: $!";
    cvsbuild_hosts(cvsdate => $cvsdate);
    collect_version();
    runcmd("$performdir/bin/setup-html.pl");

    # run repetitions if requested

    for (my $n = 0; $n < $repeat; $n++) {
	my $repeatdir = sprintf("%03d", $n);
	if ($repeat > 1) {
	    mkdir $repeatdir
		or die "Make directory '$repeatdir' failed: $!";
	    chdir($repeatdir)
		or die "Chdir to '$repeatdir' failed: $!";
	}

	# run performance tests remotely

	my @sshcmd = ('ssh', $opts{h}, 'perl', '/root/perform/perform.pl',
	    '-e', "/root/perform/env-$host.sh", '-v');
	logcmd(@sshcmd);

	# get result and logs

	collect_result("$opts{h}:/root/perform");

	if ($repeat > 1) {
	    reorder_kernel(mode => \%repmode) unless $repmode{keep};
	    chdir("..")
		or die "Chdir to '..' failed: $!";
	}
    }
    collect_dmesg();

    # if next step does not hit the end exactly, do an additional test

    last if $current == $end;
    $current = add_step($current, $step, $unit);
    $current = $end if $current > $end;
}

# create html output

chdir($performdir)
    or die "Chdir to '$performdir' failed: $!";

runcmd("bin/setup-html.pl");
runcmd("bin/perform-html.pl", "-h", $host);
runcmd("bin/perform-html.pl");

unlink("results/latest-$host");
symlink($date, "results/latest-$host")
    or die "Make symlink 'results/latest-$host' failed: $!";
unlink("results/latest");
symlink($date, "results/latest")
    or die "Make symlink 'results/latest' failed: $!";
runcmd("bin/perform-html.pl", "-l", "-h", $host);
runcmd("bin/perform-html.pl", "-l");

$date = strftime("%FT%TZ", gmtime);
logmsg("script '$scriptname' finished at $date\n");

exit;

sub add_step {
    my ($before, $step, $unit) = @_;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($before);

    if ($unit eq "sec") {
    } elsif ($unit eq "min") {
	$step *= 60;
    } elsif ($unit eq "hour") {
	$step *= 60 * 60;
    } elsif ($unit eq "day") {
	$step *= 60 * 60 * 24;
    } elsif ($unit eq "week") {
	$step *= 60 * 60 * 24 * 7;
    } elsif ($unit eq "month") {
	$mon += $step;
	$year += int(($mon - 1) / 12);
	$mon = (($mon - 1) % 12) + 1;
	$step = 0;
    } elsif ($unit eq "$year") {
	$year += $step;
	$step = 0;
    } else {
	die "Invalid step unit '$unit'";
    }

    my $after = timegm($sec, $min, $hour, $mday, $mon, $year) + $step;
    return $after;
}
