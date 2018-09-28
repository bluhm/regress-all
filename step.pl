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
getopts('B:E:h:r:S:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] -h host [-r release] -B date -E date -S date mode ...
    -h host	user and host for performance test, user defaults to root
    -v		verbose
    -r release	use release for install and cvs checkout
    -B date	begin date
    -E date	end date
    -S date	step in sec, min, hour, day, week, month, year
EOF
    exit(2);
};
$opts{h} or die "No -h specified";
$opts{B} or die "No -B begin date";
$opts{E} or die "No -E end date";
$opts{S} or die "No -S step";
my $begin = str2time($opts{B}) or die "Invalid -B date '$opts{B}'";
my $end = str2time($opts{E}) or die "Invalid -E date '$opts{E}'";
my ($step, $unit) = $opts{S} =~ /^(\d+)(\w+)$/
    or die "Invalid -S step '$opts{S}'";

my %allmodes;
@allmodes{qw(cvs install keep)} = ();
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

# setup remote machines

usehosts(bindir => "$performdir/bin", date => $date,
    host => $opts{h}, verbose => $opts{v});

setup_hosts(mode => \%mode, release => $opts{r}) unless $mode{keep};
collect_version();
runcmd("$performdir/bin/setup-html.pl");

# update in single steps

for (my $current = $begin; $current <= $end;
    $current = add_step($current, $step, $unit)) {

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

    # run performance tests remotely

    (my $host = $opts{h}) =~ s/.*\@//;
    my @sshcmd = ('ssh', $opts{h}, 'perl', '/root/perform/perform.pl',
	'-e', "/root/regress/env-$host.sh", '-v');
    logcmd(@sshcmd);

    # get result and logs

    collect_result("$opts{h}:/root/perform");
    collect_dmesg();
}

# create html output

chdir($performdir)
    or die "Chdir to '$performdir' failed: $!";

runcmd("bin/setup-html.pl");

unlink("results/latest");
symlink($date, "results/latest")
    or die "Make symlink 'results/latest' failed: $!";

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
