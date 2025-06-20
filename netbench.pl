#!/usr/bin/perl

# Copyright (c) 2022-2025 Alexander Bluhm <bluhm@genua.de>
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
use Errno;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use File::Basename;
use Getopt::Std;
use List::Util qw(sum);

my @alltestmodes = qw(
    tcpbench tcpsplice tcpcopy
    udpbench udpsplice udpcopy
);

my %opts;
getopts('A:a:B:b:C:c:d:f:i:l:m:N:P:R:S:s:t:v', \%opts) or do {
    print STDERR <<"EOF";
usage: netbench.pl [-v] [-A address] -a address [-B bitrate] [-b bufsize]
	[-C pseudo] [-c client] [-d delay] [-f frames] [-i idle] [-l length]
	[-m mmsglen] [-P packetrate] [-p pseudo] [-R ifaddr] [-S ifaddr]
	[-s server] [-t timeout] [test ...]
    -A address	IP address of relay
    -a address	IP address for packet destination
    -B bitrate	bits per seconds send rate
    -b bufsize	set size of send and receive buffer
    -C pseudo	pseudo network device changes packet length
    -c client	connect via ssh to start packet generator
    -d delay	wait for setup before sending
    -f frames	calculate udp payload to fragment packet into frames
    -i idle	idle timeout before receiving stops
    -m mmsglen	number of mmsghdr for sendmmsg or recvmmsg
    -N repeat	run instances in parallel with incremented address
    -P packet	packets per seconds send rate
    -R ifaddr	multicast receive interface address or name
    -S ifaddr	multicast send interface address or name
    -l length	set length of udp payload
    -s sever	connect via ssh to start packet consumer
    -t timeout	send duration and receive timeout, default 1
    -v		verbose
    test ...	test mode: @alltestmodes
EOF
    exit(2);
};
my $addr = $opts{a}
    or die "IP address required";
$addr =~ /^([0-9]+\.[0-9.]+|[0-9a-fA-F:]+)$/
    or die "Address must be IPv4 or IPv6";
my $relay_addr = $opts{A};
!$relay_addr || $relay_addr =~ /^([0-9]+\.[0-9.]+|[0-9a-fA-F:]+)$/
    or die "Relay address must be IPv4 or IPv6";
my $client_ssh = $opts{c};
my $server_ssh = $opts{s};
my $pseudo = $opts{C};

@ARGV or die "No test mode specified";
my %testmode;
foreach my $mode (@ARGV) {
    grep { $_ eq $mode } @alltestmodes
	or die "Unknown test mode '$mode'";
    $testmode{$mode} = 1;
}
foreach my $mode (@alltestmodes) {
    die "Test mode '$mode' must be used solely"
	if $testmode{$mode} && keys %testmode != 1;
}
$testmode{tcp} = 1
    if $testmode{tcpbench} || $testmode{tcpsplice} || $testmode{tcpcopy};
$testmode{udp} = 1
    if $testmode{udpbench} || $testmode{udpsplice} || $testmode{udpcopy};
$testmode{splice} = 1
    if $testmode{tcpsplice} || $testmode{udpsplice};
$testmode{copy} = 1
    if $testmode{tcpcopy} || $testmode{udpcopy};

my $dir = dirname($0);
chdir($dir)
    or die "Change directory to '$dir' failed: $!";
my $netbenchdir = getcwd();
$| = 1;

