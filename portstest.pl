#!/usr/bin/perl

# Copyright (c) 2016-2020 Alexander Bluhm <bluhm@genua.de>
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
use Fcntl qw(SEEK_SET);
use File::Basename;
use Getopt::Std;
use POSIX;
use Time::HiRes;

my %opts;
getopts('e:t:v', \%opts) or do {
    print STDERR "usage: $0 [-v] [-e environment] [-t timeout]\n";
    exit(2);
};
my $timeout = $opts{t} || 60*60;
environment($opts{e}) if $opts{e};

my $dir = dirname($0);
chdir($dir)
    or die "Change directory to '$dir' failed: $!";
my $portstestdir = getcwd();

# write summary of results into result file
open(my $tr, '>', "test.result")
    or die "Open 'test.result' for writing failed: $!";
$tr->autoflush();
$| = 1;

# get ports list from command line or input file
my @tests;
if (@ARGV) {
    @tests = @ARGV;
} else {
    open(my $tl, '<', "ports.list")
	or die "Open 'ports.list' for reading failed: $!";
    chomp(@tests = grep { ! /^#/ && ! /^\s*$/ } <$tl>);
    close($tl)
	or die "Close 'ports.list' after reading failed: $!";
}

sub bad {
    my ($prev, $test, $reason, $message, $log) = @_;
    my $nl = "";
    $nl = "\n" if $prev ne "";
    print $log "${nl}$reason\t$test\t$message\n" if $log;
    print "${nl}$reason\t$test\t$message\n\n" if $opts{v};
    print $tr "$reason\t$test\t$message\n";
    $log->sync() if $log;
    $tr->sync();
    no warnings 'exiting';
    next;
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

my @paxcmd = ('pax', '-wzf', "$dir/test.log.tgz", '-s,^/usr/ports/,,');
open(my $pax, '|-', @paxcmd)
    or die "Open pipe to '@paxcmd' failed: $!";
$pax->autoflush();
my $paxlog;

# run make test for each port
foreach my $test (@tests) {
    print $pax $paxlog if $paxlog;
    undef $paxlog;

    my $prev = "";
    my $begin = Time::HiRes::time();
    my $date = strftime("%FT%TZ", gmtime($begin));
    print "\nSTART\t$test\t$date\n\n" if $opts{v};

    $dir = "/usr/ports/$test";
    chdir($dir)
	or bad $prev, $test, 'NOEXIST', "Change directory to '$dir' failed: $!";

    # write make output into log file
    open(my $log, '>', "make.log")
	or bad $prev, $test, 'NOLOG', "Open 'make.log' for writing failed: $!";
    $log->autoflush();
    $paxlog = "$dir/make.log\n";

    my sub runcmd {
	my ($reason, @cmd) = @_;

	$log->truncate(0);
	$log->seek(0, SEEK_SET);
	print $log "START\t$test\t$date\n\n";
	$log->sync();

	defined(my $pid = open(my $out, '-|'))
	    or bad $prev, $test, 'NORUN', "Open pipe from '@cmd' failed: $!",
	    $log;
	if ($pid == 0) {
	    close($out);
	    open(STDIN, '<', "/dev/null")
		or warn "Redirect stdin to /dev/null failed: $!";
	    open(STDERR, '>&', \*STDOUT)
		or warn "Redirect stderr to stdout failed: $!";
	    setsid()
		or warn "Setsid $$ failed: $!";
	    exec(@cmd);
	    warn "Exec '@cmd' failed: $!";
	    _exit(126);
	}
	eval {
	    local $SIG{ALRM} = sub { die "Test running too long, aborted.\n" };
	    alarm($timeout);
	    while (<$out>) {
		print $log $_;
		s/[^\s[:print:]]/_/g;
		print if $opts{v};
		chomp($prev = $_);
	    }
	    alarm(0);
	};
	kill 'KILL', -$pid;
	if ($@) {
	    chomp($@);
	    bad $prev, $test, 'NOTERM', $@, $log;
	}
	close($out)
	    or bad $prev, $test, $reason, $! ?
	    "Close pipe from '@cmd' failed: $!" :
	    "Command '@cmd' failed: $?", $log;
    }
    runcmd('NOCLEAN', qw(make unlock clean));
    runcmd('SKIP', qw(make fetch));
    runcmd('NOEXIT', qw(make build));
    runcmd('FAIL', qw(make test));

    my $end = Time::HiRes::time();
    good $prev, $test, $end - $begin, $log;

    close($log)
	or die "Close 'make.log' after writing failed: $!";
}

print $pax $paxlog if $paxlog;
close($pax) or die $! ?
    "Close pipe to '@paxcmd' failed: $!" :
    "Command '@paxcmd' failed: $?";

close($tr)
    or die "Close 'test.result' after writing failed: $!";

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
