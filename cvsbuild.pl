#!/usr/bin/perl
# recompile parts of machine for performance comparison

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
use Buildquirks;

my $now = strftime("%FT%TZ", gmtime);

my $scriptname = "$0 @ARGV";

my @allkernelmodes = qw(align gap sort reorder reboot);

my %opts;
getopts('d:D:h:m:P:r:v', \%opts) or do {
    print STDERR <<"EOF";
usage: cvsbuild.pl [-v] [-d date] [-D cvsdate] -h host [-m modify] [-P patch]
	[-r release] [kernel ...]
    -d date	set date string and change to sub directory
    -D cvsdate	update sources from cvs to this date
    -h host	root\@openbsd-test-machine, login per ssh
    -m modify	modify mode
    -P patch	apply patch to clean kernel source, comma separated list
    -r release	change to release sub directory
    -v		verbose
    kernel ...	kernel mode: @allkernelmodes
    align	relink kernel aligning all object at page size, no randomness
    gap		relink kernel sorting object files, but use random gap
    sort	relink kernel sorting object files at fixed position
    reorder	relink kernel using the reorder kernel script
    reboot	reboot, this is always done
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
my $release;
if ($opts{r} && $opts{r} ne "current") {
    ($release = $opts{r}) =~ /^\d+\.\d$/
	or die "Release '$opts{r}' must be major.minor format";
}

my %kernelmode;
foreach my $mode (@ARGV) {
    grep { $_ eq $mode } @allkernelmodes
	or die "Unknown kernel mode '$mode'";
    $kernelmode{$mode} = 1;
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
    my $dir = "$resultdir/$modify.[0-9]";
    $resultdir = (glob($dir))[-1]
	or die "Modify directory '$dir' not found";
}
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

my ($user, $host) = split('@', $opts{h}, 2);
($user, $host) = ("root", $user) unless $host;

createlog(file => "cvsbuild-$host.log", verbose => $opts{v});
logmsg("Script '$scriptname' started at $now.\n");

createhost($user, $host);

my %sysctl = get_version();
my ($before, $clean);
if ($sysctl{'kern.version'} =~
    /#cvs : D(\d{4}).(\d\d).(\d\d).(\d\d).(\d\d).(\d\d):/) {
    # date format is from CVS/Tag
    # OpenBSD 7.3-current (GENERIC.MP) #cvs : D2023.07.18.00.00.00: \
    #    Wed Jul 19 11:28:11 CEST 2023
    $before = "$1-$2-${3}T$4:$5:${6}Z";
} elsif ($sysctl{'kern.version'} =~
    /: (\w{3} \w{3}  ?\d?\d \d\d:\d\d:\d\d \w+ \d{4})\n/) {
    # date format is from snapshot
    # OpenBSD 7.3-current (GENERIC.MP) #1314: Tue Jul 25 17:02:17 MDT 2023
    $before = $1;
    $clean = "C";
}
if ($before && $cvsdate) {
    my %q = quirks($before, $cvsdate);
    if (keys %q) {
	open(my $fh, '>', "quirks-$host.txt")
	    or die "Open 'quirks-$host.txt' for writing failed: $!";
	print $fh map { "$q{$_}{date} $q{$_}{comment}\n" } sort keys %q;
    }
    foreach my $cmd (quirk_commands($before, $cvsdate, \%sysctl)) {
	if ($cmd eq "reboot") {
	    reboot();
	} else {
	    logcmd('ssh', "$user\@$host", $cmd);
	}
    }
}

$clean = "C" if $patch;
update_cvs(undef, $cvsdate, "sys", $clean) if $cvsdate;
if ($patch) {
    clean_cvs("sys") unless $cvsdate;
    patch_cvs($_, "sys") foreach split(/,/, $patch);
}
make_kernel();
if ($kernelmode{align}) {
    align_kernel();
} elsif ($kernelmode{gap}) {
    gap_kernel();
} elsif ($kernelmode{sort}) {
    sort_kernel();
}
reorder_kernel() if $kernelmode{align} || $kernelmode{gap} ||
    $kernelmode{sort} || $kernelmode{reorder};
get_bsdnm();
diff_cvs("sys") if $patch;
reboot();
get_version();

# finish build log

$now = strftime("%FT%TZ", gmtime);
logmsg("Script '$scriptname' finished at $now.\n");
