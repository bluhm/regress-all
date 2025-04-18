#!/usr/bin/perl
# collect kernel output from console to regress or perform dir

# Copyright (c) 2018-2023 Alexander Bluhm <bluhm@genua.de>
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

use lib dirname($0);
use Logcmd;
use Machine;

my $now = strftime("%FT%TZ", gmtime);
my $scriptname = "$0 @ARGV";

my %opts;
getopts('d:D:h:lm:P:R:r:v', \%opts) or do {
    print STDERR <<"EOF";
usage: bsdcons.pl [-lv] [-d date] [-D cvsdate] -h host [-m modify] [-P patch]
	[-R repeatdir] [-r release]
    -d date	set date string and change to sub directory, may be current
    -D cvsdate	update sources from cvs to this date
    -h host	root\@openbsd-test-machine, login per ssh
    -l		update bsdcons in latest directory with this host
    -m modify	modify mode
    -P patch	patch name
    -R repdir	repetition number or btrace
    -r release	change to release sub directory
    -v		verbose
EOF
    exit(2);
};
$opts{h} or die "No -h specified";
!$opts{d} || $opts{d} eq "current" || str2time($opts{d})
    or die "Invalid -d date '$opts{d}'";
my $date = $opts{d};
!$opts{D} || str2time($opts{D})
    or die "Invalid -D cvsdate '$opts{D}'";
my $cvsdate = $opts{D};
my $patch = $opts{P};
my $modify = $opts{m};
!$opts{R} || $opts{R} =~ /^\d{3}$/
    or die "Invalid -R repeatdir '$opts{R}'";
my $repeatdir = $opts{R};
my $release;
if ($opts{r} && $opts{r} ne "current") {
    ($release = $opts{r}) =~ /^\d+\.\d$/
	or die "Release '$opts{r}' must be major.minor format";
}
$opts{d} && $opts{l}
    and die "Use either specific date or latest date";
@ARGV and die "No arguments allowed";

my $testdir = dirname($0). "/..";
chdir($testdir)
    or die "Change directory to '$testdir' failed: $!";
$testdir = getcwd();
my $resultdir = "$testdir/results";
if ($date && $date eq "current") {
    my $current = readlink("$resultdir/$date")
	or die "Read link '$resultdir/$date' failed: $!";
    -d "$resultdir/$current"
	or die "Test directory '$resultdir/$current' failed: $!";
    $date = $current;
}
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

my ($user, $host) = split('@', $opts{h}, 2);
($user, $host) = ("root", $user) unless $host;

createlog(verbose => $opts{v});
logmsg("$now Script '$scriptname' started.\n");

if ($opts{l}) {
    my @bsdcons = sort glob("*T*/bsdcons-$host.txt")
	or die "No latest 'bsdcons-$host.txt' in date directories";
    logmsg("Update latest '$bsdcons[-1]' file.\n");
    $date = dirname($bsdcons[-1]);
}

$resultdir .= "/$release" if $release;
$resultdir .= "/$date" if $date;
$resultdir .= "/$cvsdate" if $date && $cvsdate;
if ($patch) {
    my $patchdir = "patch-".
	join(',', map { s,\.[^/]*,,; basename($_) } split(/,/, $patch));
    my $dir = "$resultdir/$patchdir.[0-9]";
    $resultdir = (glob($dir))[-1]
	or die "Patch directory '$dir' not found";
}
if ($modify) {
    my $dir = "$resultdir/modify-$modify.[0-9]";
    $resultdir = (glob($dir))[-1]
	or die "Modify directory '$dir' not found";
}
$resultdir .= "/$repeatdir" if $repeatdir;
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";
logmsg("Result directory is '$resultdir'.\n");

createhost($user, $host);

# execute commands

get_bsdcons();

$now = strftime("%FT%TZ", gmtime);
logmsg("$now Script '$scriptname' finished.\n");
