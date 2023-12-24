#!/usr/bin/perl

# Copyright (c) 2022 Moritz Buhl <mbuhl@genua.de>
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

use lib dirname($0);
use Netstat;

my @allifaces = qw(em igc ix ixl bnxt);
my @allmodifymodes = qw(nolro nopf notso);
my @allpseudos = qw(bridge none veb vlan);
my @alltestmodes = sort qw(all fragment icmp tcp udp splice);

my %opts;
getopts('c:e:i:m:t:v', \%opts) or do {
    print STDERR <<"EOF";
usage: netlink.pl [-v] [-c pseudo] [-e environment] [-i iface] [-m modify]
    [-t timeout] [test ...]
    -c pseudo	pseudo network device: @allpseudos
    -e environ	parse environment for tests from shell script
    -i iface	interface, may contain number: @allifaces
    -m modify	modify mode: @allmodifymodes
    -t timeout	timeout for a single test, default 60 seconds
    -v		verbose
    test ...	test mode: @alltestmodes
		appending 4 or 6 to a test restricts the IP version.
EOF
    exit(2);
};
my $timeout = $opts{t} || 20;
environment($opts{e}) if $opts{e};
my $pseudo = $opts{c} || "none";
my $iface = $opts{i} || "em";
my $modify = $opts{m};

my $line = $ENV{NETLINK_LINE}
    or die "NETLINK_LINE is not in env";
my $management_if = $ENV{MANAGEMENT_IF}
    or die "MANAGEMENT_IF is not in env";

my ($iftype, $ifnum) = $iface =~ /^([a-z]+)([0-9]+)?$/;
grep { $_ eq $iftype } @allifaces
    or die "Unknown interface '$iface'";
my ($left_ifidx, $right_ifidx);
if (defined($ifnum)) {
    $left_ifidx = $ifnum + 0;
    $right_ifidx = $ifnum + 1;
} else {
    $left_ifidx = 0;
    $right_ifidx = 1;
}
if (($iftype.$left_ifidx) eq $management_if ||
    ($iftype.$right_ifidx) eq $management_if) {
    if (defined($ifnum)) {
	die "Cannot use inferface '$iface', conflicts management";
    } else {
	$left_ifidx = 2;
	$right_ifidx = 3;
    }
}

warn "left interface should be in the wrong network" if ($left_ifidx % 2);
warn "right interface should be in the wrong network" if (!$right_ifidx % 2);

!$modify || grep { $_ eq $modify } @allmodifymodes
    or die "Unknnown modify mode '$modify'";
grep { $_ eq $pseudo } @allpseudos
    or die "Unknown pseudo network device '$pseudo'";

@alltestmodes = map { ($_, "${_}4", "${_}6") } @alltestmodes;
my %testmode;
foreach my $mode (@ARGV) {
    grep { $_ eq $mode } @alltestmodes
	or die "Unknown test mode '$mode'";
    $testmode{$mode} = 1;
}
$testmode{all4} = $testmode{all6} = 1 if ($testmode{all});
if ($testmode{all4}) {
    $testmode{$_} = 1 foreach map { "${_}4" } @alltestmodes;
}
if ($testmode{all6}) {
    $testmode{$_} = 1 foreach map { "${_}6" } @alltestmodes;
}
foreach (keys %testmode) {
    $testmode{"${_}4"} = $testmode{"${_}6"} = 1 if $_ !~ /[46]$/;
}

my $ip4prefix = '10.10';
my $ip6prefix = 'fdd7:e83e:66bd:10';

my $obsd_l_if = $iftype . $left_ifidx;
my $obsd_l_net = "$ip4prefix.${line}1.0/24";
my $obsd_l_addr = "$ip4prefix.${line}1.2";
my $obsd_l_net6 = "${ip6prefix}${line}1::/64";
my $obsd_l_addr6 = "${ip6prefix}${line}1::2";

my @obsd_l_addr_range = map { "$ip4prefix.${line}1.2$_" } 0..9;
my @obsd_l_addr6_range = map { "${ip6prefix}${line}1::2$_" } 0..9;

my $obsd_r_if = $iftype . $right_ifidx;
my $obsd_r_net = "$ip4prefix.${line}2.0/24";
my $obsd_r_addr = "$ip4prefix.${line}2.3";
my $obsd_r_net6 = "${ip6prefix}${line}2::/64";
my $obsd_r_addr6 = "${ip6prefix}${line}2::3";

my $lnx_l_if = "ens2f0";
my $lnx_l_pdev = "$lnx_l_if.0";
my $lnx_l_addr = "$ip4prefix.${line}1.1";
my $lnx_l_addr6 = "${ip6prefix}${line}1::1";
my $lnx_l_net = "$lnx_l_addr/24";
my $lnx_l_net6 = "$lnx_l_addr6/64";
my $lnx_l_ssh = 'root@lt40'; #$ENV{LINUXL_SSH}; # XXX

