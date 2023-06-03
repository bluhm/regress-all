#!/usr/bin/perl

# Copyright (c) 2018-2023 Alexander Bluhm <bluhm@genua.de>
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

my $startdir = getcwd();
my @startcmd = ($0, @ARGV);

my @allmodifymodes = qw(lro nopf notso pfsync);
my @alltestmodes = qw(
    all net tcp udp make fs iperf tcpbench udpbench iperftcp
    iperfudp net4 tcp4 udp4 iperf4 tcpbench4 udpbench4 iperftcp4 iperfudp4
    net6 tcp6 udp6 iperf6 tcpbench6 udpbench6 iperftcp6 iperfudp6
    localnet localnet4 localnet6
    linuxnet linuxiperftcp4 linuxiperftcp6
    forward forward4 forward6 relay relay4 relay6 frag frag4 frag6
    ipsec ipsec4 ipsec6 ipsec44 ipsec46 ipsec64 ipsec66
    veb veb4 veb6 vbridge vbridge4 vbridge6 vport vport4 vport6
);

my %opts;
getopts('b:e:m:t:sv', \%opts) or do {
    print STDERR <<"EOF";
usage: perform.pl [-sv] [-b kstack] [-e environment] [-m modify] [-t timeout]
	[test ...]
    -b kstack	measure with btrace and create kernel stack map
    -e environ	parse environment for tests from shell script
    -m modify	modify mode: @allmodifymodes
    -s		stress test, run tests longer, activate sysctl
    -t timeout	timeout for a single test, default 1 hour
    -v		verbose
    test ...	@alltestmodes
EOF
    exit(2);
};
my $btrace = $opts{b};
!$btrace || $btrace eq "kstack"
    or die "Btrace -b '$btrace' not supported, use 'kstack'";
my $modify = $opts{m};
!$modify || grep { $_ eq $modify } @allmodifymodes
    or die "Unknnown modify mode '$modify'";
my $timeout = $opts{t} || 60*60;
environment($opts{e}) if $opts{e};
my $stress = $opts{s};

my %testmode;
foreach my $mode (@ARGV) {
    grep { $_ eq $mode } @alltestmodes
	or die "Unknown test mode '$mode'";
    $testmode{$mode} = 1;
}
$testmode{all} = 1 unless @ARGV;
@testmode{qw(net make fs)} = 1..3 if $testmode{all};
@testmode{qw(net4 net6 forward relay ipsec veb)} = 1..6 if $testmode{net};
@testmode{qw(tcp4 udp4 forward4 relay4 ipsec4 ipsec44 veb4)} = 1..7
    if $testmode{net4};
@testmode{qw(tcp6 udp6 forward6 relay6 ipsec6 ipsec66 veb6)} = 1..7
    if $testmode{net6};
@testmode{qw(localnet4 localnet6)} = 1..2 if $testmode{localnet};
@testmode{qw(iperftcp4 iperfudp4 tcpbench4 udpbench4)} = 1..4
    if $testmode{localnet4};
@testmode{qw(iperftcp6 iperfudp6 tcpbench6 udpbench6)} = 1..4
    if $testmode{localnet6};
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
@testmode{qw(frag4 frag6)} = 1..2 if $testmode{frag};
@testmode{qw(ipsec4 ipsec44 ipsec46 ipsec6 ipsec64 ipsec66)} = 1..6
    if $testmode{ipsec};
@testmode{qw(veb4 veb6)} = 1..2 if $testmode{veb};
@testmode{qw(vbridge4 vport4)} = 1..2 if $testmode{veb4};
@testmode{qw(vbridge6 vport6)} = 1..2 if $testmode{veb6};
@testmode{qw(vbridge4 vbridge6)} = 1..2 if $testmode{vbridge};
@testmode{qw(vport4 vport6)} = 1..2 if $testmode{vport};

if ($stress) {
    my %sysctl = (
	'kern.pool_debug'	=> 1,
	'kern.splassert'	=> 3,
	'kern.witness.watch'	=> 3,
    );
    foreach my $k (sort keys %sysctl) {
	my $v = $sysctl{$k};
	my @cmd = ('/sbin/sysctl', "$k=$v");
	system(@cmd)
	    and die "Sysctl '$k=$v' failed: $?";
    }
}

my $dir = dirname($0);
chdir($dir)
    or die "Change directory to '$dir' failed: $!";
my $performdir = getcwd();

