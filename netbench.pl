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
getopts('a:B:b:c:l:P:s:t:v', \%opts) or do {
    print STDERR <<"EOF";
usage: netbench.pl [-v] -a address [-B bitrate] [-b bufsize] [-c client]
	[-l length] [-P packetrate] [-s server] [-t timeout] [test ...]
    -a address	IP address for packet destination, comma repeat count
    -B bitrate	bits per seconds send rate
    -b bufsize	set size of send and receive buffer
    -c client	connect via ssh to start packet generator
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
    or die "IP Address required";
$addr =~ /^([0-9]+\.[0-9.]+)(?:,(\d+))?$/ ||
    $addr =~ /^([0-9a-fA-F:]+)(?:,(\d+))?$/
    or die "Address must be IPv4 or IPv6";
$addr = $1;
my $repeat = $2;
my $client_ssh = $opts{c};
my $server_ssh = $opts{s};
my $timeout = $opts{t} || 1;

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

my @addrs;
if ($repeat) {
    my ($net, $sep, $host) = $addr =~ /(.*)([.:])(.*)/;
    my $hostnum = $sep eq ':' ? hex($host || 0) : $host;
    foreach (1..$repeat) {
	$host = $sep eq ':' ? sprintf("%x", $hostnum) : $hostnum;
	push @addrs, "$net$sep$host";
	$hostnum++;
	$hostnum = $sep eq ':' ? ($hostnum & 0xffff) : ($hostnum & 0xff);
    }
} else {
    push @addrs, $addr;
}

my (@servers, @clients);
for (my $num = 0; $num < @addrs; $num++) {
    my $suffix = $repeat ? " $num" : "";
    my %server = (
	name	=> "server$suffix",
	ssh	=> $server_ssh,
	addr	=> $addrs[$num],
    );
    start_server(\%server);
    print "netbench$suffix: $server{addr} $server{port}\n" if $opts{v};

    my %client = (
	name	=> "client$suffix",
	ssh	=> $client_ssh,
	addr	=> $server{addr},
	port	=> $server{port},
    );
    push @servers, \%server;
    push @clients, \%client;
}

start_client($_) foreach (@clients);

set_nonblock($_) foreach (@clients, @servers);

select_output(@clients, @servers);

exit;

my %master;
sub start_server {
    my ($proc) = @_;

    my @cmd = ('udpbench');
    push @cmd, "-b$opts{b}" if defined($opts{b});
    push @cmd, "-l$opts{l}" if defined($opts{l});
    my $to = $timeout + ($repeat || 0) + 10;
    push @cmd, ("-t$to", '-p0', 'recv', $proc->{addr});
    unshift @cmd, ($proc->{ssh}) if $proc->{ssh};
    unshift @cmd, '-M' if $repeat && !$master{$proc->{ssh}}++;
    unshift @cmd, ('ssh', '-nT');
    $proc->{cmd} = \@cmd;

    open_pipe($proc);
}

sub start_client {
    my ($proc) = @_;

    my @cmd = ('udpbench');
    push @cmd, "-B$opts{B}" if defined($opts{B});
    push @cmd, "-b$opts{b}" if defined($opts{b});
    push @cmd, "-l$opts{l}" if defined($opts{l});
    push @cmd, "-P$opts{P}" if defined($opts{P});
    push @cmd, ("-t$timeout", "-p$proc->{port}", 'send', $proc->{addr});
    unshift @cmd, ($proc->{ssh}) if $proc->{ssh};
    unshift @cmd, '-M' if $repeat && !$master{$proc->{ssh}}++;
    unshift @cmd, ('ssh', '-nT') if $proc->{ssh};
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

sub select_output {
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
    }
    unless ($!{EWOULDBLOCK}) {
	close($proc->{fh}) or warn $! ?
	    "Close pipe from proc $proc->{name} '@{$proc->{cmd}}' failed: $!" :
	    "Proc $proc->{name} '@{$proc->{cmd}}' failed: $?";
	delete $proc->{fh};
    }
}