my $lnx_r_if = "ens2f0";
my $lnx_r_pdev = "$lnx_r_if.0";
my $lnx_r_addr = "$ip4prefix.${line}2.4";
my $lnx_r_addr6 = "${ip6prefix}${line}2::4";
my $lnx_r_net = "$lnx_r_addr/24";
my $lnx_r_net6 = "$lnx_r_addr6/64";
my $lnx_r_ssh = 'root@lt43'; #$ENV{LINUXR_SSH};

my @lnx_r_addr_range = map { "$ip4prefix.${line}2.4$_" } 0..9;
my @lnx_r_net_range = map { "$_/24" } @lnx_r_addr_range;
my @lnx_r_addr6_range = map { "$ip6prefix${line}2::4$_" } 0..9;
my @lnx_r_net6_range = map { "$_/64" } @lnx_r_addr6_range;

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

    statistics($test, "after");
    generate_diff_netstat_s($test);

    $log->sync() if $log;
    $tr->sync();
    no warnings 'exiting';
    next TEST;
}

sub good {
    my ($test, $diff, $log) = @_;
    my $duration = sprintf("%dm%02d.%02ds", $diff/60, $diff%60, 100*$diff%100);

    statistics($test, "after");
    generate_diff_netstat_s($test);

    my $pass = "PASS";
    my $netstat = "$test.stats-diff-netstat_-s.log";

    open(my $fh, '<', $netstat) or die("Could not open '$netstat'");
    while(<$fh>) {
	$pass = "XPASS" if /error/;
    }

    print $log "\n$pass\t$test\tDuration $duration\n" if $log;
    print "\n$pass\t$test\tDuration $duration\n\n" if $opts{v};
    print $tr "$pass\t$test\tDuration $duration\n";

    $log->sync() if $log;
    $tr->sync();
}

# unconfigure all interfaces used in testing
my @allinterfaces = map { m{^([a-z]+\d+):} } `ifconfig`;

foreach my $ifn (@allinterfaces) {
    unless ($ifn =~ m{^(lo|enc|pflog|${management_if})}) {
	printcmd('ifconfig', $ifn, '-inet', '-inet6', 'down');
    }
    my $pdevre = join '|', @allpseudos;
    printcmd('ifconfig', $ifn, 'destroy') if ($ifn =~ m{^($pdevre)});
}

# unconfigure linux interfaces
printcmd('ssh', $lnx_l_ssh, 'ip', 'addr', 'del', $lnx_l_net, 'dev',
    $lnx_l_pdev);
printcmd('ssh', $lnx_l_ssh, 'ip', 'addr', 'del', $lnx_l_net6, 'dev',
    $lnx_l_pdev);
printcmd('ssh', $lnx_l_ssh, 'ip', 'addr', 'del', $lnx_l_net, 'dev',
    $lnx_l_if);
printcmd('ssh', $lnx_l_ssh, 'ip', 'addr', 'del', $lnx_l_net6, 'dev',
    $lnx_l_if);

printcmd('ssh', $lnx_r_ssh, 'ip', 'addr', 'del', $lnx_r_net, 'dev',
    $lnx_r_pdev);
printcmd('ssh', $lnx_r_ssh, 'ip', 'addr', 'del', $lnx_r_net6, 'dev',
    $lnx_r_pdev);
printcmd('ssh', $lnx_r_ssh, 'ip', 'addr', 'del', $lnx_r_net, 'dev',
    $lnx_r_if);
printcmd('ssh', $lnx_r_ssh, 'ip', 'addr', 'del', $lnx_r_net6, 'dev',
    $lnx_r_if);

foreach my $net (@lnx_r_net_range) {
    printcmd('ssh', $lnx_r_ssh, 'ip', 'addr', 'del', $net, 'dev', $lnx_r_pdev);
    printcmd('ssh', $lnx_r_ssh, 'ip', 'addr', 'del', $net, 'dev', $lnx_r_if);
}

foreach my $net (@lnx_r_net6_range) {
    printcmd('ssh', $lnx_r_ssh, 'ip', 'addr', 'del', $net, 'dev', $lnx_r_pdev);
    printcmd('ssh', $lnx_r_ssh, 'ip', 'addr', 'del', $net, 'dev', $lnx_r_if);
}

printcmd('ssh', $lnx_l_ssh, 'ip', 'route', 'del', $obsd_r_net);
printcmd('ssh', $lnx_r_ssh, 'ip', 'route', 'del', $obsd_l_net);
printcmd('ssh', $lnx_l_ssh, 'ip', '-6', 'route', 'del', $obsd_r_net6);
printcmd('ssh', $lnx_r_ssh, 'ip', '-6', 'route', 'del', $obsd_l_net6);

printcmd('arp', '-da');
printcmd('ndp', '-c');

