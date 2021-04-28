#!/usr/bin/perl

# Copyright (c) 2016-2021 Alexander Bluhm <bluhm@genua.de>
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
use Getopt::Std;
use POSIX;
use Time::HiRes;

my %opts;
getopts('e:t:v', \%opts) or do {
    print STDERR "usage: $0 [-v] [-e environment] [-t timeout]\n";
    exit(2);
};
my $timeout = $opts{t} || 24*60*60;
environment($opts{e}) if $opts{e};

my $dir = dirname($0);
chdir($dir)
    or die "Change directory to '$dir' failed: $!";

# write summary of results into result file
open(my $tr, '>', "test.result")
    or die "Open 'test.result' for writing failed: $!";
$tr->autoflush();
$| = 1;

sub bad {
    my ($prev, $test, $reason, $message, $log) = @_;
    my $nl = "";
    $nl = "\n" if $prev ne "";
    print $log "${nl}$reason\t$test\t$message\n" if $log;
    print "${nl}$reason\t$test\t$message\n\n" if $opts{v};
    print $tr "$reason\t$test\t$message\n";
    $log->sync() if $log;
    $tr->sync();
    exit(1);
}

sub good {
    my ($prev, $test, $diff, $log) = @_;
    my $nl = "";
    $nl = "\n" if $prev ne "";
    my $duration = sprintf("%dm%02d.%02ds", $diff/60, $diff%60, 100*$diff%100);
    print $log "${nl}PASS\t$test\tDuration $duration\n" if $log;
    print "${nl}PASS\t$test\tDuration $duration\n\n" if $opts{v};
    print $tr "PASS\t$test\tDuration $duration\n";
    $log->sync() if $log;
    $tr->sync();
}

my $prev = "";
my $test = "release";
my $begin = Time::HiRes::time();
my $date = strftime("%FT%TZ", gmtime($begin));
print "\nSTART\t$test\t$date\n\n" if $opts{v};

$dir = "/usr/src";
chdir($dir)
    or bad $prev, $test, 'NOEXIST', "Change directory to '$dir' failed: $!";

# write make output into log file
open(my $log, '>', "make.log")
    or bad $prev, $test, 'NOLOG', "Open 'make.log' for writing failed: $!";
$log->autoflush();

my ($login,$pass,$uid,$gid) = getpwnam("build")
    or bad $prev, $test, 'NORUN', "User 'build' not in passwd file";

-d "/build" || mkdir "/build"
    or bad $prev, $test, 'NORUN', "Make directory '/build' failed: $!";
system("umount -f /build");
system("mount /build")
    and bad $prev, $test, 'NORUN', "Mount '/build' failed: $?";
chown $uid, 0, "/build"
    or bad $prev, $test, 'NORUN', "Chown '/build' to build failed: $!";
chmod 0700, "/build"
    or bad $prev, $test, 'NORUN', "Chmod '/build' to 700 failed: $!";
-d "/build/dest" || mkdir "/build/dest"
    or bad $prev, $test, 'NORUN', "Make directory '/build/dest' failed: $!";

-d "/usr/release" || mkdir "/usr/release"
    or bad $prev, $test, 'NORUN', "Make directory '/usr/release' failed: $!";
chown 0, $gid, "/usr/release"
    or bad $prev, $test, 'NORUN', "Chown '/usr/release' to build failed: $!";
chmod 0775, "/usr/release"
    or bad $prev, $test, 'NORUN', "Chmod '/usr/release' to 775 failed: $!";

system("cd /usr/src/etc && time make release")
    and bad $prev, $test, 'NOEXIT', "Make release failed: $?";
system("cd /usr/src/distrib/sets && sh checkflist")
    or bad $prev, $test, 'NOEXIT', "Run checkflist failed: $?";

my $end = Time::HiRes::time();
good $prev, $test, $end - $begin, $log;

close($log)
    or die "Close 'make.log' after writing failed: $!";

close($tr)
    or die "Close 'test.result' after writing failed: $!";

exit;

# parse shell script that is setting environment for some tests
# FOO=bar
# FOO="bar"
# export FOO=bar
# export FOO BAR
sub environment {
    my $file = shift;

    open(my $fh, '<', $file)
	or die "Open '$file' for reading failed: $!";
    while (<$fh>) {
	chomp;
	s/#.*$//;
	s/\s+$//;
	s/^export\s+(?=\w+=)//;
	s/^export\s+\w+.*//;
	next if /^$/;
	if (/^(\w+)=(\S+)$/ or /^(\w+)="([^"]*)"/ or /^(\w+)='([^']*)'/) {
	    $ENV{$1}=$2;
	} else {
	    die "Unknown environment line in '$file': $_";
	}
    }
}
