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
use File::Basename;
use File::Path qw(remove_tree);
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
my $performdir = getcwd();

# write summary of results into result file
open(my $tr, '>', "test.result")
    or die "Open 'test.result' for writing failed: $!";
$tr->autoflush();
$| = 1;

my $logdir = "$performdir/logs";
remove_tree($logdir);
mkdir $logdir
    or die "Make directory '$logdir' failed: $!";
chdir($logdir)
    or die "Chdir to '$logdir' failed: $!";

sub bad($$$;$) {
    my ($test, $reason, $message, $log) = @_;
    print $log "\n$reason\t$test\t$message\n" if $log;
    print "\n$reason\t$test\t$message\n\n" if $opts{v};
    print $tr "$reason\t$test\t$message\n";
    $log->sync() if $log;
    $tr->sync();
    no warnings 'exiting';
    next TEST;
}

sub good($$;$) {
    my ($test, $diff, $log) = @_;
    my $duration = sprintf("%dm%02d.%02ds", $diff/60, $diff%60, 100*$diff%100);
    print $log "\nPASS\t$test\tDuration $duration\n" if $log;
    print "\nPASS\t$test\tDuration $duration\n\n" if $opts{v};
    print $tr "PASS\t$test\tDuration $duration\n";
    $log->sync() if $log;
    $tr->sync();
}

my $remote_addr = $ENV{REMOTE_ADDR}
    or die "Environemnt REMOTE_ADDR not set";
my $remote_ssh = $ENV{REMOTE_SSH}
    or die "Environemnt REMOTE_SSH not set";

# iperf3 and tcpbench tests

my @sshcmd = ('ssh', $remote_ssh, 'pkill', 'iperf3');
system(@sshcmd);
@sshcmd = ('ssh', '-f', $remote_ssh, 'iperf3', '-s', '-D');
system(@sshcmd)
    and die "Start iperf3 server with '@sshcmd' failed: $?";

@sshcmd = ('ssh', $remote_ssh, 'pkill', 'tcpbench');
system(@sshcmd);
@sshcmd = ('ssh', '-f', $remote_ssh, 'tcpbench', '-s', '-r0', '-S1000000');
system(@sshcmd)
    and die "Start tcpbench server with '@sshcmd' failed: $?";

sleep 1;

sub iperf3_parser {
    my ($line, $log) = @_;
    if ($line =~ m{ ([\d.]+) +([kmgt]?)bits/sec(?: +(sender|receiver))?}i) {
	my $value = $1;
	my $unit = lc($2);
	if ($unit eq '') {
	} elsif ($unit eq 'k') {
	    $value *= 1000;
	} elsif ($unit eq 'm') {
	    $value *= 1000*1000;
	} elsif ($unit eq 'g') {
	    $value *= 1000*1000*1000;
	} elsif ($unit eq 't') {
	    $value *= 1000*1000*1000*1000;
	} else {
	    print $log "FAILED unknown unit $2\n" if $log;
	    print "FAILED unknown unit $2\n" if $opts{v};
	    return;
	}
	if ($3) {
	    print $tr "VALUE $value bits/sec $3\n";
	} else {
	    print $tr "SUBVALUE $value bits/sec\n";
	}
    }
    return 1;
}

