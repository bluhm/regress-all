#!/usr/bin/perl

# Copyright (c) 2022-2023 Alexander Bluhm <bluhm@genua.de>
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

my @alltestmodes = qw(all udpbench);

my %opts;
getopts('a:B:b:c:d:f:i:l:m:N:P:s:t:v', \%opts) or do {
    print STDERR <<"EOF";
usage: netbench.pl [-v] -a address [-B bitrate] [-b bufsize] [-c client]
	[-d delay] [-f frames] [-i idle] [-l length] [-m mmsglen]
	[-P packetrate] [-s server] [-t timeout] [test ...]
    -a address	IP address for packet destination
    -B bitrate	bits per seconds send rate
    -b bufsize	set size of send and receive buffer
    -d delay	wait for setup before sending
    -f frames	calculate udp payload to fragment packet into frames
    -i idle	idle timeout before receiving stops
    -c client	connect via ssh to start packet generator
    -m mmsglen	number of mmsghdr for sendmmsg or recvmmsg
    -N repeat	run instances in parallel with incremented address
    -P packet	packets per seconds send rate
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
my $client_ssh = $opts{c};
my $server_ssh = $opts{s};

my %testmode;
foreach my $mode (@ARGV) {
    grep { $_ eq $mode } @alltestmodes
	or die "Unknown test mode '$mode'";
    $testmode{$mode} = 1;
}
$testmode{all} = 1 unless @ARGV;
@testmode{qw(udpbench)} = 1..1 if $testmode{all};

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
    if ($addr =~ /:/) {
	if ($opts{f} <= 1) {
	    # ether frame minus ip6 header
	    $paylen = (1500 - 40) * $opts{f};
	} else {
	    # ether frame minus ip6 header minus fragment header minus round
	    $paylen = (1500 - 40 - 8 - 4) * $opts{f};
	}
    } else {
	# ether frame minus ip header
	$paylen = (1500 - 20) * $opts{f};
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

my (@servers, @clients);
my %server = (
    name	=> "server",
    ssh		=> $server_ssh,
    addr	=> $addr,
);
start_server(\%server);

my %client = (
    name	=> "client",
    ssh		=> $client_ssh,
    addr	=> $server{addr},
    port	=> $server{port},
);
push @servers, \%server;
push @clients, \%client;

start_client($_) foreach (@clients);

set_nonblock($_) foreach (@clients, @servers);

collect_output(@clients, @servers);

print_status();

exit;

my %master;
sub start_server {
    my ($proc) = @_;

    my @cmd = ('udpbench');
    push @cmd, "-B$opts{B}" if defined($opts{B});
    push @cmd, "-b$opts{b}" if defined($opts{b});
    push @cmd, "-d$opts{d}" if defined($opts{d});
    push @cmd, "-i$opts{i}" if defined($opts{i});
    push @cmd, "-l$paylen" if defined($paylen);
    push @cmd, "-m$opts{m}" if defined($opts{m});
    push @cmd, "-N$opts{N}" if defined($opts{N});
    push @cmd, "-P$opts{P}" if defined($opts{P});
    push @cmd, '-p0';
    push @cmd, "-t$opts{t}" if defined($opts{t});
    push @cmd, ('recv', $proc->{addr});
    unshift @cmd, ('ssh', '-nT', $proc->{ssh}) if $proc->{ssh};
    $proc->{cmd} = \@cmd;

    open_pipe($proc);
}

sub start_client {
    my ($proc) = @_;

    my @cmd = ('udpbench');
    push @cmd, "-B$opts{B}" if defined($opts{B});
    push @cmd, "-b$opts{b}" if defined($opts{b});
    push @cmd, "-d$opts{d}" if defined($opts{d});
    push @cmd, "-i$opts{i}" if defined($opts{i});
    push @cmd, "-l$paylen" if defined($paylen);
    push @cmd, "-m$opts{m}" if defined($opts{m});
    push @cmd, "-N$opts{N}" if defined($opts{N});
    push @cmd, "-P$opts{P}" if defined($opts{P});
    push @cmd, "-p$proc->{port}";
    push @cmd, "-t$opts{t}" if defined($opts{t});
    push @cmd, ('send', $proc->{addr});
    unshift @cmd, ('ssh', '-nT', $proc->{ssh}) if $proc->{ssh};
    $proc->{cmd} = \@cmd;

    open_pipe($proc);
}

sub open_pipe {
    my ($proc) = @_;

    $proc->{pid} = open(my $fh, '-|', @{$proc->{cmd}})
	or die "Open pipe from proc $proc->{name} '@{$proc->{cmd}}' failed: $!";
    $proc->{fh} = $fh;

    local $_;
    while (<$fh>) {
	print if $opts{v};
	if (/^sockname: ([0-9.a-fA-F:]+) ([0-9]+)/) {
	    $proc->{addr} = $1;
	    $proc->{port} = $2;
	    last;
	}
    }
    unless (defined) {
	close($fh) or die $! ?
	    "Close pipe from proc $proc->{name} '@{$proc->{cmd}}' failed: $!" :
	    "Proc $proc->{name} Client '@{$proc->{cmd}}' failed: $?";
	delete $proc->{fh};
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
	print if !$opts{v} && /^(send|recv):.*\n/;
	if (/^(send|recv):.*
	    \spackets\s([0-9]+),.*\sether\s([0-9]+),.*
	    \sbegin\s([0-9.]+),.*\send\s([0-9.]+),.*/x) {
	    $status{$1}{etherlen} = ($status{$1}{etherlen} || 0) + $2 * $3;
	    $status{$1}{begin} = $4
		if !$status{$1}{begin} || $4 < $status{$1}{begin};
	    $status{$1}{end} = $5
		if !$status{$1}{end} || $status{$1}{end} < $5;;
	}
    }
    unless ($!{EWOULDBLOCK}) {
	close($proc->{fh}) or warn $! ?
	    "Close pipe from proc $proc->{name} '@{$proc->{cmd}}' failed: $!" :
	    "Proc $proc->{name} '@{$proc->{cmd}}' failed: $?";
	delete $proc->{fh};
    }
}

sub print_status {
    foreach (qw(send recv)) {
	printf("%sall: etherlen %d, begin %f, end %f, duration %f, bit/s %g\n",
	    $_, $status{$_}{etherlen}, $status{$_}{begin}, $status{$_}{end},
	    $status{$_}{end} - $status{$_}{begin},
	    $status{$_}{etherlen} * 8 /
	    ($status{$_}{end} - $status{$_}{begin}));
    }
}