printcmd('ssh', $lnx_l_ssh, 'ip', 'neigh', 'flush', 'all', 'dev',
    $lnx_l_if);
printcmd('ssh', $lnx_l_ssh, 'ip', 'neigh', 'flush', 'all', 'dev',
    $lnx_l_pdev);
printcmd('ssh', $lnx_l_ssh, 'ip', '-6', 'neigh', 'flush', 'all', 'dev',
    $lnx_l_if);
printcmd('ssh', $lnx_l_ssh, 'ip', '-6', 'neigh', 'flush', 'all', 'dev',
    $lnx_l_pdev);

printcmd('ssh', $lnx_r_ssh, 'ip', 'neigh', 'flush', 'all', 'dev',
    $lnx_r_if);
printcmd('ssh', $lnx_r_ssh, 'ip', 'neigh', 'flush', 'all', 'dev',
    $lnx_r_pdev);
printcmd('ssh', $lnx_r_ssh, 'ip', '-6', 'neigh', 'flush', 'all', 'dev',
    $lnx_r_if);
printcmd('ssh', $lnx_r_ssh, 'ip', '-6', 'neigh', 'flush', 'all', 'dev',
    $lnx_r_pdev);

# configure given interface type
if ($pseudo eq 'bridge' || $pseudo eq 'none') {
    printcmd('ifconfig', $obsd_l_if, 'inet', "${obsd_l_addr}/24")
	and do { warn "command failed: $?"; exit 0; };
    foreach my $addr (@obsd_l_addr_range) {
	printcmd('ifconfig', $obsd_l_if, 'inet', "${addr}/32", 'alias')
	    and do { warn "command failed: $?"; exit 0; };
    }
    printcmd('ifconfig', $obsd_r_if, 'inet', "${obsd_r_addr}/24")
	and do { warn "command failed: $?"; exit 0; };

    printcmd('ifconfig', $obsd_l_if, 'inet6', "${obsd_l_addr6}/64")
	and do { warn "command failed: $?"; exit 0; };
    foreach my $addr (@obsd_l_addr6_range) {
	printcmd('ifconfig', $obsd_l_if, 'inet6', "${addr}/128", 'alias')
	    and do { warn "command failed: $?"; exit 0; };
    }
    printcmd('ifconfig', $obsd_r_if, 'inet6', "${obsd_r_addr6}/64")
	and do { warn "command failed: $?"; exit 0; };
}

printcmd('ifconfig', $obsd_l_if, 'up');
printcmd('ifconfig', $obsd_r_if, 'up');

printcmd('sysctl net.inet.ip.forwarding=1');
printcmd('sysctl net.inet6.ip6.forwarding=1');

# allow tcpbench to bind on ipv6 addresses without explicitly providing it
printcmd('ssh', $lnx_l_ssh, 'sysctl','net.ipv6.bindv6only=1');
printcmd('ssh', $lnx_r_ssh, 'sysctl','net.ipv6.bindv6only=1');

# allow fragment reassembly to use up to 1GiB of memory
printcmd('ssh', $lnx_l_ssh, 'sysctl', 'net.ipv6.ip6frag_high_thresh=1073741824')
    if ($testmode{fragment6});
printcmd('ssh', $lnx_r_ssh, 'sysctl', 'net.ipv6.ip6frag_high_thresh=1073741824')
    if ($testmode{fragment6});
printcmd('ssh', $lnx_l_ssh, 'sysctl', 'net.ipv4.ipfrag_high_thresh=1073741824')
    if ($testmode{fragment4});
printcmd('ssh', $lnx_r_ssh, 'sysctl', 'net.ipv4.ipfrag_high_thresh=1073741824')
    if ($testmode{fragment4});

# install tcpbench service
defined(my $pid = open(my $lnx_tcpbench_service, '|-'))
    or die "fork failed";
if ($pid == 0) {
    my @sshcmd = ('ssh', $lnx_r_ssh, 'cat', '-', '>',
	'/etc/systemd/system/tcpbench.service');
    print "@sshcmd\n";
    exec(@sshcmd);
    warn "Exec '@sshcmd' failed: $!";
    _exit(126);
}
print $lnx_tcpbench_service <<'EOF';
[Unit]
Description=OpenBSD tcpbench server
After=network.target auditd.service

[Service]
ExecStart=/usr/bin/tcpbench -s
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
RestartPreventExitStatus=255
Type=simple

[Install]
WantedBy=multi-user.target
Alias=tcpbench.service
EOF

close($lnx_tcpbench_service)
    or die ($! ?
    "Close pipe failed: $!" :
    "Command failed: $?");

open(my $tcpbench_rc, '>', '/etc/rc.d/tcpbench')
    or die 'Could not open /etc/rc.d/tcpbench';

print $tcpbench_rc <<'EOF';
#!/bin/ksh

daemon="/usr/bin/tcpbench"
daemon_flags="-s"
daemon_user=user

. /etc/rc.d/rc.subr

