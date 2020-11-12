#!/usr/bin/perl

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
use File::Basename;
use File::Path qw(remove_tree);
use Getopt::Std;
use POSIX;
use Time::HiRes;

my %opts;
getopts('e:t:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] [-e environment] [-t timeout] [test ...]
    -t timeout	timeout for a single test, default 1 hour
    -e environ	parse environment for tests from shell script
    -v		verbose
    test ...	test mode: all, net, tcp, udp, make, fs, iperf, tcpbench,
		udpbench, iperftcp, iperfudp, net4, tcp4, udp4, iperf4,
		tcpbench4, udpbench4, iperftcp4, iperfudp4, net6, tcp6,
		udp6, iperf6, tcpbench6, udpbench6, iperftcp6, iperfudp6,
		linuxnet, linuxiperftcp4, linuxiperftcp6,
		forward, forward4, forward6 relay, relay4, relay6
EOF
    exit(2);
};
my $timeout = $opts{t} || 60*60;
environment($opts{e}) if $opts{e};

my %allmodes;
@allmodes{qw(all net tcp udp make fs iperf tcpbench udpbench iperftcp
    iperfudp net4 tcp4 udp4 iperf4 tcpbench4 udpbench4 iperftcp4 iperfudp4
    net6 tcp6 udp6 iperf6 tcpbench6 udpbench6 iperftcp6 iperfudp6
    linuxnet linuxiperftcp4 linuxiperftcp6
    forward forward4 forward6 relay relay4 relay6
)} = ();
my %testmode = map {
    die "Unknown test mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV;
$testmode{all} = 1 unless @ARGV;
@testmode{qw(net make fs)} = 1..3 if $testmode{all};
@testmode{qw(net4 net6 forward relay)} = 1..4 if $testmode{net};
@testmode{qw(tcp4 udp4 forward4 relay4)} = 1..4 if $testmode{net4};
@testmode{qw(tcp6 udp6 forward6 relay6)} = 1..4 if $testmode{net6};
@testmode{qw(linuxiperftcp4 linuxiperftcp6)} = 1..2 if $testmode{linuxnet};
@testmode{qw(iperf4 iperf6)} = 1..2 if $testmode{iperf};
@testmode{qw(iperftcp4 iperfudp4 linuxiperftcp4)} = 1..3 if $testmode{iperf4};
@testmode{qw(iperftcp6 iperfudp6 linuxiperftcp6)} = 1..3 if $testmode{iperf6};
@testmode{qw(tcp4 tcp6)} = 1..2 if $testmode{tcp};
@testmode{qw(iperftcp4 tcpbench4 linuxiperftcp4)} = 1..3 if $testmode{tcp4};
@testmode{qw(iperftcp6 tcpbench6 linuxiperftcp6)} = 1..3 if $testmode{tcp6};
@testmode{qw(udp4 udp6)} = 1..2 if $testmode{udp};
@testmode{qw(iperfudp4 udpbench4)} = 1..2 if $testmode{udp4};
@testmode{qw(iperfudp6 udpbench6)} = 1..2 if $testmode{udp6};
@testmode{qw(tcpbench4 tcpbench6)} = 1..2 if $testmode{tcpbench};
@testmode{qw(udpbench4 udpbench6)} = 1..2 if $testmode{udpbench};
@testmode{qw(iperftcp4 iperftcp6)} = 1..2 if $testmode{iperftcp};
@testmode{qw(iperfudp4 iperfudp6)} = 1..2 if $testmode{iperfudp};
@testmode{qw(forward4 forward6)} = 1..2 if $testmode{forward};
@testmode{qw(relay4 relay6)} = 1..2 if $testmode{relay};

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

my $local_if = $ENV{LOCAL_IF};
my $remote_if = $ENV{REMOTE_IF};
my $remote_ssh = $ENV{REMOTE_SSH}
    or die "Environemnt REMOTE_SSH not set";
my $local_addr = $ENV{LOCAL_ADDR}
    or die "Environemnt LOCAL_ADDR not set";
my $remote_addr = $ENV{REMOTE_ADDR}
    or die "Environemnt REMOTE_ADDR not set";
my $local_addr6 = $ENV{LOCAL_ADDR6}
    or die "Environemnt LOCAL_ADDR6 not set";
my $remote_addr6 = $ENV{REMOTE_ADDR6}
    or die "Environemnt REMOTE_ADDR6 not set";

my $linux_addr = $ENV{LINUX_ADDR};
my $linux_addr6 = $ENV{LINUX_ADDR6};
my $linux_forward_addr = $ENV{LINUX_FORWARD_ADDR};
my $linux_forward_addr6 = $ENV{LINUX_FORWARD_ADDR6};
my $linux_relay_addr = $ENV{LINUX_RELAY_ADDR};
my $linux_relay_addr6 = $ENV{LINUX_RELAY_ADDR6};
my $linux_ssh = $ENV{LINUX_SSH};

my $linux_relay_local_addr = $ENV{LINUX_RELAY_LOCAL_ADDR};
my $linux_relay_local_addr6 = $ENV{LINUX_RELAY_LOCAL_ADDR6};
my $linux_relay_remote_addr = $ENV{LINUX_RELAY_REMOTE_ADDR};
my $linux_relay_remote_addr6 = $ENV{LINUX_RELAY_REMOTE_ADDR6};
my $linux_other_ssh = $ENV{LINUX_OTHER_SSH};

# tcpdump as workaround for missing workaround in ix(4) for 82598
# tcpdump during reboot may not be sufficent as other side changes link later

if ($local_if && $local_if =~ /^ix\d/) {
    my $cmd = ("tcpdump -ni '$local_if' & sleep 1; kill \$!");
    system($cmd);
}

if ($remote_if && $remote_if =~ /^ix\d/) {
    my @sshcmd = ('ssh', $remote_ssh,
	"tcpdump -ni '$remote_if' & sleep 1; kill \$!");
    system(@sshcmd);
}

# iperf3 and tcpbench tests

if ($testmode{iperftcp4} || $testmode{iperfudp4}) {
    my @sshcmd = ('ssh', $remote_ssh, 'pkill -f "iperf3 -4"');
    system(@sshcmd);
    @sshcmd = ('ssh', '-f', $remote_ssh, 'iperf3', '-4', '-s', '-D');
    system(@sshcmd)
	and die "Start iperf3 server with '@sshcmd' failed: $?";
}

if ($testmode{iperftcp6} || $testmode{iperfudp6}) {
    my @sshcmd = ('ssh', $remote_ssh, 'pkill -f "iperf3 -6"');
    system(@sshcmd);
    @sshcmd = ('ssh', '-f', $remote_ssh, 'iperf3', '-6', '-s', '-D');
    system(@sshcmd)
	and die "Start iperf3 server with '@sshcmd' failed: $?";
}

if ($testmode{tcpbench4}) {
    my @sshcmd = ('ssh', $remote_ssh, 'pkill -f "tcpbench -4"');
    system(@sshcmd);
    @sshcmd = ('ssh', '-f', $remote_ssh, 'tcpbench', '-4', '-s', '-r0',
	'-S1000000');
    system(@sshcmd)
	and die "Start tcpbench server with '@sshcmd' failed: $?";
}

if ($testmode{tcpbench6}) {
    my @sshcmd = ('ssh', $remote_ssh, 'pkill -f "tcpbench -6"');
    system(@sshcmd);
    @sshcmd = ('ssh', '-f', $remote_ssh, 'tcpbench', '-6', '-s', '-r0',
	'-S1000000');
    system(@sshcmd)
	and die "Start tcpbench server with '@sshcmd' failed: $?";
}

my $kconf = `sysctl -n kern.osversion | cut -d# -f1`;
my $machine = `machine`;
my $ncpu = `sysctl -n hw.ncpu`;
chomp($kconf, $machine, $ncpu);

if ($testmode{make}) {
    my @cmd = ('make', "-C/usr/src/sys/arch/$machine/compile/$kconf");
    push @cmd, '-s' unless $opts{v};
    push @cmd, 'clean', 'config';
    system(@cmd)
	and die "Clean kernel with '@cmd' failed: $?";
}

system('sync');
sleep 1;

my %iperf3_ids;
sub iperf3_initialize {
    undef %iperf3_ids;
    return 1;
}

sub iperf3_parser {
    my ($line, $log) = @_;
    my $id;
    if ($line =~ m{^\[ *(\w+)\] }) {
	$id = $1;
	$iperf3_ids{$id}++ if $id =~ /^\d+$/;
    }
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
	    # with -P parallel connections parse only summary
	    if (keys %iperf3_ids <= 1 || $id eq "SUM") {
		print $tr "VALUE $value bits/sec $3\n";
		undef %iperf3_ids;
	    }
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

sub udpbench_parser {
    my ($line, $log) = @_;
    if ($line =~ m{^(send|recv): .*, bit/s ([\d.e+]+)$}) {
	my $direction = $1;
	my $value = 0 + $2;
	print $tr "VALUE $value bits/sec $direction\n";
    }
    return 1;
}

sub time_parser {
    my ($line, $log) = @_;
    if ($line =~ /^(\w+) +(\d+\.\d+)$/) {
	print $tr "VALUE $2 sec $1\n";
    }
    if ($line =~ /^ *(\d+)  ([\w ]+)$/) {
	print $tr "SUBVALUE $1 1 $2\n";
    }
    return 1;
}

my @fsmark_keys;
my @fsmark_values;
my @fsmark_units;
sub fsmark_parser {
    my ($line, $log) = @_;
    if (!@fsmark_keys) {
	@fsmark_keys = map { lc($_) } $line =~
	    m{^(FSUse)%\s+(Count)\s+(Size)\s+(Files)/sec\s+App (Overhead)$};
	if (@fsmark_keys) {
	    @fsmark_units = qw(percent 1 bytes 1/sec sec);
	    if (@fsmark_units != @fsmark_keys) {
		print $log "FAILED not 5 keys\n" if $log;
		print "FAILED not 5 keys\n" if $opts{v};
		return;
	    }
	}
    } elsif (!@fsmark_values) {
	@fsmark_values = split(" ", $line);
	if (@fsmark_keys != @fsmark_values) {
	    print $log "FAILED not 5 values\n" if $log;
	    print "FAILED not 5 values\n" if $opts{v};
	    return;
	}
	for (my $i = 0; $i < 5; $i++) {
	    my $value = $fsmark_values[$i];
	    my $unit = $fsmark_units[$i];
	    my $key = $fsmark_keys[$i];
	    $value /= 1000000 if $key eq "overhead";
	    print $tr "SUB" unless $key eq "files";
	    print $tr "VALUE $value $unit $key\n";
	}
    }
    return 1;
}

sub fsmark_finalize {
    my ($log) = @_;
    unless (@fsmark_values) {
	print $log "FAILED no values\n" if $log;
	print "FAILED no values\n" if $opts{v};
	return;
    }
    return 1;
}

my $wallclock;
sub wallclock_initialize {
    $wallclock = Time::HiRes::time();
    return 1;
}

sub wallclock_finalize {
    printf $tr "SUBVALUE %.2f sec wall\n", Time::HiRes::time() - $wallclock;
    return 1;
}

my @tests;
push @tests, (
    {
	testcmd => ['iperf3', "-c$remote_addr", '-w1m', '-t10'],
	parser => \&iperf3_parser,
    }, {
	testcmd => ['iperf3', "-c$remote_addr", '-w1m', '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{iperftcp4};
push @tests, (
    {
	testcmd => ['iperf3', '-6', "-c$remote_addr6", '-w1m', '-t10'],
	parser => \&iperf3_parser,
    }, {
	testcmd => ['iperf3', '-6', "-c$remote_addr6", '-w1m', '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{iperftcp6};
push @tests, (
    {
	# increase socket buffer limit on Linux machine
	# echo 2097152 >/proc/sys/net/core/rmem_max
	# echo 2097152 >/proc/sys/net/core/wmem_max
	testcmd => ['iperf3', "-c$linux_addr", '-w2m', '-t10'],
	parser => \&iperf3_parser,
    }, {
	testcmd => ['iperf3', "-c$linux_addr", '-w2m', '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{linuxiperftcp4} && $linux_addr;
push @tests, (
    {
	testcmd => ['iperf3', '-6', "-c$linux_addr6", '-w2m', '-t10'],
	parser => \&iperf3_parser,
    }, {
	testcmd => ['iperf3', '-6', "-c$linux_addr6", '-w2m', '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{linuxiperftcp6} && $linux_addr6;
push @tests, (
    {
	testcmd => ['tcpbench', '-S1000000', '-t10', $remote_addr],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['tcpbench', '-S1000000', '-t10', '-n100', $remote_addr],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }
) if $testmode{tcpbench4};
push @tests, (
    {
	testcmd => ['tcpbench', '-S1000000', '-t10', $remote_addr6],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['tcpbench', '-S1000000', '-t10', '-n100', $remote_addr6],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }
) if $testmode{tcpbench6};
push @tests, (
    {
	testcmd => ['iperf3', "-c$remote_addr", '-u', '-b10G', '-w1m', '-t10'],
	parser => \&iperf3_parser,
    }, {
	testcmd => ['iperf3', "-c$remote_addr", '-u', '-b10G', '-w1m', '-t10',
	    '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{iperfudp4};
push @tests, (
    {
	testcmd => ['iperf3', '-6', "-c$remote_addr6", '-u', '-b10G', '-w1m',
	    '-t10'],
	parser => \&iperf3_parser,
    }, {
	testcmd => ['iperf3', '-6', "-c$remote_addr6", '-u', '-b10G', '-w1m',
	    '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{iperfudp6};
push @tests, (
    {
	testcmd => ['udpbench', '-l36', '-t10', '-r', $remote_ssh,
	    'send', $remote_addr],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['udpbench', '-l36', '-t10', '-r', $remote_ssh,
	    'recv', $local_addr],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['udpbench', '-l1472', '-t10', '-r', $remote_ssh,
	    'send', $remote_addr],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['udpbench', '-l1472', '-t10', '-r', $remote_ssh,
	    'recv', $local_addr],
	parser => \&udpbench_parser,
    }
) if $testmode{udpbench4};
push @tests, (
    {
	testcmd => ['udpbench', '-l16', '-t10', '-r', $remote_ssh,
	    'send', $remote_addr6],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['udpbench', '-l16', '-t10', '-r', $remote_ssh,
	    'recv', $local_addr6],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['udpbench', '-l1452', '-t10', '-r', $remote_ssh,
	    'send', $remote_addr6],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['udpbench', '-l1452', '-t10', '-r', $remote_ssh,
	    'recv', $local_addr6],
	parser => \&udpbench_parser,
    }
) if $testmode{udpbench6};
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_ssh, 'iperf3', "-c$linux_forward_addr",
	    '-P10', '-t10'],
	parser => \&iperf3_parser,
    }
) if $testmode{forward4} && $linux_forward_addr && $linux_ssh;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_ssh, 'iperf3', '-6', "-c$linux_forward_addr6",
	    '-P10', '-t10'],
	parser => \&iperf3_parser,
    }
) if $testmode{forward6} && $linux_forward_addr6 && $linux_ssh;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_ssh, 'iperf3', "-c$linux_relay_addr",
	    '-P10', '-t10'],
	parser => \&iperf3_parser,
    }
) if $testmode{relay4} && $linux_relay_addr && $linux_ssh;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_ssh, 'iperf3', '-6', "-c$linux_relay_addr6",
	    '-P10', '-t10'],
	parser => \&iperf3_parser,
    }
) if $testmode{relay6} && $linux_relay_addr6 && $linux_ssh;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_other_ssh, 'iperf3',
	    "-c$linux_relay_local_addr", '-P10', '-t10'],
	parser => \&iperf3_parser,
    }
) if $testmode{relay4} && $linux_relay_local_addr && $linux_other_ssh;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_other_ssh, 'iperf3', '-6',
	    "-c$linux_relay_local_addr6", '-P10', '-t10'],
	parser => \&iperf3_parser,
    }
) if $testmode{relay6} && $linux_relay_local_addr6 && $linux_other_ssh;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_other_ssh, 'iperf3',
	    "-c$linux_relay_remote_addr", '-P10', '-t10'],
	parser => \&iperf3_parser,
    }
) if $testmode{relay4} && $linux_relay_remote_addr && $linux_other_ssh;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_other_ssh, 'iperf3', '-6',
	    "-c$linux_relay_remote_addr6", '-P10', '-t10'],
	parser => \&iperf3_parser,
    }
) if $testmode{relay6} && $linux_relay_remote_addr6 && $linux_other_ssh;
push @tests, (
    {
	initialize => \&wallclock_initialize,
	testcmd => ['time', '-lp', 'make',
	    "-C/usr/src/sys/arch/$machine/compile/$kconf", "-j$ncpu", '-s'],
	parser => \&time_parser,
	finalize => \&wallclock_finalize,
    }
) if $testmode{make};
push @tests, (
    {
	testcmd => ['time', '-lp', 'fs_mark',
	    '-d/var/cache/fs_mark', '-D8', '-N16', '-n256', '-t8'],
	parser => \&fsmark_parser,
	finalize => \&fsmark_finalize,
    }
) if $testmode{fs};

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
	    if ($t->{parser}) {
		local $_ = $_;
		$t->{parser}($_, $log)
		    or bad $test, 'FAIL', "Could not parse value", $log
	    }
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
if ($testmode{iperftcp4} || $testmode{iperfudp4} || $testmode{tcpbench4} ||
    $testmode{iperftcp6} || $testmode{iperfudp6} || $testmode{tcpbench6}) {
    my @sshcmd = ('ssh', $remote_ssh, 'pkill', 'iperf3', 'tcpbench');
    system(@sshcmd);
}

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
