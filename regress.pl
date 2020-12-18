#!/usr/bin/perl

# Copyright (c) 2016-2017 Alexander Bluhm <bluhm@genua.de>
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
my $timeout = $opts{t} || 60*60;
environment($opts{e}) if $opts{e};

my $dir = dirname($0);
chdir($dir)
    or die "Chdir to '$dir' failed: $!";
my $regressdir = getcwd();

# write summary of results into result file
open(my $tr, '>', "test.result")
    or die "Open 'test.result' for writing failed: $!";
$tr->autoflush();
$| = 1;

# get test list from command line or input file
my @tests;
if (@ARGV) {
    @tests = @ARGV;
} else {
    open(my $tl, '<', "test.list")
	or die "Open 'test.list' for reading failed: $!";
    chomp(@tests = grep { ! /^#/ && ! /^\s*$/ } <$tl>);
    close($tl)
	or die "Close 'test.list' after reading failed: $!";
}

# run sudo is if is set to get password in advance
my @sudocmd = qw(make -s -f - sudo);
open(my $sudo, '|-', @sudocmd)
    or die "Open pipe to '@sudocmd' failed: $!";
print $sudo "sudo:\n\t\${SUDO} true\n";
close($sudo) or die $! ?
    "Close pipe to '@sudocmd' failed: $!" :
    "Command '@sudocmd' failed: $?";

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

my @paxcmd = ('pax', '-wzf', "$dir/test.log.tgz", '-s,^/usr/src/regress/,,');
open(my $pax, '|-', @paxcmd)
    or die "Open pipe to '@paxcmd' failed: $!";
$pax->autoflush();
my $paxlog;

# run make regress for each test
foreach my $test (@tests) {
    print $pax $paxlog if $paxlog;
    undef $paxlog;

    my $prev = "";
    my $begin = Time::HiRes::time();
    my $date = strftime("%FT%TZ", gmtime($begin));
    print "\nSTART\t$test\t$date\n\n" if $opts{v};

    $dir = $test =~ m,^/, ? $test : "/usr/src/regress/$test";
    chdir($dir)
	or bad $prev, $test, 'NOEXIST', "Chdir to '$dir' failed: $!";

    my $cleancmd = "make clean";
    $cleancmd .= " >/dev/null" unless $opts{v};
    $cleancmd .= " 2>&1";
    system($cleancmd)
	and bad $prev, $test, 'NOCLEAN', "Command '$cleancmd' failed: $?";
    print "\n" if $opts{v};

    # write make output into log file
    open(my $log, '>', "make.log")
	or bad $prev, $test, 'NOLOG', "Open 'make.log' for writing failed: $!";
    $log->autoflush();
    $paxlog = "$dir/make.log\n";

    print $log "START\t$test\t$date\n\n";
    $log->sync();

    my $skipped = 0;
    my (@xfailed, @xpassed, @failed);
    my @runcmd = qw(make regress);
    defined(my $pid = open(my $out, '-|'))
	or bad $prev, $test, 'NORUN', "Open pipe from '@runcmd' failed: $!",
	$log;
    if ($pid == 0) {
	close($out);
	open(STDIN, '<', "/dev/null")
	    or warn "Redirect stdin to /dev/null failed: $!";
	open(STDERR, '>&', \*STDOUT)
	    or warn "Redirect stderr to stdout failed: $!";
	setsid()
	    or warn "Setsid $$ failed: $!";
	exec(@runcmd);
	warn "Exec '@runcmd' failed: $!";
	_exit(126);
    }
    eval {
	local $SIG{ALRM} = sub { die "Test running too long, aborted.\n" };
	alarm($timeout);
	while (<$out>) {
	    print $log $_;
	    s/[^\s[:print:]]/_/g;
	    print if $opts{v};
	    push @failed, $prev, if /^FAILED$/;
	    push @xpassed, $prev, if /^UNEXPECTED_PASS(ED)?$/;
	    $skipped++ if /^SKIPPED$/;
	    push @xfailed, $prev, if /^EXPECTED_FAIL(ED)?$/;
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
	or bad $prev, $test, 'NOEXIT', $! ?
	"Close pipe from '@runcmd' failed: $!" :
	"Command '@runcmd' failed: $?", $log;

    bad $prev, $test, 'FAIL', join(", ", @failed), $log if @failed;
    bad $prev, $test, 'XPASS', join(", ", @xpassed), $log if @xpassed;
    bad $prev, $test, 'SKIP', "Test skipped itself", $log if $skipped;
    bad $prev, $test, 'XFAIL', join(", ", @xfailed), $log if @xfailed;
    my $end = Time::HiRes::time();
    good $prev, $test, $end - $begin, $log;

    close($log)
	or die "Close 'make.log' after writing failed: $!";
}

print $pax $paxlog if $paxlog;
close($pax) or die $! ?
    "Close pipe to '@paxcmd' failed: $!" :
    "Command '@paxcmd' failed: $?";

# create a tgz file with all obj/regress files
my $objdir = "/usr/obj/regress";
@paxcmd = ('pax', '-x', 'cpio', '-wzf', "$regressdir/test.obj.tgz");
push @paxcmd, '-v' if $opts{v};
push @paxcmd, ("-s,^$objdir/,,", "-s,^$objdir,,", $objdir);
system(@paxcmd)
    and die "Command '@paxcmd' failed: $?";

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