rc_reload=NO
rc_bg=YES

rc_start() {
	rc_exec "${daemon} ${daemon_flags}" &
}

rc_cmd $1
EOF
close($tcpbench_rc);

printcmd('chmod', '555', '/etc/rc.d/tcpbench');

my $configure_linux = 1;

if ($pseudo eq 'aggr') {
    # XXX: does now work as switch is not configured
    # XXX: multiple interfaces in one aggr
    printcmd('ifconfig', 'aggr0', 'create');
    printcmd('ifconfig', 'aggr1', 'create');

    printcmd('ifconfig', $obsd_l_if, 'up');
    printcmd('ifconfig', $obsd_r_if, 'up');
    printcmd('ifconfig', 'aggr0', 'trunkport', $obsd_l_if);
    printcmd('ifconfig', 'aggr1', 'trunkport', $obsd_r_if);

    printcmd('ifconfig', 'aggr0', 'inet', "${obsd_l_addr}/24");
    foreach my $addr (@obsd_l_addr_range) {
	printcmd('ifconfig', 'aggr0', 'inet', "${addr}/32", 'alias');
    }
    printcmd('ifconfig', 'aggr1', 'inet', "${obsd_r_addr}/24");

    printcmd('ifconfig', 'aggr0', 'inet6', "${obsd_l_addr6}/64");
    foreach my $addr (@obsd_l_addr6_range) {
	printcmd('ifconfig', 'aggr0', 'inet6', "${addr}/128", 'alias');
    }
    printcmd('ifconfig', 'aggr1', 'inet6', "${obsd_r_addr6}/64");

    printcmd('ifconfig', 'aggr0', 'up');
    printcmd('ifconfig', 'aggr1', 'up');
} elsif ($pseudo eq 'bridge') {
    # XXX: vether
    printcmd('ifconfig', 'bridge0', 'create');
    printcmd('ifconfig', 'bridge0', 'add', $obsd_l_if);
    printcmd('ifconfig', 'bridge0', 'add', $obsd_r_if);
    printcmd('ifconfig', 'bridge0', 'up');
} elsif ($pseudo eq 'carp') {
    # XXX
} elsif ($pseudo eq 'trunk') {
    # XXX
} elsif ($pseudo eq 'veb') {
    printcmd('ifconfig', 'veb0', 'create');
    printcmd('ifconfig', 'vport0', 'create');
    printcmd('ifconfig', 'vport1', 'create');

    printcmd('ifconfig', 'vport0', 'inet', "${obsd_l_addr}/24");
    foreach my $addr (@obsd_l_addr_range) {
	printcmd('ifconfig', 'vport0', 'inet', "${addr}/32", 'alias');
    }
    printcmd('ifconfig', 'vport1', 'inet', "${obsd_r_addr}/24");

    printcmd('ifconfig', 'vport0', 'inet6', "${obsd_l_addr6}/64");
    foreach my $addr (@obsd_l_addr6_range) {
	printcmd('ifconfig', 'vport0', 'inet6', "${addr}/128", 'alias');
    }
    printcmd('ifconfig', 'vport1', 'inet6', "${obsd_r_addr6}/64");

    printcmd('ifconfig', 'vport0', 'up');
    printcmd('ifconfig', 'vport1', 'up');
    printcmd('ifconfig', $obsd_l_if, 'up');
    printcmd('ifconfig', $obsd_r_if, 'up');
    printcmd('ifconfig', 'veb0', 'add', $obsd_l_if);
    printcmd('ifconfig', 'veb0', 'add', $obsd_r_if);
    printcmd('ifconfig', 'veb0', 'add', 'vport0');
    printcmd('ifconfig', 'veb0', 'add', 'vport1');
    printcmd('ifconfig', 'veb0', 'up');
} elsif ($pseudo eq 'vlan') {
    $configure_linux = 0; # all necessary config is below
    my $vlanl = 252;
    my $vlanr = 253;

    printcmd('ssh', $lnx_l_ssh, 'modprobe', '8021q');
    printcmd('ssh', $lnx_r_ssh, 'modprobe', '8021q');

    printcmd('ssh', $lnx_l_ssh, 'ip', 'link', 'add', 'link', $lnx_l_if,
	'name', $lnx_l_pdev, 'type', 'vlan', 'id', $vlanl);
    printcmd('ssh', $lnx_r_ssh, 'ip', 'link', 'add', 'link', $lnx_r_if,
	'name', $lnx_r_pdev, 'type', 'vlan', 'id', $vlanr);

    printcmd('ssh', $lnx_l_ssh, 'ip', 'link', 'set', 'dev', $lnx_l_if, 'up');
    printcmd('ssh', $lnx_r_ssh, 'ip', 'link', 'set', 'dev', $lnx_r_if, 'up');

    printcmd('ssh', $lnx_l_ssh, 'ip', 'link', 'set', 'dev', $lnx_l_pdev, 'up');
    printcmd('ssh', $lnx_r_ssh, 'ip', 'link', 'set', 'dev', $lnx_r_pdev, 'up');

    printcmd('ifconfig', 'vlan0', 'create');
    printcmd('ifconfig', 'vlan1', 'create');
    printcmd('ifconfig', 'vlan0', 'parent', $obsd_l_if, 'vnetid', $vlanl);
    printcmd('ifconfig', 'vlan1', 'parent', $obsd_r_if, 'vnetid', $vlanr);

    printcmd('ifconfig', 'vlan0', 'inet', "${obsd_l_addr}/24", 'up');
    foreach my $addr (@obsd_l_addr_range) {
	printcmd('ifconfig', 'vlan0', 'inet', "${addr}/32", 'alias');
    }
    printcmd('ifconfig', 'vlan1', 'inet', "${obsd_r_addr}/24", 'up');

    printcmd('ssh', $lnx_l_ssh, 'ip', 'addr', 'add', $lnx_l_net, 'dev',
	$lnx_l_pdev);
    printcmd('ssh', $lnx_l_ssh, 'ip', 'route', 'add', $obsd_r_net, 'via',
	$obsd_l_addr, 'dev', "$lnx_l_pdev");

    printcmd('ssh', $lnx_r_ssh, 'ip', 'addr', 'add', $lnx_r_net, 'dev',
	$lnx_r_pdev);
    printcmd('ssh', $lnx_r_ssh, 'ip', 'route', 'add', $obsd_l_net, 'via',
	$obsd_r_addr, 'dev', "$lnx_r_pdev");

    printcmd('ifconfig', 'vlan0', 'inet6', "${obsd_l_addr6}/64", 'up');
    foreach my $addr (@obsd_l_addr6_range) {
	printcmd('ifconfig', 'vlan0', 'inet6', "${addr}/128", 'alias');
    }
    printcmd('ifconfig', 'vlan1', 'inet6', "${obsd_r_addr6}/64", 'up');

    printcmd('ssh', $lnx_l_ssh, 'ip', 'addr', 'add', $lnx_l_net6, 'dev',
	$lnx_l_pdev);
    printcmd('ssh', $lnx_l_ssh, 'ip', '-6', 'route', 'add', $obsd_r_net6, 'via',
	$obsd_l_addr6, 'dev', "$lnx_l_pdev");

    printcmd('ssh', $lnx_r_ssh, 'ip', 'addr', 'add', $lnx_r_net6, 'dev',
	$lnx_r_pdev);
    printcmd('ssh', $lnx_r_ssh, 'ip', '-6', 'route', 'add', $obsd_l_net6, 'via',
	$obsd_r_addr6, 'dev', "$lnx_r_pdev");
}
# XXX: tpmr, nipsec, gre?