my $paylen = $opts{l};
if (defined($opts{f})) {
    !defined($paylen)
	or die "Use either -f frames or -l lenght";
    $opts{f} =~ /\d+$/
	or die "Frames must be number";
    my $mtu = 1500;
    if ($pseudo) {
	if ($pseudo eq "gif") {
		$mtu = 1480;
	} elsif ($pseudo eq "gif6") {
		$mtu = 1460;
	} elsif ($pseudo eq "gre") {
		$mtu = 1472;
	}
    }
    if ($addr =~ /:/) {
	if ($opts{f} <= 1) {
	    # ether frame minus ip6 header
	    $paylen = ($mtu - 40) * $opts{f};
	} else {
	    # ether frame minus ip6 header minus fragment header minus round
	    $paylen = ($mtu - 40 - 8 - 4) * $opts{f};
	}
    } else {
	# ether frame minus ip header
	$paylen = ($mtu - 20) * $opts{f};
    }
    # minus udp header
    $paylen = $paylen < 8 ? 0 : $paylen - 8;
    if ($addr =~ /:/) {
	# maximux ip6 payload length
	$paylen = 2**16 - 1 - 8 if $paylen > 2**16 - 1 - 8;
    } else {
	# maximum ip packet length
	$paylen = 2**16 - 1 - 20 - 8 if $paylen > 2**16 - 1 - 20 - 8;
    }
}

my (@servers, @clients, @relays);
my %server = (
    name	=> "server",
    ssh		=> $server_ssh,
    addr	=> $addr,
);
start_server_tcp(\%server) if $testmode{tcp};
start_server_udp(\%server) if $testmode{udp};

my (%relay, $client_addr, $client_port);
if ($testmode{splice} || $testmode{copy}) {
    %relay = (
	name	=> "relay",
	listen	=> $relay_addr,
	connect	=> $server{addr},
	port	=> $server{port},
    );
    start_relay(\%relay);
    ($client_addr, $client_port) = (@relay{qw(addr port)});
} else {
    ($client_addr, $client_port) = (@server{qw(addr port)});
}

my %client = (
    name	=> "client",
    ssh		=> $client_ssh,
    addr	=> $client_addr,
    port	=> $client_port,
);
push @servers, \%server;
push @relays, \%relay if %relay;
push @clients, \%client;

start_client_tcp(\%client) if $testmode{tcp};
start_client_udp(\%client) if $testmode{udp};

set_nonblock($_) foreach (@clients, @relays, @servers);

collect_output(@clients, @relays, @servers);

print_status_tcp() if $testmode{tcp};
print_status_udp() if $testmode{udp};

if ($testmode{tcp}) {
    foreach my $server (@servers) {
	# timeout tcpbench -s may hang and block the port
	cleanup_server_tcp($server);
	# timeout always fails with error
	delete $server->{status};
    }
}

my @failed = map { $_->{status} ? $_->{name} : () }
    (@clients, @relays, @servers);
die "Process '@failed' failed" if @failed;

exit;

sub start_server_tcp {
    my ($proc) = @_;

    $proc->{port} = "12345";
    my $timeout = 3;
    $timeout += $opts{t} if defined($opts{t});
    my @cmd = ('tcpbench', '-s');
    unshift @cmd, ('timeout', $timeout) if $opts{t};
    push @cmd, "-b$proc->{addr}";
    push @cmd, "-p$proc->{port}";
    push @cmd, "-S$opts{b}" if defined($opts{b});
    unshift @cmd, ('ssh', '-nT', $proc->{ssh}) if $proc->{ssh};
    $proc->{cmd} = \@cmd;
    $proc->{conn} = "recv";

    open_pipe($proc);
}

sub start_client_tcp {
    my ($proc) = @_;

    my @cmd = ('tcpbench');
    push @cmd, "-n$opts{N}" if defined($opts{N});
    push @cmd, "-p$proc->{port}";
    push @cmd, "-S$opts{b}" if defined($opts{b});
    push @cmd, "-t$opts{t}" if defined($opts{t});
    push @cmd, $proc->{addr};
    unshift @cmd, ('ssh', '-nT', $proc->{ssh}) if $proc->{ssh};
    $proc->{cmd} = \@cmd;
    $proc->{conn} = "send";

    open_pipe($proc);
}

