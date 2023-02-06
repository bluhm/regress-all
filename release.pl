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
use File::Path qw(remove_tree);
use Getopt::Std;
use POSIX;
use Time::HiRes;

my %opts;
getopts('e:t:v', \%opts) or do {
    print STDERR <<"EOF";
usage: release.pl [-v] [-e environment] [-t timeout] [steps ...]
    -e environ	parse environment for tests from shell script
    -t timeout	timeout for a single test, default 1 hour
    -v		verbose
    steps ...	clean obj build sysmerge dev destdir reldir release chkflist
EOF
    exit(2);
};
my $timeout = $opts{t} || 5*24*60*60;
environment($opts{e}) if $opts{e};
@ARGV and warn "Make release restricted to build steps, for debugging only\n";

my $dir = dirname($0);
chdir($dir)
    or die "Change directory to '$dir' failed: $!";
$dir = getcwd();
my $logdir = "$dir/logs";
-d $logdir && remove_tree($logdir);
mkdir $logdir
    or die "Make directory '$logdir' failed: $!";

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
    no warnings 'exiting';
    last;
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

sub logmsg {
    my ($prev, $message, $log) = @_;
    print $log "$message\n" if $log;
    print "$message\n" if $opts{v};
    $$prev = $message;
}

my $ncpu = `sysctl -n hw.ncpu`;
chomp($ncpu);

my @tests = (
    [ clean	=> "rm -rf /usr/obj/*"					],
    [ obj	=> "cd /usr/src && make obj"				],
    [ build	=> "cd /usr/src && make -j$ncpu build"			],
    [ sysmerge	=> "sysmerge -b"					],
    [ dev	=> "cd /dev && ./MAKEDEV all"				],
    [ destdir	=> \&destdir						],
    [ reldir	=> \&releasedir						],
    [ release	=> "cd /usr/src/etc && time make -j$ncpu release"	],
    [ chkflist	=> "cd /usr/src/distrib/sets && sh checkflist"		],
);

# run release steps as tests
foreach (@tests) {
    my ($test, $cmd) = @$_;

    if (@ARGV) {
	next unless grep { $_ eq $test } @ARGV;
    }
    my $prev = "";
    my $begin = Time::HiRes::time();
    my $date = strftime("%FT%TZ", gmtime($begin));
    print "\nSTART\t$test\t$date\n\n" if $opts{v};

    mkdir "$logdir/$test";
    my $logfile = "$logdir/$test/make.log";
    open(my $log, '>', $logfile)
	or bad $prev, $test, 'NOLOG', "Open '$logfile' for writing failed: $!";
    $log->autoflush();

    print $log "START\t$test\t$date\n\n";
    $log->sync();

    if (ref $cmd eq 'CODE') {
	logmsg \$prev, "Function '$test' started.", $log;
	eval { $cmd->() };
	if ($@) {
	    chomp($@);
	    bad $prev, $test, 'FAIL', $@, $log;
	}
	logmsg \$prev, "Function '$test' finished.", $log;
    } else {
	logmsg \$prev, "Command '$cmd' started.", $log;
	my $pid = open(my $out, '-|', $cmd)
	    or bad $prev, $test, 'NORUN', "Open pipe from '$cmd' failed: $!",
	    $log;
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
	    or bad $prev, $test, 'NOEXIT', $! ?
	    "Close pipe from '$cmd' failed: $!" :
	    "Command '$cmd' failed: $?", $log;
	logmsg \$prev, "Command '$cmd' finished.", $log;
    }

    my $end = Time::HiRes::time();
    good $prev, $test, $end - $begin, $log;

    close($log)
	or die "Close '$logfile' after writing failed: $!";
}

my @paxcmd = ('pax', '-wzf', "$dir/test.log.tgz", '-s,^logs/,,',
    '-s,^logs,,', 'logs');
system(@paxcmd)
    and die "Command '@paxcmd' failed: $?";

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

sub destdir {
    my ($login, $pass, $uid, $gid) = getpwnam("build")
	or die "User 'build' not in passwd file";

    -d "/build" || mkdir "/build"
	or die "Make directory '/build' failed: $!";
    system("umount -f /build");
    system("mount /build")
	and die "Mount '/build' failed: $?";
    chown $uid, 0, "/build"
	or die "Chown '/build' to build failed: $!";
    chmod 0700, "/build"
	or die "Chmod '/build' to 700 failed: $!";
    -d "/build/dest" || mkdir "/build/dest"
	or die "Make directory '/build/dest' failed: $!";

    $ENV{DESTDIR}="/build/dest";
}

sub releasedir {
    my ($login, $pass, $uid, $gid) = getpwnam("build")
	or die "User 'build' not in passwd file";

    -d "/usr/release" || mkdir "/usr/release"
	or die "Make directory '/usr/release' failed: $!";
    chown 0, $gid, "/usr/release"
	or die "Chown '/usr/release' to build failed: $!";
    chmod 0775, "/usr/release"
	or die "Chmod '/usr/release' to 775 failed: $!";

    $ENV{RELEASEDIR}="/usr/release";
}