if ($configure_linux) {
    my @sshcmd = ('ssh', $lnx_l_ssh);
    printcmd(@sshcmd, 'ip', 'addr', 'add', $lnx_l_net, 'dev', $lnx_l_if);
    printcmd(@sshcmd, 'ip', 'link', 'set', 'dev', $lnx_l_if, 'up');
    printcmd(@sshcmd, 'ip', 'route', 'add', $obsd_r_net, 'via',
	$obsd_l_addr, 'dev', "$lnx_l_if");

    printcmd(@sshcmd, 'ip', 'addr', 'add', $lnx_l_net6, 'dev', $lnx_l_if);
    printcmd(@sshcmd, 'ip', '-6', 'route', 'add', $obsd_r_net6, 'via',
	$obsd_l_addr6, 'dev', "$lnx_l_if");

    @sshcmd = ('ssh', $lnx_r_ssh);
    printcmd(@sshcmd, 'ip', 'addr', 'add', $lnx_r_net, 'dev', $lnx_r_if);
    foreach my $net (@lnx_r_net_range) {
	printcmd(@sshcmd, 'ip', 'addr', 'add', $net, 'dev', $lnx_r_if);
    }
    printcmd(@sshcmd, 'ip', 'link', 'set', 'dev', $lnx_r_if, 'up');
    printcmd(@sshcmd, 'ip', 'route', 'add', $obsd_l_net, 'via',
	$obsd_r_addr, 'dev', "$lnx_r_if");

    printcmd(@sshcmd, 'ip', 'addr', 'add', $lnx_r_net6, 'dev', $lnx_r_if);
    foreach my $net (@lnx_r_net6_range) {
	printcmd(@sshcmd, 'ip', 'addr', 'add', $net, 'dev', $lnx_r_if);
    }
    printcmd(@sshcmd, 'ip', '-6', 'route', 'add', $obsd_l_net6, 'via',
	$obsd_r_addr6, 'dev', "$lnx_r_if");
}

# wait for linux
sleep(3);

my $netbench = "$netlinkdir/netbench.pl";

# tcpbench tests

