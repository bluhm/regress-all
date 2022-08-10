#!/usr/bin/perl

# Copyright (c) 2022 Alexander Bluhm <bluhm@genua.de>
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

my %opts;
getopts('a:B:b:c:l:P:s:t:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] -a address [-B bitrate] [-b bufsize] [-c client] [-l length]
    [-P packetrate] [-s server] [-t timeout] [test ...]
    -a address	IP address for packet destination
    -B bitrate	bits per seconds send rate
    -b bufsize	set size of send and receive buffer
    -c client	connect via ssh to start packet generator
    -P packet	packets per seconds send rate
    -l length	set length of udp payload
    -s sever	connect via ssh to start packet consumer
    -t timeout	send duration and receive timeout, default 1
    -v		verbose
    test ...	test mode: all iperf3 tcpbench udpbench
EOF
    exit(2);
};
my $addr = $opts{a}
    or die "IP Address required";
$addr =~ /^[0-9]+\.[0-9.]+$/ || $addr =~ /^[0-9a-fA-F:]+$/
    or die "Address must be IPv4 or IPv6";
my $client_ssh = $opts{c};
my $server_ssh = $opts{s};
my $timeout = $opts{t} || 1;

my %allmodes;
@allmodes{qw(all udpbench)} = ();
my %testmode = map {
    die "Unknown test mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV;
$testmode{all} = 1 unless @ARGV;
@testmode{qw(udpbench)} = 1..1 if $testmode{all};

my $dir = dirname($0);
chdir($dir)
    or die "Change directory to '$dir' failed: $!";
my $netbenchdir = getcwd();
$| = 1;

my @server_cmd = ('udpbench');
push @server_cmd, "-b$opts{b}" if defined($opts{b});
push @server_cmd, "-l$opts{l}" if defined($opts{l});
push @server_cmd, ('-t'.($timeout+10), '-p0', 'recv', $addr);
unshift @server_cmd, ('ssh', '-nT', $server_ssh) if $server_ssh;

my $server_pid = open(my $server_fh, '-|', @server_cmd)
    or die "Open pipe from server '@server_cmd' failed: $!";

my $port;
while (<$server_fh>) {
    print $_ if $opts{v};
    if (/^sockname: ([0-9.a-fA-F:]+) ([0-9]+)/) {
	$port = $2;
	print "netbench port: $port\n" if $opts{v};
	last;
    }
}
unless (defined) {
    close($server_fh) or die $! ?
	"Close pipe from server '@server_cmd' failed: $!" :
	"Server '@server_cmd' failed: $?";
    undef $server_fh;
}

my @client_cmd = ('udpbench');
push @client_cmd, "-B$opts{B}" if defined($opts{B});
push @client_cmd, "-b$opts{b}" if defined($opts{b});
push @client_cmd, "-l$opts{l}" if defined($opts{l});
push @client_cmd, "-P$opts{P}" if defined($opts{P});
push @client_cmd, ("-t$timeout", "-p$port", 'send', $addr);
unshift @client_cmd, ('ssh', '-nT', $client_ssh) if $client_ssh;

my $client_pid = open(my $client_fh, '-|', @client_cmd)
    or die "Open pipe from client '@client_cmd' failed: $!";

while (<$client_fh>) {
    print $_ if $opts{v};
    if (/^sockname: ([0-9.a-fA-F:]+) ([0-9]+)/) {
	last;
    }
}
unless (defined) {
    close($client_fh) or die $! ?
	"Close pipe from client '@client_cmd' failed: $!" :
	"Client '@client_cmd' failed: $?";
    undef $client_fh;
}

my $flags = fcntl($client_fh, F_GETFL, 0)
    or die "Client fcntl F_GETFL failed: $!\n";
fcntl($client_fh, F_SETFL, $flags | O_NONBLOCK)
    or die "Client fcntl F_SETFL O_NONBLOCK failed: $!\n";
$flags = fcntl($server_fh, F_GETFL, 0)
    or die "Server fcntl F_GETFL failed: $!\n";
fcntl($server_fh, F_SETFL, $flags | O_NONBLOCK)
    or die "Server fcntl F_SETFL O_NONBLOCK failed: $!\n";

my ($client_prev, $server_prev);
while ($client_fh || $server_fh) {
    my $rin = '';
    vec($rin, fileno($client_fh), 1) = 1 if $client_fh;
    vec($rin, fileno($server_fh), 1) = 1 if $server_fh;

    my $nfound = select(my $rout = $rin, undef, undef, undef);
    defined($nfound)
	or die "Select failed: $!";
    $nfound
	or die "Select timeout";

    if ($client_fh && vec($rout, fileno($client_fh), 1)) {
	undef $!;
	while (<$client_fh>) {
	    print $_ if $opts{v};
	    # handle short reads
	    $_ = $client_prev. $_ if defined($client_prev);
	    $client_prev = /\n$/ ? undef : $_;
	    print $_ if !$opts{v} && /^(send|recv):.*\n/;
	}
	unless ($!{EWOULDBLOCK}) {
	    close($client_fh) or die $! ?
		"Close pipe from client '@client_cmd' failed: $!" :
		"Client '@client_cmd' failed: $?";
	    undef $client_fh;
	}
    }

    if ($server_fh && vec($rout, fileno($server_fh), 1)) {
	undef $!;
	while (<$server_fh>) {
	    print $_ if $opts{v};
	    # handle short reads
	    $_ = $server_prev. $_ if defined($server_prev);
	    $server_prev = /\n$/ ? undef : $_;
	    print $_ if !$opts{v} && /^(send|recv):.*\n/;
	}
	unless ($!{EWOULDBLOCK}) {
	    close($server_fh) or die $! ?
		"Close pipe from server '@server_cmd' failed: $!" :
		"Server '@server_cmd' failed: $?";
	    undef $server_fh;
	}
    }
}

exit;
