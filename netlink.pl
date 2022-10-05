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

my @alltests = sort qw(all fragment icmp ipopts pathmtu tcp udp);
my @allpseudodevs = sort qw(aggr bridge carp none trunk veb vlan);
my @allifs = sort qw(em igc ix ixl);

my %opts;
getopts('c:e:i:l:r:t:v', \%opts) or do {
    print STDERR <<"EOF";
usage: netlink.pl [-v] [-c pseudo-dev] [-e environment] [-i interface]
	[-l index] [-r index] [-t timeout] [test ...]
    -c pseudo-dev	@{[ join ', ', @allpseudodevs ]}
    -e environ		parse environment for tests from shell script
    -i interface	@{[ join ', ', @allifs ]}
    -l index		interface index, default 0
    -r index		interface index, default 1
    -t timeout		timeout for a single test, default 60 seconds
    -v			verbose
    test		@{[ join ', ', @alltests ]}
			appending 4 or 6 to a test restricts the IP version.
EOF
    exit(2);
};
my $verbose = $opts{v};
my $timeout = $opts{t} || 20;
environment($opts{e}) if $opts{e};
my $pseudodev = $opts{c} || 'none';
my $interface = $opts{i} || "em";

my $line = $ENV{NETLINK_LINE} || die "NETLINK_LINE is not in env";
my $management_if = $ENV{MANAGEMENT_IF} || die "MANAGEMENT_IF is not in env";

# ifN if N is even then it is left, odd means right.
my $left_ifidx = $opts{l} || ("${interface}0" eq $management_if? 2 : 0);
my $right_ifidx = $opts{r} || ("${interface}1" eq $management_if? 3 : 1);

warn "left interface should be in the wrong network" if ($left_ifidx % 2);
warn "right interface should be in the wrong network" if (!$right_ifidx % 2);

die "Unknown interface: $interface" unless grep { $_ eq $interface } @allifs;
if (!grep { $_ eq $pseudodev} @allpseudodevs && $pseudodev) {
    die "Unknown pseudo-device: $pseudodev";
}

