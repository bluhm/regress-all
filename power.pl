#!/usr/bin/perl
# power up and down machine to save cooling power

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

my $scriptname = "$0 @ARGV";

my @allpowermodes = qw(down up);

my %opts;
getopts('d:D:h:m:P:R:r:v', \%opts) or do {
    print STDERR <<"EOF";
usage: power.pl [-v] [-d date] [-D cvsdate] -h host [-m modify] [-P patch]
	[-R repeatdir] [-r release] power
    -d date	set date string and change to sub directory, may be current
    -D cvsdate	update sources from cvs to this date
    -h host	root\@openbsd-test-machine, login per ssh
    -m modify	modify mode
    -P patch	patch name
    -R repdir	repetition number or btrace
    -r release	change to release sub directory
    -v		verbose
    power	power mode: @allpowermodes
    down	shutdown and power off machine
    up		machine is up or power cycle
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

@ARGV or die "No mode specified";
my %mode;
foreach my $mode (@ARGV) {
    grep { $_ eq $mode } @allpowermodes
	or die "Unknown power mode '$mode'";
    $mode{$mode} = 1;
}
foreach my $mode (@allpowermodes) {
    die "Power mode '$mode' must be used solely"
	if $mode{$mode} && keys %mode != 1;
}

my $performdir = dirname($0). "/..";
chdir($performdir)
    or die "Change directory to '$performdir' failed: $!";
$performdir = getcwd();
my $resultdir = "$performdir/results";
$resultdir .= "/$release" if $release;
if ($date && $date eq "current") {
    my $current = readlink("$resultdir/$date")
	or die "Read link '$resultdir/$date' failed: $!";
    -d "$resultdir/$current"
	or die "Test directory '$resultdir/$current' failed: $!";
    $date = $current;
}
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

my ($user, $host) = split('@', $opts{h}, 2);
($user, $host) = ("root", $user) unless $host;

createlog(file => "power-$host.log", verbose => $opts{v});
$date = strftime("%FT%TZ", gmtime);
logmsg("Script '$scriptname' started at $date.\n");

createhost($user, $host);

# execute commands

power_down() if $mode{down};
power_up() if $mode{up};

# finish power log

my $now = strftime("%FT%TZ", gmtime);
logmsg("Script '$scriptname' finished at $now.\n");

exit;