# write summary of results into result file
rename("test.result", "test.result.old") if $stress;
open(my $tr, '>', "test.result")
    or die "Open 'test.result' for writing failed: $!";
$tr->autoflush();
$| = 1;

my $logdir = "$performdir/logs";
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

sub logcmd {
    my ($log, @cmd) = @_;
    print $log "@cmd\n";
    print "@cmd\n" if $opts{v};

    defined(my $pid = open(my $fh, '-|'))
	or die "Open pipe from '@cmd' failed: $!";
    if ($pid == 0) {
	$SIG{__DIE__} = 'DEFAULT';
	close($fh);
	open(STDIN, '<', "/dev/null")
	    or die "Redirect stdin to /dev/null failed: $!";
	open(STDERR, '>&', \*STDOUT)
	    or die "Redirect stderr to stdout failed: $!";
	setsid()
	    or die "Setsid $$ failed: $!";
	{
	    no warnings 'exec';
	    exec(@cmd);
	    die "Exec '@cmd' failed: $!";
	}
	_exit(126);
    }
    local $_;
    while (<$fh>) {
	s/[^\s[:print:]]/_/g;
	print $log $_;
	print $_ if $opts{v};
    }
    $log->sync();
    close($fh)
	or $! && die "Close pipe from '@cmd' failed: $!";
    return $?;
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
my $local_ipsec_addr = $ENV{LOCAL_IPSEC_ADDR};
my $remote_ipsec_addr = $ENV{REMOTE_IPSEC_ADDR};
my $local_ipsec6_addr = $ENV{LOCAL_IPSEC6_ADDR};
my $remote_ipsec6_addr = $ENV{REMOTE_IPSEC6_ADDR};
my $local_ipsec_trans_addr = $ENV{LOCAL_IPSEC_TRANS_ADDR};
my $remote_ipsec_trans_addr = $ENV{REMOTE_IPSEC_TRANS_ADDR};
my $local_ipsec_trans_addr6 = $ENV{LOCAL_IPSEC_TRANS_ADDR6};
my $remote_ipsec_trans_addr6 = $ENV{REMOTE_IPSEC_TRANS_ADDR6};

my $linux_addr = $ENV{LINUX_ADDR};
my $linux_addr6 = $ENV{LINUX_ADDR6};
my $linux_forward_addr = $ENV{LINUX_FORWARD_ADDR};
my $linux_forward_addr6 = $ENV{LINUX_FORWARD_ADDR6};
my $linux_relay_addr = $ENV{LINUX_RELAY_ADDR};
my $linux_relay_addr6 = $ENV{LINUX_RELAY_ADDR6};
my $linux_linux_addr = $ENV{LINUX_LINUX_ADDR};
my $linux_linux_addr6 = $ENV{LINUX_LINUX_ADDR6};
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

my $linux_veb_addr = $ENV{LINUX_VEB_ADDR};
my $linux_veb_addr6 = $ENV{LINUX_VEB_ADDR6};

my $pfsync_if = $ENV{PFSYNC_IF};
my $pfsync_addr = $ENV{PFSYNC_ADDR};
my $pfsync_peer_if = $ENV{PFSYNC_PEER_IF};
my $pfsync_peer_addr = $ENV{PFSYNC_PEER_ADDR};
my $pfsync_ssh = $ENV{PFSYNC_SSH};

my $netbench = "$performdir/netbench.pl";

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

# I have seen hanging iperf3 processes on linux machines, reap them

if ($linux_ssh) {
    my @sshcmd = ('ssh', $linux_ssh, 'pkill', 'iperf3');
    system(@sshcmd);
}
if ($linux_other_ssh) {
    my @sshcmd = ('ssh', $linux_other_ssh, 'pkill', 'iperf3');
    system(@sshcmd);
    @sshcmd = ('ssh', $linux_other_ssh, 'iperf3', '-sD');
    system(@sshcmd)
	and die "Start linux iperf3 server with '@sshcmd' failed: $?";
}

# tcpbench tests

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

sub iked_startup {
    my ($log) = @_;
    my @cmd = ('/etc/rc.d/iked', '-f', 'restart');
    logcmd($log, @cmd) and
	die "Command '@cmd' failed: $?";
    my @sshcmd = ('ssh', $remote_ssh, @cmd);
    logcmd($log, @sshcmd) and
	die "Command '@sshcmd' failed: $?";
    @cmd = ('ping', '-n', '-c1', '-w1',
	'-I', $local_ipsec_addr, $remote_ipsec_addr);
    foreach (1..20) {
	sleep 1;
	logcmd($log, @cmd) or return;
    }
    die "Command '@cmd' failed for 20 seconds: $?";

    print $log "iked started\n\n";
    print "iked started\n\n" if $opts{v};
}

sub iked_shutdown {
    my ($log) = @_;
    # XXX give the iperf3 server on linux host some time to close connection
    sleep 5;
    print $log "\nstopping iked\n";
    print "\nstopping iked\n" if $opts{v};

    my @cmd = ('/etc/rc.d/iked', '-f', 'stop');
    logcmd($log, @cmd) and
	die "Command '@cmd' failed: $?";
    my @sshcmd = ('ssh', $remote_ssh, @cmd);
    logcmd($log, @sshcmd) and
	die "Command '@sshcmd' failed: $?";
    sleep 1;
    @cmd = ('ipsecctl', '-F');
    logcmd($log, @cmd) and
	die "Command '@cmd' failed: $?";
    @sshcmd = ('ssh', $remote_ssh, @cmd);
    logcmd($log, @sshcmd) and
	die "Command '@sshcmd' failed: $?";
}

sub lro_get_ifs {
    my @cmd = ('/sbin/ifconfig', '-a', 'hwfeatures');
    unshift @cmd, @_;
    open(my $fh, '-|', @cmd)
	or die "Open pipe from command '@cmd' failed: $!";
    my ($ifname, @ifs);
    while (<$fh>) {
	    $ifname = $1 if /^(\w+\d+):/;
	    push @ifs, $ifname if /hwfeatures=.*\bLRO\b/;
    }
    close($fh) or die $! ?
	"Close pipe from command '@cmd' failed: $!" :
	"Command '@cmd' failed: $?";
    return @ifs;
}

my (@lro_ifs, @remote_lro_ifs);
sub lro_startup {
    my ($log) = @_;

    @lro_ifs = lro_get_ifs();
    foreach my $ifname (@lro_ifs) {
	my @cmd = ('/sbin/ifconfig', $ifname, 'tcprecvoffload');
	logcmd($log, @cmd) and
	    die "Command '@cmd' failed: $?";
    }
    @remote_lro_ifs = lro_get_ifs('ssh', $remote_ssh);
    foreach my $ifname (@remote_lro_ifs) {
	my @cmd = ('/sbin/ifconfig', $ifname, 'tcprecvoffload');
	my @sshcmd = ('ssh', $remote_ssh, @cmd);
	logcmd($log, @sshcmd) and
	    die "Command '@sshcmd' failed: $?";
    }

    # changing LRO may lose interface link status due to down/up
    sleep 1;
    print $log "lro enabled\n\n";
    print "lro enabled\n\n" if $opts{v};
}

sub lro_shutdown {
    my ($log) = @_;
    print $log "\ndisabling lro\n";
    print "\ndisabling lro\n" if $opts{v};

    foreach my $ifname (@lro_ifs) {
	my @cmd = ('/sbin/ifconfig', $ifname, '-tcprecvoffload');
	logcmd($log, @cmd) and
	    die "Command '@cmd' failed: $?";
    }
    foreach my $ifname (@remote_lro_ifs) {
	my @cmd = ('/sbin/ifconfig', $ifname, '-tcprecvoffload');
	my @sshcmd = ('ssh', $remote_ssh, @cmd);
	logcmd($log, @sshcmd) and
	    die "Command '@sshcmd' failed: $?";
    }
}

sub nopf_startup {
    my ($log) = @_;
    my @cmd = ('/sbin/pfctl', '-d');
    logcmd($log, @cmd) and
	die "Command '@cmd' failed: $?";
    my @sshcmd = ('ssh', $remote_ssh, @cmd);
    logcmd($log, @sshcmd) and
	die "Command '@sshcmd' failed: $?";

    print $log "pf disabled\n\n";
    print "pf disabled\n\n" if $opts{v};
}

sub nopf_shutdown {
    my ($log) = @_;
    print $log "\nenabling pf\n";
    print "\nenabling pf\n" if $opts{v};

    my @cmd = ('/sbin/pfctl', '-e', '-f', '/etc/pf.conf');
    logcmd($log, @cmd) and
	die "Command '@cmd' failed: $?";
    my @sshcmd = ('ssh', $remote_ssh, @cmd);
    logcmd($log, @sshcmd) and
	die "Command '@sshcmd' failed: $?";
}

sub notso_startup {
    my ($log) = @_;
    my @cmd = ('/sbin/sysctl', 'net.inet.tcp.tso=0');
    logcmd($log, @cmd) and
	die "Command '@cmd' failed: $?";
    my @sshcmd = ('ssh', $remote_ssh, @cmd);
    logcmd($log, @sshcmd) and
	die "Command '@sshcmd' failed: $?";

    print $log "tso disabled\n\n";
    print "tso disabled\n\n" if $opts{v};
}

sub notso_shutdown {
    my ($log) = @_;
    print $log "\nenabling tso\n";
    print "\nenabling tso\n" if $opts{v};

    my @cmd = ('/sbin/sysctl', 'net.inet.tcp.tso=1');
    logcmd($log, @cmd) and
	die "Command '@cmd' failed: $?";
    my @sshcmd = ('ssh', $remote_ssh, @cmd);
    logcmd($log, @sshcmd) and
	die "Command '@sshcmd' failed: $?";
}

sub pfsync_startup {
    my ($log) = @_;
    my @cmd = ('/sbin/ifconfig', 'pfsync0',
	'syncdev', $pfsync_if, 'syncpeer', $pfsync_peer_addr, 'up');
    logcmd($log, @cmd) and
	die "Command '@cmd' failed: $?";
    my @sshcmd = ('ssh', $pfsync_ssh, '/sbin/ifconfig', 'pfsync0',
	'syncdev', $pfsync_peer_if, 'syncpeer', $pfsync_addr, 'up');
    logcmd($log, @sshcmd) and
	die "Command '@sshcmd' failed: $?";

    print $log "pfsync created\n\n";
    print "pfsync created\n\n" if $opts{v};
}

sub pfsync_shutdown {
    my ($log) = @_;
    print $log "\ndestroying pfsync\n";
    print "\ndestroying pfsync\n" if $opts{v};

    my @cmd = ('/sbin/ifconfig', 'pfsync0', 'destroy');
    logcmd($log, @cmd) and
	die "Command '@cmd' failed: $?";
    my @sshcmd = ('ssh', $pfsync_ssh, '/sbin/ifconfig', 'pfsync0', 'destroy');
    logcmd($log, @sshcmd) and
	die "Command '@sshcmd' failed: $?";
}

sub time_parser {
    my ($line, $log) = @_;
    if ($line =~ /^(\w+) +(\d+\.\d+)$/) {
	print $tr "VALUE $2 sec $1\n";
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
	    print $tr "VALUE $value $unit $key\n" if $key eq "files";
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
my @frag = (
    {
	# local send, other OpenBSD recv
	client => undef,
	server => $remote_ssh,
	address => '$remote_addr',
    },
    {
	# local recv, other OpenBSD send
	client => $remote_ssh,
	server => undef,
	address => '$local_addr',
    },
    {
	# local recv, Linux send
	client => $linux_ssh,
	server => undef,
	address => '$linux_relay_addr',
    },
    {
	# local send, other Linux recv
	client => undef,
	server => $linux_other_ssh,
	address => '$linux_forward_addr',
    },
    {
	# Linux send, local forward, other Linux recv
	client => $linux_ssh,
	server => $linux_other_ssh,
	address => '$linux_forward_addr',
    },
);
foreach my $payload (0, 1500 - 28, 1500 - 28 + 1500 - 20, 2**16 - 1 - 28) {
    push @tests, map {
	{
	    testcmd => [$netbench,
		'-b1000000',
		"-l$payload",
		 $_->{client} ? ("-c$_->{client}") : (),
		 $_->{server} ? ("-s$_->{server}") : (),
		'-a'. eval "$_->{address}",
		'-t10',
		'udpbench'],
	    parser => \&udpbench_parser,
	}
    } @frag if $testmode{frag4};
}
foreach my $payload (0, 1500 - 48, 1500 - 56 + 1500 - 48 - 8, 2**16 - 1 - 8) {
    push @tests, map {
	{
	    testcmd => [$netbench,
		'-b1000000',
		"-l$payload",
		 $_->{client} ? ("-c$_->{client}") : (),
		 $_->{server} ? ("-s$_->{server}") : (),
		'-a'. eval "$_->{address}6",
		'-t10',
		'udpbench'],
	    parser => \&udpbench_parser,
	}
    } @frag if $testmode{frag6};
}
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
my %ipsec = (
    ipsec4  => { ip => 4, addr => $remote_ipsec_trans_addr },
    ipsec6  => { ip => 6, addr => $remote_ipsec_trans_addr6 },
    ipsec44 => { ip => 4, addr => $linux_ipsec_addr,   ssh => $linux_ssh },
    ipsec46 => { ip => 6, addr => $linux_ipsec_addr6,  ssh => $linux_ssh },
    ipsec64 => { ip => 4, addr => $linux_ipsec6_addr,  ssh => $linux_ssh },
    ipsec66 => { ip => 6, addr => $linux_ipsec6_addr6, ssh => $linux_ssh },
);
my @ipsectests;
foreach my $ipsecmode (sort keys %ipsec) {
    $testmode{$ipsecmode}
	or next;
    my $ssh = $ipsec{$ipsecmode}{ssh};
    my $ip = $ipsec{$ipsecmode}{ip};
    my $addr = $ipsec{$ipsecmode}{addr}
	or next;
    my @cmd;
    push @cmd, 'ssh', $ssh if $ssh;
    push @cmd, 'iperf3';
    push @cmd, '-6' if $ip == 6;
    push @cmd, "-c$addr";
    push @ipsectests, (
	{
	    initialize => \&iperf3_initialize,
	    testcmd => [ @cmd, '-P10', '-t10'],
	    parser => \&iperf3_parser,
	}, {
	    initialize => \&iperf3_initialize,
	    testcmd => [@cmd, '-P10', '-t10', '-R'],
	    parser => \&iperf3_parser,
	}
    );
}
if (@ipsectests) {
    $ipsectests[0]{startup} = \&iked_startup;
    $ipsectests[-1]{shutdown} = \&iked_shutdown;
}
push @tests, @ipsectests;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_ssh, 'iperf3', "-c$linux_veb_addr",
	    '-P10', '-t10'],
	parser => \&iperf3_parser,
    }, {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_ssh, 'iperf3', "-c$linux_veb_addr",
	    '-P10', '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{vbridge4} && $linux_veb_addr && $linux_ssh;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_ssh, 'iperf3', '-6', "-c$linux_veb_addr6",
	    '-P10', '-t10'],
	parser => \&iperf3_parser,
    }, {
	initialize => \&iperf3_initialize,
	testcmd => ['ssh', $linux_ssh, 'iperf3', '-6', "-c$linux_veb_addr6",
	    '-P10', '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{vbridge6} && $linux_veb_addr6 && $linux_ssh;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['iperf3', "-c$linux_veb_addr", '-w1m', '-t10'],
	parser => \&iperf3_parser,
    }, {
	initialize => \&iperf3_initialize,
	testcmd => ['iperf3', "-c$linux_veb_addr", '-w1m', '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{vport4} && $linux_veb_addr;
push @tests, (
    {
	initialize => \&iperf3_initialize,
	testcmd => ['iperf3', '-6', "-c$linux_veb_addr6", '-w1m', '-t10'],
	parser => \&iperf3_parser,
    }, {
	initialize => \&iperf3_initialize,
	testcmd => ['iperf3', '-6', "-c$linux_veb_addr6", '-w1m', '-t10', '-R'],
	parser => \&iperf3_parser,
    }
) if $testmode{vport6} && $linux_veb_addr6;
if ($modify && $modify eq 'lro') {
    $tests[0]{startup} = \&lro_startup;
    $tests[-1]{shutdown} = \&lro_shutdown;
}
if ($modify && $modify eq 'nopf') {
    $tests[0]{startup} = \&nopf_startup;
    $tests[-1]{shutdown} = \&nopf_shutdown;
}
if ($modify && $modify eq 'notso') {
    $tests[0]{startup} = \&notso_startup;
    $tests[-1]{shutdown} = \&notso_shutdown;
}
if ($modify && $modify eq 'pfsync') {
    $tests[0]{startup} = \&pfsync_startup;
    $tests[-1]{shutdown} = \&pfsync_shutdown;
}
push @tests, (
    {
	testcmd => ['time', '-lp', 'make',
	    "-C/usr/src/sys/arch/$machine/compile/$kconf", "-j$ncpu", '-s'],
	parser => \&time_parser,
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

    # reap zombies, might happen it there were some btrace errors
    1 while waitpid(-1, WNOHANG) > 0;

    my $sampletime;
    if ($btrace) {
	# run the test for 80 seconds to measure btrace during 1 minute
	if (grep { /^-t10$/ } @runcmd) {
	    s/^-t10$/-t80/ foreach @runcmd;
	    $sampletime = 60;
	} elsif (grep { /^make$/ } @runcmd) {
	    # kernel build usually takes longer than 5 minutes
	    $sampletime = 300;
	} else {
	    next;
	}
    } elsif ($stress) {
	if (grep { /^-t10$/ } @runcmd) {
	    s/^-t10$/-t60/ foreach @runcmd;
	}
    }

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

    # XXX temporarily disabled
    #statistics($test, "before");

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

    my $btpid;
    if ($btrace) {
	my @btcmd = ('btrace', '-e', "profile:hz:100{\@[$btrace]=count()}");
	my $btfile = "$test-$btrace.btrace";
	open(my $bt, '>', $btfile)
	    or bad $test, 'NOLOG',
	    "Open btrace '$btfile' for writing failed: $!";
	$SIG{USR1} = 'IGNORE';
	defined($btpid = fork())
	    or bad $test, 'XPASS', "Fork btrace failed: $!", $log;
	if ($btpid == 0) {
	    # child process

	    # allow test to spin up
	    sleep 10;

	    defined(my $btracepid = fork())
		or warn "Fork btrace '@btcmd' failed: $!";
	    if ($btracepid == 0) {
		# child process
		open(STDOUT, '>&', $bt)
		    or warn "Redirect stdout to btrace failed: $!";
		exec(@btcmd);
		warn "Exec '@btcmd' failed: $!";
		_exit(126);
	    }
	    my $tracetime = Time::HiRes::time();
	    print $log "Btrace '@btcmd' started for $sampletime seconds\n";
	    print "Btrace '@btcmd' started for $sampletime seconds\n"
		if $opts{v};

	    # gather samples during 1 minute or 5 minutes
	    $SIG{USR1} = sub { print "Btrace aborted\n" if $opts{v} };
	    sleep $sampletime;
	    $SIG{USR1} = 'IGNORE';
	    kill 'INT', $btracepid
		or warn "Interrupt btrace failed: $!";

	    $tracetime = sprintf("%d", Time::HiRes::time() - $tracetime);
	    print $log "Btrace '@btcmd' stopped after $tracetime seconds\n";
	    print "Btrace '@btcmd' stopped after $tracetime seconds\n"
		if $opts{v};
	    undef $!;
	    waitpid($btracepid, 0) == $btracepid && $? == 0
		and _exit(0);
	    warn $! ?
		"Wait for btrace '@btcmd' failed: $!" :
		"Btrace '@btcmd' failed: $?";
	    _exit(126);
	}
	close($bt);
    }

    eval {
	local $SIG{ALRM} = sub { die "Test running too long, aborted.\n" };
	alarm($timeout);
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

    if ($btpid) {
	kill 'USR1', $btpid
	    or bad $test, 'XPASS', "Kill btrace failed: $!", $log;
	print "Btrace killed\n" if $opts{v};
	waitpid($btpid, 0) == $btpid
	    or bad $test, 'XPASS', "Wait for btrace failed: $!", $log;
	$? == 0
	    or bad $test, 'XFAIL', "Btrace failed: $?", $log;
    }

    close($out)
	or bad $test, 'NOEXIT', $! ?
	"Close pipe from '@runcmd' failed: $!" :
	"Command '@runcmd' failed: $?", $log;

    # XXX temporarily disabled
    #statistics($test, "after");

    eval { $t->{shutdown}($log) if $t->{shutdown}; };
    if ($@) {
	bad $test, 'NOCLEAN', "Could not shutdown", $log;
    }

    my $end = Time::HiRes::time();
    good $test, $end - $begin, $log;

    close($log)
	or die "Close log '$logfile' after writing failed: $!";
}

chdir($performdir)
    or die "Change directory to '$performdir' failed: $!";

# kill remote commands or ssh will hang forever
if ($testmode{tcpbench4} || $testmode{tcpbench6}) {
    my @sshcmd = ('ssh', $remote_ssh, 'pkill', 'tcpbench');
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

if ($stress) {
    chdir($startdir)
	or die "Change directory to '$startdir' failed: $!";
    exec $! @startcmd;
    die "Exec '@startcmd' failed: $!";
}

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