my $subscale;
sub tcpbench_parser {
    my ($line, $log) = @_;
    if ($line =~ m{ ([kmgt]?)bps: +([\d.]+) }i) {
	my $value = $2;
	my $unit = lc($1);
	if ($unit eq '') {
	} elsif ($unit eq 'k') {
	    $value *= 1000;
	} elsif ($unit eq 'm') {
	    $value *= 1000*1000;
	} elsif ($unit eq 'g') {
	    $value *= 1000*1000*1000;
	} elsif ($unit eq 't') {
	    $value *= 1000*1000*1000*1000;
	} else {
	    print $log "FAILED unknown unit $1\n" if $log;
	    print "FAILED unknown unit $1\n" if $opts{v};
	    return;
	}
	print $tr "VALUE $value bits/sec\n";
    } elsif ($line =~ m{ \d+ +\d+ +([\d.]+) +[\d.]+%}i) {
	unless ($subscale) {
	    print $log "FAILED sub unit not set\n" if $log;
	    print "FAILED sub unit not set\n" if $opts{v};
	    return;
	}
	my $value = $1 * $subscale;
	print $tr "SUBVALUE $value bits/sec\n";
    } elsif ($line =~ m{ \w+ +\w+ +([kmgt]?)bps +[\w.]+}i) {
	my $unit = lc($1);
	if ($unit eq '') {
	    $subscale = 1;
	} elsif ($unit eq 'k') {
	    $subscale = 1000;
	} elsif ($unit eq 'm') {
	    $subscale = 1000*1000;
	} elsif ($unit eq 'g') {
	    $subscale = 1000*1000*1000;
	} elsif ($unit eq 't') {
	    $subscale = 1000*1000*1000*1000;
	} else {
	    print $log "FAILED unknown sub unit $1\n" if $log;
	    print "FAILED unknown sub unit $1\n" if $opts{v};
	    return;
	}
    }
    return 1;
}

my @tests = (
    {
	testcmd => ['iperf3', "-c$remote_addr", '-w1m'],
	parser => \&iperf3_parser,
    }, {
	testcmd => ['iperf3', "-c$remote_addr", '-w1m', '-R'],
	parser => \&iperf3_parser,
    }, {
	testcmd => ['tcpbench', '-S1000000', '-t10', $remote_addr],
	parser => \&tcpbench_parser,
    }, {
	testcmd => ['tcpbench', '-S1000000', '-t10', '-n100', $remote_addr],
	parser => \&tcpbench_parser,
    }
);

TEST:
foreach my $t (@tests) {
    my @runcmd = @{$t->{testcmd}};
    my $test = join("_", @runcmd);

    my $begin = Time::HiRes::time();
    my $date = strftime("%FT%TZ", gmtime($begin));
    print "\nSTART\t$test\t$date\n\n" if $opts{v};

    # write test output into log file
    my $logfile = "$test.log";
    open(my $log, '>', $logfile)
	or bad $test, 'NOLOG', "Open log '$logfile' for writing failed: $!";
    $log->autoflush();

    print $log "START\t$test\t$date\n\n";
    $log->sync();

    defined(my $pid = open(my $out, '-|'))
	or bad $test, 'NORUN', "Open pipe from '@runcmd' failed: $!", $log;
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
	local $SIG{ALRM} = sub { die "Test running too long, aborted\n" };
	alarm($timeout);
	while (<$out>) {
	    print $log $_;
	    $t->{parser}($_, $log)
		or bad $test, 'FAIL', "Could not parse value", $log;
	    s/[^\s[:print:]]/_/g;
	    print if $opts{v};
	}
	alarm(0);
    };
    kill 'KILL', -$pid;
    if ($@) {
	chomp($@);
	bad $test, 'NOTERM', $@, $log;
    }
    close($out)
	or bad $test, 'NOEXIT', $! ?
	"Close pipe from '@runcmd' failed: $!" :
	"Command '@runcmd' failed: $?", $log;

    my $end = Time::HiRes::time();
    good $test, $end - $begin, $log;

    close($log)
	or die "Close log '$logfile' after writing failed: $!";
}

chdir($performdir)
    or die "Chdir to '$performdir' failed: $!";

# kill remote commands or ssh will hang forever
@sshcmd = ('ssh', $remote_ssh, 'pkill', 'iperf3', 'tcpbench');
system(@sshcmd);

# create a tgz file with all log files
my @paxcmd = ('pax', '-x', 'cpio', '-wzf', "$performdir/test.log.tgz");
push @paxcmd, '-v' if $opts{v};
push @paxcmd, ("-s,^$logdir/,,", "-s,^$logdir,,", $logdir);
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
