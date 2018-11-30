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

sub bad {
    my ($test, $reason, $message, $log) = @_;
    print $log "\n$reason\t$test\t$message\n" if $log;
    print "\n$reason\t$test\t$message\n\n" if $opts{v};
    print $tr "$reason\t$test\t$message\n";
    $log->sync() if $log;
    $tr->sync();
    no warnings 'exiting';
    next TEST;
}

sub good {
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

my $kconf = `sysctl -n kern.osversion | cut -d# -f1`;
my $machine = `machine`;
my $ncpu = `sysctl -n hw.ncpu`;
chomp($kconf, $machine, $ncpu);
my @cmd = ('make', "-C/usr/src/sys/arch/$machine/compile/$kconf");
push @cmd, '-s' unless $opts{v};
push @cmd, 'clean', 'config';
system(@cmd)
    and die "Clean kernel with '@cmd' failed: $?";
system('sync');

sleep 1;

sub iperf3_parser {
    my ($line, $log) = @_;
    if ($line =~ m{ ([\d.]+) +([kmgt]?)bits/sec(?:.* (sender|receiver))?}i) {
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

my @tcpbench_subvalues;
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
	push @tcpbench_subvalues, $value;
	print $tr "SUBVALUE $value bits/sec\n";
    }
    return 1;
}

sub tcpbench_finalize {
    my ($log) = @_;
    unless (@tcpbench_subvalues) {
	print $log "FAILED no sub values\n" if $log;
	print "FAILED no sub values\n" if $opts{v};
	return;
    }
    if (@tcpbench_subvalues >= 5) {
	# first and last value have higher variance, take middle values
	shift @tcpbench_subvalues;
	pop @tcpbench_subvalues;
    }
    my $value = 0;
    $value += $_ foreach @tcpbench_subvalues;
    $value /= @tcpbench_subvalues;
    undef @tcpbench_subvalues;
    # too much precision is useless and produces ugly output
    $value =~ s/\..*//;
    print $tr "VALUE $value bits/sec sender\n";
    return 1;
}

sub time_parser {
    my ($line, $log) = @_;
    if (/^(\w+) +(\d+\.\d+)$/) {
	print $tr "VALUE $2 sec $1\n";
    }
    if (/^ *(\d+)  ([\w ]+)$/) {
	print $tr "SUBVALUE $1 count $2\n";
    }
    return 1;
}

my $wallclock;
sub wallclock_initialize {
    $wallclock = Time::HiRes::time();
    return 1;
}

sub wallclock_finalize {
    printf $tr "VALUE %.2f sec wall\n", Time::HiRes::time() - $wallclock;
    return 1;
}

my @tests = (
    {
	testcmd => ['iperf3', "-c$remote_addr", '-w1m', '-t60'],
	parser => \&iperf3_parser,
    }, {
	testcmd => ['iperf3', "-c$remote_addr", '-w1m', '-t60', '-R'],
	parser => \&iperf3_parser,
    }, {
	testcmd => ['tcpbench', '-S1000000', '-t60', $remote_addr],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['tcpbench', '-S1000000', '-t60', '-n100', $remote_addr],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	initialize => \&wallclock_initialize,
	testcmd => ['time', '-lp', 'make',
	    "-C/usr/src/sys/arch/$machine/compile/$kconf", "-j$ncpu", '-s'],
	parser => \&time_parser,
	finalize => \&wallclock_finalize,
    }, {
	testcmd => ['iperf3', "-c$remote_addr", '-u', '-b0', '-w1m', '-t60'],
	parser => \&iperf3_parser,
    }, {
	testcmd => ['iperf3', "-c$remote_addr", '-u', '-b0', '-w1m', '-t60',
	    '-R'],
	parser => \&iperf3_parser,
    }
);

my @stats = (
    {
	statcmd => [ 'netstat', '-s' ],
    }, {
	statcmd => [ 'netstat', '-m' ],
    }, {
	statcmd => [ 'vmstat', '-mv' ],
    }, {
	statcmd => [ 'vmstat', '-s' ],
    }, {
	statcmd => [ 'vmstat', '-iz' ],
    },
);

TEST:
foreach my $t (@tests) {
    my @runcmd = @{$t->{testcmd}};
    (my $test = join("_", @runcmd)) =~ s,/.*/,,;

    my $begin = Time::HiRes::time();
    my $date = strftime("%FT%TZ", gmtime($begin));
    print "\nSTART\t$test\t$date\n\n" if $opts{v};

    # write test output into log file
    my $logfile = "$test.log";
    open(my $log, '>', $logfile)
	or bad $test, 'NOLOG', "Open log '$logfile' for writing failed: $!";
    $log->autoflush();

    # I have seen startup failures, this may help
    sleep 1;

    print $log "START\t$test\t$date\n\n";
    $log->sync();

    # XXX temporarily disabled
    #statistics($test, "before");

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
	$t->{initialize}($log)
	    or bad $test, 'FAIL', "Could not initialize test", $log
	    if $t->{initialize};
	while (<$out>) {
	    print $log $_;
	    $t->{parser}($_, $log)
		or bad $test, 'FAIL', "Could not parse value", $log
		if $t->{parser};
	    s/[^\s[:print:]]/_/g;
	    print if $opts{v};
	}
	$t->{finalize}($log)
	    or bad $test, 'FAIL', "Could not finalize test", $log
	    if $t->{finalize};
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

    # XXX temporarily disabled
    #statistics($test, "after");

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

sub statistics {
    my ($test, $when) = @_;
    foreach my $s (@stats) {
	my @statcmd = @{$s->{statcmd}};
	my $name = "$test.stats-$when-". join("_", @statcmd). ".log";
	open(my $fh, '>', $name)
	    or die "Open '$name' for writing failed: $!";
	defined(my $pid = fork())
	    or die "fork failed: $!";
	unless ($pid) {
	    # child process
	    open(STDOUT, ">&", $fh)
		or die "Redirect stdout to '$name' failed: $!";
	    open(STDERR, ">&", $fh)
		or die "Redirect stderr to '$name' failed: $!";
	    exec(@statcmd);
	    die "Exec failed: $!";
	}
	waitpid($pid, 0)
	    or die "Wait for pid '$pid' failed:$!";
	$? == 0
	    or die "Command '@statcmd' failed: $?";
    }
}