sub start_server_udp {
    my ($proc) = @_;

    my $timeout = 3;
    $timeout += $opts{d} if defined($opts{d});
    $timeout += $opts{t} if defined($opts{t});
    my @cmd = ('udpbench');
    push @cmd, "-B$opts{B}" if defined($opts{B});
    push @cmd, "-b$opts{b}" if defined($opts{b});
    push @cmd, "-C$opts{C}" if defined($opts{C});
    push @cmd, "-d$opts{d}" if defined($opts{d});
    push @cmd, "-i$opts{i}" if defined($opts{i});
    push @cmd, "-l$paylen" if defined($paylen);
    push @cmd, "-m$opts{m}" if defined($opts{m});
    push @cmd, "-N$opts{N}" if defined($opts{N});
    push @cmd, "-P$opts{P}" if defined($opts{P});
    push @cmd, "-I$opts{R}" if defined($opts{R});
    push @cmd, '-p0';
    push @cmd, "-t$timeout" if defined($opts{t});
    push @cmd, ('recv', $proc->{addr});
    unshift @cmd, ('ssh', '-nT', $proc->{ssh}) if $proc->{ssh};
    $proc->{cmd} = \@cmd;

    open_pipe($proc, "sockname", $opts{N});
}

sub start_client_udp {
    my ($proc) = @_;

    my @cmd = ('udpbench');
    push @cmd, "-B$opts{B}" if defined($opts{B});
    push @cmd, "-b$opts{b}" if defined($opts{b});
    push @cmd, "-C$opts{C}" if defined($opts{C});
    push @cmd, "-d$opts{d}" if defined($opts{d});
    push @cmd, "-i$opts{i}" if defined($opts{i});
    push @cmd, "-l$paylen" if defined($paylen);
    push @cmd, "-m$opts{m}" if defined($opts{m});
    push @cmd, "-N$opts{N}" if defined($opts{N});
    push @cmd, "-P$opts{P}" if defined($opts{P});
    push @cmd, "-I$opts{S}" if defined($opts{S});
    push @cmd, "-p$proc->{port}";
    push @cmd, "-t$opts{t}" if defined($opts{t});
    push @cmd, ('send', $proc->{addr});
    unshift @cmd, ('ssh', '-nT', $proc->{ssh}) if $proc->{ssh};
    $proc->{cmd} = \@cmd;

    open_pipe($proc, "sockname", $opts{N});
}

sub start_relay {
    my ($proc) = @_;

    my $timeout = 2;
    $timeout += $opts{d} if defined($opts{d});
    $timeout += $opts{t} if defined($opts{t});
    my @cmd = ('splicebench');
    push @cmd, '-c' if $testmode{copy};
    push @cmd, '-u' if $testmode{udp};
    push @cmd, "-b$opts{b}" if defined($opts{b});
    push @cmd, "-i$opts{i}" if defined($opts{i});
    push @cmd, "-N$opts{N}" if defined($opts{N}) && $testmode{udp};
    push @cmd, "-n$opts{N}" if defined($opts{N}) && $testmode{tcp};
    push @cmd, "-t$timeout" if defined($opts{t});
    push @cmd, "[$proc->{listen}]:0";
    push @cmd, "[$proc->{connect}]:$proc->{port}";
    unshift @cmd, ('ssh', '-nT', $proc->{ssh}) if $proc->{ssh};
    $proc->{cmd} = \@cmd;

    open_pipe($proc, "listen sockname", $testmode{udp} && $opts{N});
}

sub open_pipe {
    my ($proc, $sockname, $num) = @_;

    print "command: @{$proc->{cmd}}\n" if $opts{v};
    $proc->{pid} = open(my $fh, '-|', @{$proc->{cmd}})
	or die "Open pipe from proc $proc->{name} '@{$proc->{cmd}}' failed: $!";
    $proc->{fh} = $fh;

    local $_;
    while (<$fh>) {
	print if $opts{v};
	last unless $sockname;
	if (/^$sockname: ([0-9.a-fA-F:]+) ([0-9]+)/) {
	    $proc->{addr} ||= $1;
	    $proc->{port} = $2;
	    last unless $num && --$num;
	}
    }
    unless (defined) {
	close($fh) or die $! ?
	    "Close pipe from proc $proc->{name} '@{$proc->{cmd}}' failed: $!" :
	    "Proc $proc->{name} Client '@{$proc->{cmd}}' failed: $?";
	delete $proc->{fh};
	delete $proc->{pid};
    }
}

