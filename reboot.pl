#!/usr/bin/perl
# reboot machine for repeated performance test

# Copyright (c) 2018-2020 Alexander Bluhm <bluhm@genua.de>
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

my %opts;
getopts('d:D:h:R:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] [-d date] [-D cvsdate] -h host [-R repeat] [kernel ...]
    -d date	set date string and change to sub directory
    -D cvsdate	update sources from cvs to this date
    -h host	root\@openbsd-test-machine, login per ssh
    -R repeat	repetition number
    -v		verbose
    align	relink kernel aligning all object at page size, no randomness
    gap		relink kernel sorting object files, but use random gap
    sort	relink kernel sorting object files at fixed position
    reorder	relink kernel using the reorder kernel script
    reboot	reboot, this is always done
EOF
    exit(2);
};
$opts{h} or die "No -h specified";
!$opts{d} || str2time($opts{d})
    or die "Invalid -d date '$opts{d}'";
my $date = $opts{d};
!$opts{D} || str2time($opts{D})
    or die "Invalid -D cvsdate '$opts{D}'";
my $cvsdate = $opts{D};
!$opts{R} || $opts{R} =~ /^\d{3}$/
    or die "Invalid -R repeat '$opts{R}'";
my $repeat = $opts{R};

my %allmodes;
@allmodes{qw(align gap sort reorder reboot)} = ();
my %kernelmode = map {
    die "Unknown kernel mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV;

my $performdir = dirname($0). "/..";
chdir($performdir)
    or die "Change directory to '$performdir' failed: $!";
$performdir = getcwd();
my $resultdir = "$performdir/results";
$resultdir .= "/$date" if $date;
$resultdir .= "/$cvsdate" if $date && $cvsdate;
$resultdir .= "/$repeat" if $date && $cvsdate && $repeat;
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

my ($user, $host) = split('@', $opts{h}, 2);
($user, $host) = ("root", $user) unless $host;

createlog(file => "reboot-$host.log", verbose => $opts{v});
$date = strftime("%FT%TZ", gmtime);
logmsg("Script '$scriptname' started at $date.\n");

createhost($user, $host);

# execute commands

if ($kernelmode{align}) {
    align_kernel();
} elsif ($kernelmode{gap}) {
    gap_kernel();
} elsif ($kernelmode{sort}) {
    sort_kernel();
}
reorder_kernel() if $kernelmode{align} || $kernelmode{gap} ||
    $kernelmode{sort} || $kernelmode{reorder};
reboot();
get_version();

# finish reboot log

$date = strftime("%FT%TZ", gmtime);
logmsg("Script '$scriptname' finished at $date.\n");
