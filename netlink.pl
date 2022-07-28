#!/usr/bin/perl

# Copyright (c) 2022 Moritz Buhl <mbuhl@genua.de>
# Copyright (c) 2018-2021 Alexander Bluhm <bluhm@genua.de>
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

sub usage {
    print STDERR <<"EOF";
usage: $0 interface [pseudo-dev] test
    interface	em, igc, ix, ixl
    pseudo-dev	veb, bridge, trunk, aggr, carp
    test	all, inet, inet6, fragment, icmp, ipopts, pathmtu, udp, tcp
EOF
    exit(2);
}

my %opts;
getopts('v', \%opts) or usage;

usage if ($#ARGV < 1 || $#ARGV > 2);

my %allifs;
@allifs{qw(em igc ix ixl)} = ();
die "Unknown test interface: ${ARGV[0]}" unless exists $allifs{$ARGV[0]};
my $testif = $ARGV[0];
shift @ARGV;

my %allpseudodevs;
@allpseudodevs{qw(veb bridge trunk aggr carp)} = ();
if ($#ARGV) {
    die "Unknown test pseudo-device: ${ARGV[0]}" unless exists $allpseudodevs{$ARGV[0]};
    my $testpseudodev = $ARGV[0];
    shift @ARGV;
}

my %allmodes;
@allmodes{qw(all inet inet6 fragment icmp ipopts pathmtu udp tcp)} = ();
my %testmode = map {
    die "Unknown test mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} $ARGV[0];
shift @ARGV;

my $local_if = $ENV{LOCAL_IF};
my $remote_if = $ENV{REMOTE_IF};
my $remote_ssh = $ENV{REMOTE_SSH}
    ;#or die "Environemnt REMOTE_SSH not set";
my $local_addr = $ENV{LOCAL_ADDR}
    ;#or die "Environemnt LOCAL_ADDR not set";
my $remote_addr = $ENV{REMOTE_ADDR}
    ;#or die "Environemnt REMOTE_ADDR not set";
my $local_addr6 = $ENV{LOCAL_ADDR6}
    ;#or die "Environemnt LOCAL_ADDR6 not set";
my $remote_addr6 = $ENV{REMOTE_ADDR6}
    ;#or die "Environemnt REMOTE_ADDR6 not set";

my $linux_addr = $ENV{LINUX_ADDR};
my $linux_addr6 = $ENV{LINUX_ADDR6};
my $linux_forward_addr = $ENV{LINUX_FORWARD_ADDR};
my $linux_forward_addr6 = $ENV{LINUX_FORWARD_ADDR6};
my $linux_relay_addr = $ENV{LINUX_RELAY_ADDR};
my $linux_relay_addr6 = $ENV{LINUX_RELAY_ADDR6};
my $linux_ipsec_addr = $ENV{LINUX_IPSEC_ADDR};
my $linux_ipsec_addr6 = $ENV{LINUX_IPSEC_ADDR6};
my $linux_ipsec6_addr = $ENV{LINUX_IPSEC6_ADDR};
my $linux_ipsec6_addr6 = $ENV{LINUX_IPSEC6_ADDR6};
my $linux_ssh = $ENV{LINUX_SSH};

my $linux_relay_local_addr = $ENV{LINUX_RELAY_LOCAL_ADDR};
my $linux_relay_local_addr6 = $ENV{LINUX_RELAY_LOCAL_ADDR6};
my $linux_relay_remote_addr = $ENV{LINUX_RELAY_REMOTE_ADDR};
my $linux_relay_remote_addr6 = $ENV{LINUX_RELAY_REMOTE_ADDR6};
my $linux_other_ssh = $ENV{LINUX_OTHER_SSH};

my $ip4prefix = '10.10';
my $ip6prefix = 'fdd7:e83e:66bd:0';

my $dir = dirname($0);
chdir($dir)
    or die "Change directory to '$dir' failed: $!";
my $netlinkdir = getcwd();

# write summary of results into result file
open(my $tr, '>', "test.result")
    or die "Open 'test.result' for writing failed: $!";
$tr->autoflush();
$| = 1;

my $logdir = "$netlinkdir/logs";
remove_tree($logdir);
mkdir $logdir
    or die "Make directory '$logdir' failed: $!";
chdir($logdir)
    or die "Change directory to '$logdir' failed: $!";

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

my $kconf = `sysctl -n kern.osversion | cut -d# -f1`;
my $hostname = `hostname -s`;
my $machine = `machine`;
my $ncpu = `sysctl -n hw.ncpu`;
chomp($kconf, $hostname, $machine, $ncpu);

# map hostname to testing line
my %lines;
$lines{ot41} = 1;
$lines{ot42} = 2;

# unconfigure all interfaces used in testing
my @allinterfaces = `ifconfig | grep ^[a-z] | cut -d: -f1`;
chomp(@allinterfaces);

foreach my $ifn (@allinterfaces) {
    unless ($ifn =~ m{^(lo|enc|pflog|em0)}) {
	system("ifconfig ${ifn} -inet -inet6 down");
    }
    my $pdevre = join '|', keys %allpseudodevs;
    system("ifconfig ${ifn} destroy") if ($ifn =~ m{^($pdevre)});
}

# em0 usually is our configuration interface
my $ifl = $testif . (($testif =~ m {^em})? 1 : 0);
my $ifr = $testif . (($testif =~ m {^em})? 2: 1);

# configure given interface type
if ($testmode{inet6}) {
    system("ifconfig ${ifl} inet6 ${ip6prefix}:$lines{$hostname}1::2 up");
    system("ifconfig ${ifr} inet6 ${ip6prefix}:$lines{$hostname}2::3 up");
} else {
    system("ifconfig ${ifl} inet $ip4prefix.$lines{$hostname}1.2/24 up");
    system("ifconfig ${ifr} inet $ip4prefix.$lines{$hostname}2.3/24 up");
}
exit;

# tcpbench tests

if ($testmode{tcp}) {
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
    }, {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_ssh, 'iperf3', "-c$linux_forward_addr",
	    '-P10', '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{forward4} && $linux_forward_addr && $linux_ssh;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_ssh, 'iperf3', '-6', "-c$linux_forward_addr6",
	    '-P10', '-t10'],
	parser => \&iperf3_parser,
    }, {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_ssh, 'iperf3', '-6', "-c$linux_forward_addr6",
	    '-P10', '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{forward6} && $linux_forward_addr6 && $linux_ssh;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_ssh, 'iperf3', "-c$linux_relay_addr",
	    '-P10', '-t10'],
	parser => \&iperf3_parser,
    }, {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_ssh, 'iperf3', "-c$linux_relay_addr",
	    '-P10', '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{relay4} && $linux_relay_addr && $linux_ssh;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_ssh, 'iperf3', '-6', "-c$linux_relay_addr6",
	    '-P10', '-t10'],
	parser => \&iperf3_parser,
    }, {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_ssh, 'iperf3', '-6', "-c$linux_relay_addr6",
	    '-P10', '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{relay6} && $linux_relay_addr6 && $linux_ssh;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_other_ssh, 'iperf3',
	    "-c$linux_relay_local_addr", '-P10', '-t10'],
	parser => \&iperf3_parser,
    }, {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_other_ssh, 'iperf3',
	    "-c$linux_relay_local_addr", '-P10', '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{relay4} && $linux_relay_local_addr && $linux_other_ssh;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_other_ssh, 'iperf3', '-6',
	    "-c$linux_relay_local_addr6", '-P10', '-t10'],
	parser => \&iperf3_parser,
    }, {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_other_ssh, 'iperf3', '-6',
	    "-c$linux_relay_local_addr6", '-P10', '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{relay6} && $linux_relay_local_addr6 && $linux_other_ssh;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_other_ssh, 'iperf3',
	    "-c$linux_relay_remote_addr", '-P10', '-t10'],
	parser => \&iperf3_parser,
    }, {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_other_ssh, 'iperf3',
	    "-c$linux_relay_remote_addr", '-P10', '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{relay4} && $linux_relay_remote_addr && $linux_other_ssh;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_other_ssh, 'iperf3', '-6',
	    "-c$linux_relay_remote_addr6", '-P10', '-t10'],
	parser => \&iperf3_parser,
    }, {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_other_ssh, 'iperf3', '-6',
	    "-c$linux_relay_remote_addr6", '-P10', '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{relay6} && $linux_relay_remote_addr6 && $linux_other_ssh;

my @stats = (
    {
	statcmd => [ 'netstat', '-s' ],
    }, {
	statcmd => [ 'netstat', '-m' ],
    }, {
	statcmd => [ 'netstat', '-inv' ],
    }, {
	statcmd => [ 'netstat', '-binv' ],
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

    eval { $t->{startup}($log) if $t->{startup}; };
    if ($@) {
	bad $test, 'NOEXIST', "Could not startup", $log;
    }

    statistics($test, "before");

    defined(my $pid = open(my $out, '-|'))
	or bad $test, 'NORUN', "Open pipe from '@runcmd' failed: $!", $log;
    if ($pid == 0) {
	# child process
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
	$t->{initialize}($log)
	    or bad $test, 'FAIL', "Could not initialize test", $log
	    if $t->{initialize};
	while (<$out>) {
	    print $log $_;
	    if ($t->{parser}) {
		local $_ = $_;
		$t->{parser}($_, $log)
		    or bad $test, 'FAIL', "Could not parse value", $log;
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

    statistics($test, "after");

    eval { $t->{shutdown}($log) if $t->{shutdown}; };
    if ($@) {
	bad $test, 'NOCLEAN', "Could not shutdown", $log;
    }

    my $end = Time::HiRes::time();
    good $test, $end - $begin, $log;

    close($log)
	or die "Close log '$logfile' after writing failed: $!";
}

chdir($netlinkdir)
    or die "Change directory to '$netlinkdir' failed: $!";

# kill remote commands or ssh will hang forever
if ($testmode{tcpbench4} || $testmode{tcpbench6}) {
    my @sshcmd = ('ssh', $remote_ssh, 'pkill', 'tcpbench');
    system(@sshcmd);
}

# create a tgz file with all log files
my @paxcmd = ('pax', '-x', 'cpio', '-wzf', "$netlinkdir/test.log.tgz");
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
	    or die "Fork failed: $!";
	unless ($pid) {
	    # child process
	    open(STDOUT, ">&", $fh)
		or die "Redirect stdout to '$name' failed: $!";
	    open(STDERR, ">&", $fh)
		or die "Redirect stderr to '$name' failed: $!";
	    exec(@statcmd);
	    warn "Exec '@statcmd' failed: $!";
	    _exit(126);
	}
	waitpid($pid, 0)
	    or die "Wait for pid '$pid' failed: $!";
	$? == 0
	    or die "Command '@statcmd' failed: $?";
    }
}

sub netstat_m_parser {
	my ($l, $log) = @_;
	if ($l =~ m{(\d+) mbufs in use}) {
		my $mbufs = $1;
		print "used mbufs: $mbufs\n";
	} elsif ($l =~ m{(\d+) mbufs allocated to data}) {
		my $data_mbufs = $1;
		print "data mbufs: $data_mbufs\n";
	} elsif ($l =~ m{(\d+) mbufs allocated to packet headers}) {
		my $header_mbufs = $1;
		print "header mbufs: $header_mbufs\n";
	} elsif ($l =~ m{(\d+) mbufs allocated to socket names and addresses}) {
		my $named_mbufs = $1;
		print "named mbufs: $named_mbufs\n";
	} elsif ($l =~ m{(\d+)/(\d+) mbuf (\d+) byte clusters in use}) {
		my ($current, $peak, $mbuf_size) = ($1, $2, $3);
		print "mbufs of size $mbuf_size: curr: $current peak: $peak\n";
	} elsif ($l =~ m{(\d+)/(\d+)/(\d+) Kbytes allocated to network}) {
		my ($current, $peak, $max) = ($1, $2, $3);
		print "network mbufs: curr: $current peak: $peak max: $max\n";
	} elsif ($l =~ m{(\d+) requests for memory denied}) {
		my $denied = $1;
		print "denied requests: $denied\n";
	} elsif ($l =~ m{(\d+) requests for memory delayed}) {
		my $delayed = $1;
		print "delayed requests: $delayed\n";
	} elsif ($l =~ m{(\d+) calls to protocol drain routines}) {
		my $drains = $1;
		print "called drains: $drains\n";
	}
}

sub netstat_s_parser {
}

sub netstat_binv_parser {
	my ($l, $log) = @_;
	if ($l =~ m{([a-z]+\d+\*?)\s+(\d+)\s+<Link>[0-9a-f:\s]+\s+(\d+)\s+(\d+)}) {
		my $ifn = $1;
		my $mtu = $2;
		my $Ibytes = $3;
		my $Obytes = $4;
		print "$ifn ($mtu) >$Ibytes <$Obytes\n";
	}
	#} elsif ($l =~ m{(\d+) mbufs allocated to data}) {
}

sub netstat_inv_parser {
	my ($l, $log) = @_;
	my $mac = m{(?:(?:[0-9a-f]{2}:){5}[0-9a-f]{2})};
	if ($l =~ m{([a-z]+\d+\*?)\s+(\d+)\s+<Link>\s+(?:(?:[0-9a-f]{2}:){5}[0-9a-f]{2})?\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)}) {
		my $ifn = $1;
		my $mtu = $2;
		my $Ipkts = $3;
		my $Ifail = $4;
		my $Opkts = $5;
		my $Ofail = $6;
		my $colls = $7;
		print "$ifn ($mtu)\t>$Ipkts -$Ifail <$Opkts -$Ofail c$colls\n";
	}
}

sub vmstat_iz_parser {
	my ($l, $log) = @_;
	if ($l =~ m{irq\d+/(\w+)\s+(\d+)\s+(\d+)}) {
		my $dev = $1;
		my $total = $2;
		my $rate = $3;

		print "$dev has $total at $rate\n";
	}
}

sub vmstat_m_tail_1_parser {
	my ($l, $log) = @_;
	if ($l =~ m{In use (\d+)K, total allocated (\d+)K; utilization ([0-9.]+)%}) {
		my $used = $1;
		my $allocated = $2;
		my $utilization = $3;

		print "Memory: $used/$allocated = $utilization\n";
	}
}
