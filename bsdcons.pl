#!/usr/bin/perl
# collect kernel output from console to regress or perform dir

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
getopts('d:D:h:lR:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-lv] [-d date] [-D cvsdate] -h host [-R repeat]
    -d date	set date string and change to sub directory
    -D cvsdate	update sources from cvs to this date
    -h host	root\@openbsd-test-machine, login per ssh
    -l		update bsdcons in latest directory with this host
    -R repeat	repetition number
    -v		verbose
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
$opts{d} && $opts{l}
    and die "Use either specific date or latest date";

my $testdir = dirname($0). "/..";
chdir($testdir)
    or die "Chdir to '$testdir' failed: $!";
$testdir = getcwd();
my $resultdir = "$testdir/results";
chdir($resultdir)
    or die "Chdir to '$resultdir' failed: $!";

my ($user, $host) = split('@', $opts{h}, 2);
($user, $host) = ("root", $user) unless $host;

createlog(verbose => $opts{v});
my $now = strftime("%FT%TZ", gmtime);
logmsg("Script '$scriptname' started at $now.\n");

if ($opts{l}) {
    my @bsdcons = sort glob("*T*/bsdcons-$host.txt")
	or die "No latest 'bsdcons-$host.txt' in date directories";
    logmsg("Update latest '$bsdcons[-1]' file.\n");
    $date = dirname($bsdcons[-1]);
}

$resultdir .= "/$date" if $date;
$resultdir .= "/$cvsdate" if $date && $cvsdate;
$resultdir .= "/$repeat" if $date && $cvsdate && $repeat;
chdir($resultdir)
    or die "Chdir to '$resultdir' failed: $!";

createhost($user, $host);

# execute commands

get_bsdcons();

$now = strftime("%FT%TZ", gmtime);
logmsg("Script '$scriptname' finished at $now.\n");