sub tcpbench_server_startup {
    # requires echo 1 > /proc/sys/net/ipv6/bindv6only
    my @sshcmd = ('ssh', '-f', $lnx_r_ssh, 'service', 'tcpbench', 'start');
    printcmd(@sshcmd)
	and die "Start linux tcpbench server with '@sshcmd' failed: $?";

    my @cmd = ('rcctl', '-f', 'start', 'tcpbench');
    printcmd(@cmd)
	and die "Start local tcpbench server with '@cmd' failed: $?";
}

sub tcpbench_server_shutdown {
    # requires echo 1 > /proc/sys/net/ipv6/bindv6only
    my @sshcmd = ('ssh', '-f', $lnx_r_ssh, 'service', 'tcpbench', 'stop');
    printcmd(@sshcmd)
	and die "Stop linux tcpbench server with '@sshcmd' failed: $?";

    my @cmd = ('rcctl', '-f', 'stop', 'tcpbench');
    printcmd(@cmd)
	and die "Stop local tcpbench server with '@cmd' failed: $?";
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

sub netbench_parser {
    my ($line, $log) = @_;
    if ($line =~ m{^(send|recv)all:.* bit/s ([\d.e+]+)$}) {
	my $direction = $1;
	my $value = 0 + $2;
	print $tr "VALUE $value bits/sec $direction\n";
    }
    return 1;
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

sub lro_get_ifs {
    my @cmd = ('/sbin/ifconfig', '-a', 'hwfeatures');
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

my @lro_ifs;
sub nolro_startup {
    my ($log) = @_;

    @lro_ifs = lro_get_ifs();
    foreach my $ifname (@lro_ifs) {
	my @cmd = ('/sbin/ifconfig', $ifname, '-tcplro');
	logcmd($log, @cmd) and
	    die "Command '@cmd' failed: $?";
    }

    # changing LRO may lose interface link status due to down/up
    sleep 1;
    print $log "lro disabled\n\n";
    print "lro disabled\n\n" if $opts{v};
}

sub nolro_shutdown {
    my ($log) = @_;
    print $log "\nenabling lro\n";
    print "\nenabling lro\n" if $opts{v};

    foreach my $ifname (@lro_ifs) {
	my @cmd = ('/sbin/ifconfig', $ifname, 'tcplro');
	logcmd($log, @cmd) and
	    die "Command '@cmd' failed: $?";
    }
}

sub nopf_startup {
    my ($log) = @_;
    my @cmd = ('/sbin/pfctl', '-d');
    logcmd($log, @cmd) and
	die "Command '@cmd' failed: $?";

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
}

sub notso_startup {
    my ($log) = @_;
    my @cmd = ('/sbin/sysctl', 'net.inet.tcp.tso=0');
    logcmd($log, @cmd) and
	die "Command '@cmd' failed: $?";

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
}

my @tests;
push @tests, (
    {
	testcmd => ['ssh', $lnx_l_ssh, 'ping', '-qfc10000', $obsd_l_addr],
	parser => \&ping_f_parser,
    }, {
	testcmd => ['ping', '-qfc10000', $lnx_r_addr],
	parser => \&ping_f_parser,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'ping', '-qfc10000', $lnx_r_addr],
	parser => \&ping_f_parser,
    }
) if ($testmode{icmp4});
push @tests, (
    {
	testcmd => ['ssh', $lnx_l_ssh, 'ping6', '-qfc10000', $obsd_l_addr6],
	parser => \&ping_f_parser,
    }, {
	testcmd => ['ping6', '-qfc10000', $lnx_r_addr6],
	parser => \&ping_f_parser,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'ping6', '-qfc10000', $lnx_r_addr6],
	parser => \&ping_f_parser,
    }
) if ($testmode{icmp6});
push @tests, {
    testcmd => \&tcpbench_server_startup,
} if ($testmode{tcp4} || $testmode{tcp6});
push @tests, (
    {
	testcmd => ['ssh', $lnx_l_ssh, 'tcpbench', '-S1000000', '-t10',
	    $obsd_l_addr],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'tcpbench', '-S1000000', '-t10', '-n100',
	    $obsd_l_addr],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['tcpbench', '-S1000000', '-t10', $lnx_r_addr],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['tcpbench', '-S1000000', '-t10', '-n100', $lnx_r_addr],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'tcpbench', '-S1000000', '-t10',
	    $lnx_r_addr],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'tcpbench', '-S1000000', '-t10',
	    '-n100', $lnx_r_addr],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }
) if ($testmode{tcp4});
push @tests, (
    {
	testcmd => ['ssh', $lnx_l_ssh, 'tcpbench', '-S1000000', '-t10',
	    $obsd_l_addr6],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'tcpbench', '-S1000000', '-t10',
	    '-n100', $obsd_l_addr6],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['tcpbench', '-S1000000', '-t10', $lnx_r_addr6],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['tcpbench', '-S1000000', '-t10', '-n100', $lnx_r_addr6],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'tcpbench', '-S1000000', '-t10',
	    $lnx_r_addr6],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'tcpbench', '-S1000000', '-t10',
	    '-n100', $lnx_r_addr6],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }
) if ($testmode{tcp6});
push @tests, (
    {
	testcmd => ['udpbench', '-l36', '-t10', '-r', $lnx_l_ssh,
	    'recv', $obsd_l_addr],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['udpbench', '-l1472', '-t10', '-r', $lnx_l_ssh,
	    'recv', $obsd_l_addr],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['udpbench', '-l36', '-t10', '-r', $lnx_r_ssh,
	    'send', $lnx_r_addr],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['udpbench', '-l1472', '-t10', '-r', $lnx_r_ssh,
	    'send', $lnx_r_addr],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'udpbench', '-l36', '-t10',
	    '-r', $lnx_r_ssh, 'send', $lnx_r_addr],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'udpbench', '-l1472', '-t10',
	    '-r', $lnx_r_ssh, 'send', $lnx_r_addr],
	parser => \&udpbench_parser,
    }
) if ($testmode{udp4});
push @tests, (
    {
	testcmd => ['udpbench', '-l36', '-t10', '-r', $lnx_l_ssh,
	    'recv', $obsd_l_addr6],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['udpbench', '-l1452', '-t10', '-r', $lnx_l_ssh,
	    'recv', $obsd_l_addr6],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['udpbench', '-l36', '-t10', '-r', $lnx_r_ssh,
	    'send', $lnx_r_addr6],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['udpbench', '-l1452', '-t10', '-r', $lnx_r_ssh,
	    'send', $lnx_r_addr6],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'udpbench', '-l36', '-t10',
	    '-r', $lnx_r_ssh, 'send', $lnx_r_addr6],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'udpbench', '-l1452', '-t10',
	    '-r', $lnx_r_ssh, 'send', $lnx_r_addr6],
	parser => \&udpbench_parser,
    }
) if ($testmode{udp6});
push @tests, (
    {
	testcmd => ['udpbench', '-l1473', '-t10', '-r', $lnx_l_ssh,
	    'recv', $obsd_l_addr],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['udpbench', '-l1473', '-t10', '-r', $lnx_r_ssh,
	    'send', $lnx_r_addr],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'udpbench', '-l1473', '-t10',
	    '-r', $lnx_r_ssh, 'send', $lnx_r_addr],
	parser => \&udpbench_parser,
    }
) if ($testmode{fragment4});
push @tests, (
    {
	testcmd => ['udpbench', '-l1453', '-t10', '-r', $lnx_l_ssh,
	    'recv', $obsd_l_addr6],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['udpbench', '-l1453', '-t10', '-r', $lnx_r_ssh,
	    'send', $lnx_r_addr6],
	parser => \&udpbench_parser,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'udpbench', '-l1453', '-t10',
	    '-r', $lnx_r_ssh, 'send', $lnx_r_addr6],
	parser => \&udpbench_parser,
    }
) if ($testmode{fragment6});
push @tests, {
    testcmd => \&tcpbench_server_shutdown,
} if ($testmode{tcp4} || $testmode{tcp6} ||
    $testmode{splice4} || $testmode{splice6});