sub set_nonblock {
    my ($proc) = @_;

    my $flags = fcntl($proc->{fh}, F_GETFL, 0)
	or die "Proc $proc->{name} fcntl F_GETFL failed: $!\n";
    fcntl($proc->{fh}, F_SETFL, $flags | O_NONBLOCK)
	or die "Proc $proc->{name} fcntl F_SETFL O_NONBLOCK failed: $!\n";
}

sub collect_output {
    my @procs = @_;

    while (my @fhs = map { $_->{fh} || () } @procs) {

	if ($testmode{tcp}) {
	    my @pids = map { $_->{pid} || () } @clients;
	    unless (@pids) {
		@pids = map { $_->{pid} || () } @servers;
		kill 'TERM', @pids;
	    }
	}
	my $rin = '';
	vec($rin, fileno($_), 1) = 1 foreach @fhs;

	my $nfound = select(my $rout = $rin, undef, undef, undef);
	defined($nfound)
	    or die "Select failed: $!";
	$nfound
	    or die "Select timeout";

	read_output($_, $rout) foreach @procs;
    }
}

my %status;
sub read_output {
    my ($proc, $rout) = @_;

    $proc->{fh} && vec($rout, fileno($proc->{fh}), 1)
	or return;

    undef $!;
    local $_;
    while (readline($proc->{fh})) {
	print if $opts{v};
	# handle short reads
	$_ = $proc->{prev}. $_ if defined($proc->{prev});
	$proc->{prev} = /\n$/ ? undef : $_;
	print if !$opts{v} && /^(send|recv|Conn):.*\n/;
	if (/^(send|recv):.*
	    \spackets\s([0-9]+),.*\sether\s([0-9]+),.*
	    \sbegin\s([0-9.]+),.*\send\s([0-9.]+),.*/x) {
	    $status{$1}{etherlen} = ($status{$1}{etherlen} || 0) + $2 * $3;
	    $status{$1}{begin} = $4
		if !$status{$1}{begin} || $4 < $status{$1}{begin};
	    $status{$1}{end} = $5
		if !$status{$1}{end} || $status{$1}{end} < $5;;
	}
	if (/^Conn:\s+\d+\s+([kmgt]?)bps:\s+([\d.]+)\s/i) {
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
		die "Unit '$1' unknown";
	    }
	    push @{$status{$proc->{conn}}{bits} ||= []}, $value;
	}
    }
    unless ($!{EWOULDBLOCK}) {
	unless (close($proc->{fh})) {
	    die "Close pipe from proc $proc->{name} '@{$proc->{cmd}}' ".
		"failed: $!" if $!;
	    warn "Proc $proc->{name} '@{$proc->{cmd}}' failed: $?";
	    $proc->{status} = $?;
	}
	delete $proc->{fh};
	delete $proc->{pid};
    }
}

sub print_status_tcp {
    foreach (qw(send recv)) {
	my @values = @{$status{$_}{bits}};
	printf("%sall: bit/s %g\n",
	    $_, sum(@values) / scalar(@values));
    }
}
sub print_status_udp {
    foreach (qw(send recv)) {
	printf("%sall: etherlen %d, begin %f, end %f, duration %f, bit/s %g\n",
	    $_, $status{$_}{etherlen}, $status{$_}{begin}, $status{$_}{end},
	    $status{$_}{end} - $status{$_}{begin},
	    $status{$_}{etherlen} * 8 /
	    ($status{$_}{end} - $status{$_}{begin}));
    }
}

sub cleanup_server_tcp {
    my ($proc) = @_;

    my @cmd = ('tcpbench', '-s');
    push @cmd, "-b$proc->{addr}";
    push @cmd, "-p$proc->{port}";
    push @cmd, "-S$opts{b}" if defined($opts{b});
    @cmd = "'@cmd'" if $proc->{ssh};
    unshift @cmd, ('pkill', '-f');
    unshift @cmd, ('ssh', '-nT', $proc->{ssh}) if $proc->{ssh};
    print "command: @cmd\n" if $opts{v};
    system(@cmd);
}