my %allmodes;
@allmodes{($_, $_ . '4' , $_ . '6')} = () foreach @alltests;
my %testmode = map {
    die "Unknown test mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV;
$testmode{all} = 1 unless @ARGV;
$testmode{all4} = $testmode{all6} = 1 if ($testmode{all});
if ($testmode{all4}) {
    $testmode{$_} = 1 foreach (map { $_ . '4' } @alltests);
}
if ($testmode{all6}) {
    $testmode{$_} = 1 foreach (map { $_ . '6' } @alltests);
}

foreach (keys %testmode) {
    $testmode{$_ . '4'} = $testmode{$_ . '6'} = 1 if ($_ =~ /[^46]$/);
}

my $ipv4 = (join '', keys %testmode) =~ /4/;
my $ipv6 = (join '', keys %testmode) =~ /6/;

my $ip4prefix = '10.10';
my $ip6prefix = 'fdd7:e83e:66bd:10';

my $obsd_l_if = $interface . $left_ifidx;
my $obsd_l_net = "$ip4prefix.${line}1.0/24";
my $obsd_l_addr = "$ip4prefix.${line}1.2";
my $obsd_l_net6 = "${ip6prefix}${line}1::/64";
my $obsd_l_addr6 = "${ip6prefix}${line}1::2";

my $obsd_r_if = $interface . $right_ifidx;
my $obsd_r_net = "$ip4prefix.${line}2.0/24";
my $obsd_r_addr = "$ip4prefix.${line}2.3";
my $obsd_r_net6 = "${ip6prefix}${line}2::/64";
my $obsd_r_addr6 = "${ip6prefix}${line}2::3";

my $lnx_l_if = "enp6s0"; # XXX: make this an env var?
my $lnx_l_pdev = "$lnx_l_if.0";
my $lnx_l_addr = "$ip4prefix.${line}1.1";
my $lnx_l_addr6 = "${ip6prefix}${line}1::1";
my $lnx_l_net = "$lnx_l_addr/24";
my $lnx_l_net6 = "$lnx_l_addr6/64";
my $lnx_l_ssh = 'root@lt40'; #$ENV{LINUXL_SSH}; # XXX

my $lnx_r_if = "enp6s0"; # XXX
my $lnx_r_pdev = "$lnx_r_if.0";
my $lnx_r_addr = "$ip4prefix.${line}2.4";
my $lnx_r_addr6 = "${ip6prefix}${line}2::4";
my $lnx_r_net = "$lnx_r_addr/24";
my $lnx_r_net6 = "$lnx_r_addr6/64";
my $lnx_r_ssh = 'root@lt43'; #$ENV{LINUXR_SSH};

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

# unconfigure all interfaces used in testing
my @allinterfaces = map { m{^([a-z]+\d+):} } `ifconfig`;

foreach my $ifn (@allinterfaces) {
    unless ($ifn =~ m{^(lo|enc|pflog|${management_if})}) {
	mysystem('ifconfig', $ifn, '-inet', '-inet6', 'down');
    }
    my $pdevre = join '|', @allpseudodevs;
    mysystem('ifconfig', $ifn, 'destroy') if ($ifn =~ m{^($pdevre)});
}

# unconfigure linux interfaces
mysystem('ssh', $lnx_l_ssh, 'ip', 'addr', 'del', $lnx_l_net, 'dev',
    $lnx_l_pdev);
mysystem('ssh', $lnx_l_ssh, 'ip', 'addr', 'del', $lnx_l_net6, 'dev',
    $lnx_l_pdev);
mysystem('ssh', $lnx_l_ssh, 'ip', 'addr', 'del', $lnx_l_net, 'dev',
    $lnx_l_if);
mysystem('ssh', $lnx_l_ssh, 'ip', 'addr', 'del', $lnx_l_net6, 'dev',
    $lnx_l_if);

mysystem('ssh', $lnx_r_ssh, 'ip', 'addr', 'del', $lnx_r_net, 'dev',
    $lnx_r_pdev);
mysystem('ssh', $lnx_r_ssh, 'ip', 'addr', 'del', $lnx_r_net6, 'dev',
    $lnx_r_pdev);
mysystem('ssh', $lnx_r_ssh, 'ip', 'addr', 'del', $lnx_r_net, 'dev',
    $lnx_r_if);
mysystem('ssh', $lnx_r_ssh, 'ip', 'addr', 'del', $lnx_r_net6, 'dev',
    $lnx_r_if);

mysystem('ssh', $lnx_l_ssh, 'ip', 'route', 'del', $obsd_r_net);
mysystem('ssh', $lnx_r_ssh, 'ip', 'route', 'del', $obsd_l_net);
mysystem('ssh', $lnx_l_ssh, 'ip', '-6', 'route', 'del', $obsd_r_net6);
mysystem('ssh', $lnx_r_ssh, 'ip', '-6', 'route', 'del', $obsd_l_net6);

mysystem('arp', '-da');
mysystem('ndp', '-c');

mysystem('ssh', $lnx_l_ssh, 'ip', 'neigh', 'flush', 'all', 'dev',
    $lnx_l_if);
mysystem('ssh', $lnx_l_ssh, 'ip', 'neigh', 'flush', 'all', 'dev',
    $lnx_l_pdev);
mysystem('ssh', $lnx_l_ssh, 'ip', '-6', 'neigh', 'flush', 'all', 'dev',
    $lnx_l_if);
mysystem('ssh', $lnx_l_ssh, 'ip', '-6', 'neigh', 'flush', 'all', 'dev',
    $lnx_l_pdev);

mysystem('ssh', $lnx_r_ssh, 'ip', 'neigh', 'flush', 'all', 'dev',
    $lnx_r_if);
mysystem('ssh', $lnx_r_ssh, 'ip', 'neigh', 'flush', 'all', 'dev',
    $lnx_r_pdev);
mysystem('ssh', $lnx_r_ssh, 'ip', '-6', 'neigh', 'flush', 'all', 'dev',
    $lnx_r_if);
mysystem('ssh', $lnx_r_ssh, 'ip', '-6', 'neigh', 'flush', 'all', 'dev',
    $lnx_r_pdev);

# configure given interface type
if ($pseudodev eq 'bridge' || $pseudodev eq 'none') {
    if ($ipv4) {
	mysystem('ifconfig', $obsd_l_if, 'inet', "${obsd_l_addr}/24");
	mysystem('ifconfig', $obsd_r_if, 'inet', "${obsd_r_addr}/24");
    }
    if ($ipv6) {
	mysystem('ifconfig', $obsd_l_if, 'inet6', $obsd_l_addr6);
	mysystem('ifconfig', $obsd_r_if, 'inet6', $obsd_r_addr6);
    }
}

mysystem('ifconfig', $obsd_l_if, 'up');
mysystem('ifconfig', $obsd_r_if, 'up');

mysystem('sysctl net.inet.ip.forwarding=1') if ($ipv4);
mysystem('sysctl net.inet6.ip6.forwarding=1') if ($ipv6);

# allow tcpbench to bind on ipv6 addresses without explicitly providing it
mysystem('ssh', $lnx_l_ssh, 'sysctl','net.ipv6.bindv6only=1') if ($ipv6);
mysystem('ssh', $lnx_r_ssh, 'sysctl','net.ipv6.bindv6only=1') if ($ipv6);

# allow fragment reassembly to use up to 1GiB of memory
mysystem('ssh', $lnx_l_ssh, 'sysctl', 'net.ipv6.ip6frag_high_thresh=1073741824')
    if ($testmode{fragment6});
mysystem('ssh', $lnx_r_ssh, 'sysctl', 'net.ipv6.ip6frag_high_thresh=1073741824')
    if ($testmode{fragment6});
mysystem('ssh', $lnx_l_ssh, 'sysctl', 'net.ipv4.ipfrag_high_thresh=1073741824')
    if ($testmode{fragment4});
mysystem('ssh', $lnx_r_ssh, 'sysctl', 'net.ipv4.ipfrag_high_thresh=1073741824')
    if ($testmode{fragment4});

my $configure_linux = 1;

if ($pseudodev eq 'aggr') {
    # XXX: multiple interfaces in one aggr
    mysystem('ifconfig', 'aggr0', 'create');
    mysystem('ifconfig', 'aggr1', 'create');

    mysystem('ifconfig', $obsd_l_if, 'up');
    mysystem('ifconfig', $obsd_r_if, 'up');
    mysystem('ifconfig', 'aggr0', 'trunkport', $obsd_l_if);
    mysystem('ifconfig', 'aggr1', 'trunkport', $obsd_r_if);

    if ($ipv4) {
	mysystem('ifconfig', 'aggr0', "${obsd_l_addr}/24");
	mysystem('ifconfig', 'aggr1', "${obsd_r_addr}/24");
    }
    if ($ipv6) {
	mysystem('ifconfig', 'aggr0', $obsd_l_addr6);
	mysystem('ifconfig', 'aggr1', $obsd_r_addr6);
    }

    mysystem('ifconfig', 'aggr0', 'up');
    mysystem('ifconfig', 'aggr1', 'up');
} elsif ($pseudodev eq 'bridge') {
    # XXX: vether
    mysystem('ifconfig', 'bridge0', 'create');
    mysystem('ifconfig', 'bridge0', 'add', $obsd_l_if);
    mysystem('ifconfig', 'bridge0', 'add', $obsd_r_if);
    mysystem('ifconfig', 'bridge0', 'up');
} elsif ($pseudodev eq 'carp') {
    # XXX
} elsif ($pseudodev eq 'trunk') {
    # XXX
} elsif ($pseudodev eq 'veb') {
    mysystem('ifconfig', 'veb0', 'create');
    mysystem('ifconfig', 'vport0', 'create');
    mysystem('ifconfig', 'vport1', 'create');

    if ($ipv4) {
	mysystem('ifconfig', 'vport0', 'inet', "${obsd_l_addr}/24");
	mysystem('ifconfig', 'vport1', 'inet', "${obsd_r_addr}/24");
    }
    if ($ipv6) {
	mysystem('ifconfig', 'vport0', 'inet6', $obsd_l_addr6);
	mysystem('ifconfig', 'vport1', 'inet6', $obsd_r_addr6);
    }

    mysystem('ifconfig', 'vport0', 'up');
    mysystem('ifconfig', 'vport1', 'up');
    mysystem('ifconfig', $obsd_l_if, 'up');
    mysystem('ifconfig', $obsd_r_if, 'up');
    mysystem('ifconfig', 'veb0', 'add', $obsd_l_if);
    mysystem('ifconfig', 'veb0', 'add', $obsd_r_if);
    mysystem('ifconfig', 'veb0', 'add', 'vport0');
    mysystem('ifconfig', 'veb0', 'add', 'vport1');
    mysystem('ifconfig', 'veb0', 'up');
} elsif ($pseudodev eq 'vlan') {
    $configure_linux = 0; # all necessary config is below
    my $vlanl = 252;
    my $vlanr = 253;

    mysystem('ssh', $lnx_l_ssh, 'modprobe', '8021q');
    mysystem('ssh', $lnx_r_ssh, 'modprobe', '8021q');

    mysystem('ssh', $lnx_l_ssh, 'ip', 'link', 'add', 'link', $lnx_l_if,
	'name', $lnx_l_pdev, 'type', 'vlan', 'id', $vlanl);
    mysystem('ssh', $lnx_r_ssh, 'ip', 'link', 'add', 'link', $lnx_r_if,
	'name', $lnx_r_pdev, 'type', 'vlan', 'id', $vlanr);

    mysystem('ssh', $lnx_l_ssh, 'ip', 'link', 'set', 'dev', $lnx_l_if, 'up');
    mysystem('ssh', $lnx_r_ssh, 'ip', 'link', 'set', 'dev', $lnx_r_if, 'up');

    mysystem('ssh', $lnx_l_ssh, 'ip', 'link', 'set', 'dev', $lnx_l_pdev, 'up');
    mysystem('ssh', $lnx_r_ssh, 'ip', 'link', 'set', 'dev', $lnx_r_pdev, 'up');

    mysystem('ifconfig', 'vlan0', 'create');
    mysystem('ifconfig', 'vlan1', 'create');
    mysystem('ifconfig', 'vlan0', 'parent', $obsd_l_if, 'vnetid', $vlanl);
    mysystem('ifconfig', 'vlan1', 'parent', $obsd_r_if, 'vnetid', $vlanr);

    if ($ipv4) {
	mysystem('ifconfig', 'vlan0', 'inet', "${obsd_l_addr}/24", 'up');
	mysystem('ifconfig', 'vlan1', 'inet', "${obsd_r_addr}/24", 'up');

	mysystem('ssh', $lnx_l_ssh, 'ip', 'addr', 'add', $lnx_l_net, 'dev',
	    $lnx_l_pdev);
	mysystem('ssh', $lnx_l_ssh, 'ip', 'route', 'add', $obsd_r_net, 'via',
	    $obsd_l_addr, 'dev', "$lnx_l_pdev");

	mysystem('ssh', $lnx_r_ssh, 'ip', 'addr', 'add', $lnx_r_net, 'dev',
	    $lnx_r_pdev);
	mysystem('ssh', $lnx_r_ssh, 'ip', 'route', 'add', $obsd_l_net, 'via',
	    $obsd_r_addr, 'dev', "$lnx_r_pdev");
    }
    if ($ipv6) {
	mysystem('ifconfig', 'vlan0', 'inet6', $obsd_l_addr6, 'up');
	mysystem('ifconfig', 'vlan1', 'inet6', $obsd_r_addr6, 'up');

	mysystem('ssh', $lnx_l_ssh, 'ip', 'addr', 'add', $lnx_l_net6, 'dev',
	    $lnx_l_pdev);
	mysystem('ssh', $lnx_l_ssh, 'ip', '-6', 'route', 'add', $obsd_r_net6, 'via',
	    $obsd_l_addr6, 'dev', "$lnx_l_pdev");

	mysystem('ssh', $lnx_r_ssh, 'ip', 'addr', 'add', $lnx_r_net6, 'dev',
	    $lnx_r_pdev);
	mysystem('ssh', $lnx_r_ssh, 'ip', '-6', 'route', 'add', $obsd_l_net6, 'via',
	    $obsd_r_addr6, 'dev', "$lnx_r_pdev");
    }
}
# XXX: tpmr, nipsec, gre?

if ($configure_linux) {
    if ($ipv4) {
	my @sshcmd = ('ssh', $lnx_l_ssh);
	mysystem(@sshcmd, 'ip', 'addr', 'add', $lnx_l_net, 'dev', $lnx_l_if);
	mysystem(@sshcmd, 'ip', 'link', 'set', 'dev', $lnx_l_if, 'up');
	mysystem(@sshcmd, 'ip', 'route', 'add', $obsd_r_net, 'via',
	    $obsd_l_addr, 'dev', "$lnx_l_if");

	@sshcmd = ('ssh', $lnx_r_ssh);
	mysystem(@sshcmd, 'ip', 'addr', 'add', $lnx_r_net, 'dev', $lnx_r_if);
	mysystem(@sshcmd, 'ip', 'link', 'set', 'dev', $lnx_r_if, 'up');
	mysystem(@sshcmd, 'ip', 'route', 'add', $obsd_l_net, 'via',
	    $obsd_r_addr, 'dev', "$lnx_r_if");
    }
    if ($ipv6) {
	my @sshcmd = ('ssh', $lnx_l_ssh);
	mysystem(@sshcmd, 'ip', 'addr', 'add', $lnx_l_net6, 'dev', $lnx_l_if);
	mysystem(@sshcmd, 'ip', '-6', 'route', 'add', $obsd_r_net6, 'via',
	    $obsd_l_addr6, 'dev', "$lnx_l_if");

	@sshcmd = ('ssh', $lnx_r_ssh);
	mysystem(@sshcmd, 'ip', 'addr', 'add', $lnx_r_net6, 'dev', $lnx_r_if);
	mysystem(@sshcmd, 'ip', '-6', 'route', 'add', $obsd_l_net6, 'via',
	    $obsd_r_addr6, 'dev', "$lnx_r_if");
    }
}

# wait for linux
sleep(3);

# tcpbench tests

if ($testmode{tcp4} || $testmode{tcp6}) {
    my @cmd = ('ssh', $lnx_r_ssh, 'pkill -f tcpbench');
    mysystem(@cmd);

    @cmd = ('pkill -f tcpbench');
    mysystem(@cmd);

    # requires echo 1 > /proc/sys/net/ipv6/bindv6only
    @cmd = ('ssh', '-f', $lnx_r_ssh, 'tcpbench', '-s', '-r0', '-S1000000');
    mysystem(@cmd)
	and die "Start tcpbench server with '@cmd' failed: $?";

    @cmd = ('tcpbench', '-s', '-r0', '-S1000000');
    defined(my $pid = fork())
	or die "Fork failed: $!";
    unless ($pid) {
	exec(@cmd);
	warn "Exec '@cmd' failed: $!";
	_exit(126);
    }
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
push @tests, (
    {
	testcmd => ['ssh', $lnx_l_ssh, 'tcpbench', '-S1000000', '-t10', $obsd_l_addr],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'tcpbench', '-S1000000', '-t10', '-n100', $obsd_l_addr],
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
	testcmd => ['ssh', $lnx_l_ssh, 'tcpbench', '-S1000000', '-t10', $lnx_r_addr],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'tcpbench', '-S1000000', '-t10', '-n100', $lnx_r_addr],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }
) if ($testmode{tcp4});
push @tests, (
    {
	testcmd => ['ssh', $lnx_l_ssh, 'tcpbench', '-S1000000', '-t10', $obsd_l_addr6],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'tcpbench', '-S1000000', '-t10', '-n100', $obsd_l_addr6],
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
	testcmd => ['ssh', $lnx_l_ssh, 'tcpbench', '-S1000000', '-t10', $lnx_r_addr6],
	parser => \&tcpbench_parser,
	finalize => \&tcpbench_finalize,
    }, {
	testcmd => ['ssh', $lnx_l_ssh, 'tcpbench', '-S1000000', '-t10', '-n100', $lnx_r_addr6],
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
if ($testmode{tcp4} || $testmode{tcp6}) {
    my @sshcmd = ('ssh', $lnx_r_ssh, 'pkill', 'tcpbench');
    mysystem(@sshcmd);
    mysystem('pkill', 'tcpbench');
}

# create a tgz file with all log files
my @paxcmd = ('pax', '-x', 'cpio', '-wzf', "$netlinkdir/test.log.tgz");
push @paxcmd, '-v' if $opts{v};
push @paxcmd, ("-s,^$logdir/,,", "-s,^$logdir,,", $logdir);
mysystem(@paxcmd)
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

sub netstat_s_parser {
	# XXX
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

sub mysystem {
    my @cmd = @_;
    print(join ' ', @cmd, "\n") if $verbose;
    system(@cmd);
}