foreach my $mode (qw(tcpsplice tcpcopy)) {
    push @tests, (
	{
	    testcmd => [$netbench,
		'-v',
		'-b1000000',
		"-c$lnx_l_ssh",
		"-s$lnx_r_ssh",
		"-A$obsd_l_addr_range[0]",
		"-a$lnx_r_addr_range[0]",
		'-t10',
		$mode],
	    parser => \&netbench_parser,
	}, {
	    testcmd => [$netbench,
		'-v',
		'-b1000000',
		'-N10',
		"-c$lnx_l_ssh",
		"-s$lnx_r_ssh",
		"-A$obsd_l_addr_range[0]",
		"-a$lnx_r_addr_range[0]",
		'-t10',
		$mode],
	    parser => \&netbench_parser,
	}
    ) if $testmode{splice4};
    push @tests, (
	{
	    testcmd => [$netbench,
		'-v',
		'-b1000000',
		"-c$lnx_l_ssh",
		"-s$lnx_r_ssh",
		"-A$obsd_l_addr6_range[0]",
		"-a$lnx_r_addr6_range[0]",
		'-t10',
		$mode],
	    parser => \&netbench_parser,
	}, {
	    testcmd => [$netbench,
		'-v',
		'-b1000000',
		'-N10',
		"-c$lnx_l_ssh",
		"-s$lnx_r_ssh",
		"-A$obsd_l_addr6_range[0]",
		"-a$lnx_r_addr6_range[0]",
		'-t10',
		$mode],
	    parser => \&netbench_parser,
	}
    ) if $testmode{splice6};
}
foreach my $frame (0, 1) {
    push @tests, {
	testcmd => [$netbench,
	    '-v',
	    '-B1000000000',
	    '-b1000000',
	    '-d1',
	    "-f$frame",
	    '-i3',
	    '-N10',
	    "-c$lnx_l_ssh",
	    "-s$lnx_r_ssh",
	    "-A$obsd_l_addr_range[0]",
	    "-a$lnx_r_addr_range[0]",
	    '-t10',
	    'udpsplice'],
	parser => \&netbench_parser,
    } if $testmode{splice4};
    push @tests, {
	testcmd => [$netbench,
	    '-v',
	    '-B1000000000',
	    '-b1000000',
	    '-d1',
	    "-f$frame",
	    '-i3',
	    '-N10',
	    "-c$lnx_l_ssh",
	    "-s$lnx_r_ssh",
	    "-A$obsd_l_addr6_range[0]",
	    "-a$lnx_r_addr6_range[0]",
	    '-t10',
	    'udpsplice'],
	parser => \&netbench_parser,
    } if $testmode{splice6};
}

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
	statcmd => [ 'netstat', '-nr' ],
    }, {
	statcmd => [ 'ssh', 'root@lt40', 'netstat', '-nr' ],
    }, {
	statcmd => [ 'ssh', 'root@lt40', 'netstat', '-6nr' ],
    }, {
	statcmd => [ 'ssh', 'root@lt43', 'netstat', '-nr' ],
    }, {
	statcmd => [ 'ssh', 'root@lt43', 'netstat', '-6nr' ],
    }, {
	statcmd => [ 'vmstat', '-mv' ],
    }, {
	statcmd => [ 'vmstat', '-s' ],
    }, {
	statcmd => [ 'vmstat', '-iz' ],
    },
);

if ($modify && $modify eq 'nolro') {
    $tests[0]{startup} = \&nolro_startup;
    $tests[-1]{shutdown} = \&nolro_shutdown;
}
if ($modify && $modify eq 'nopf') {
    $tests[0]{startup} = \&nopf_startup;
    $tests[-1]{shutdown} = \&nopf_shutdown;
}
if ($modify && $modify eq 'notso') {
    $tests[0]{startup} = \&notso_startup;
    $tests[-1]{shutdown} = \&notso_shutdown;
}

local $SIG{ALRM} = 'IGNORE';
TEST:
foreach my $t (@tests) {
    if (ref $t->{testcmd} eq 'CODE') {
	$t->{testcmd}->();
	next;
    }

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

    close($out)
	or bad $test, 'NOEXIT', $! ?
	"Close pipe from '@runcmd' failed: $!" :
	"Command '@runcmd' failed: $?", $log;

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
if ($testmode{tcp4} || $testmode{tcp6}) {
    my @sshcmd = ('ssh', $lnx_r_ssh, 'pkill', 'tcpbench');
    printcmd(@sshcmd);
    printcmd('pkill', 'tcpbench');
}

# create a tgz file with all log files
my @paxcmd = ('pax', '-x', 'cpio', '-wzf', "$netlinkdir/test.log.tgz");
push @paxcmd, '-v' if $opts{v};
push @paxcmd, ("-s,^$logdir/,,", "-s,^$logdir,,", $logdir);
printcmd(@paxcmd)
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
    if ($l =~ m{(\d+) mbufs? in use}) {
	my $mbufs = $1;
	print "used mbufs: $mbufs\n";
    } elsif ($l =~ m{(\d+) mbufs? allocated to data}) {
	my $data_mbufs = $1;
	print "data mbufs: $data_mbufs\n";
    } elsif ($l =~ m{(\d+) mbufs? allocated to packet headers}) {
	my $header_mbufs = $1;
	print "header mbufs: $header_mbufs\n";
    } elsif ($l =~ m{(\d+) mbufs? allocated to socket names and addresses}) {
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

sub ping_f_parser {
    my ($l, $log) = @_;
    if ($l =~ m{rtt min/avg/max/mdev = ([\.\d]+)/([\.\d]+)/([\.\d]+)/([\.\d]+) ms, ipg/ewma ([\.\d]+)/([\.\d]+) ms}) {
	my $min = $1;
	my $avg = $2;
	my $max = $3;
	my $mdev = $4;
	my $ipg = $5;
	my $ewma = $6;
	print "Ping: $min/$avg/$max/$mdev $ipg/$ewma\n";
    }
    if ($l =~ m{round-trip min/avg/max/std-dev = ([\.\d]+)/([\.\d]+)/([\.\d]+)/([\.\d]+) ms}) {
	my $min = $1;
	my $avg = $2;
	my $max = $3;
	my $stddev = $4;
	print "Ping: $min/$avg/$max/$stddev\n";
    }
    return 1;
}

sub printcmd {
    my @cmd = @_;
    print "@cmd\n";
    system(@cmd);
}
