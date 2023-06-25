#!/usr/bin/perl -T
# restrict ssh commands

# Copyright (c) 2021-2022 Alexander Bluhm <bluhm@openbsd.org>
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

# Allow ssh to run iperf3 or udpbench, but only with safe arguments.
# Start pkill with iperf3 or udpbench argument is also allowed.
# Used in authorized_keys restrict,command="force-ssh.pl iperf3 udpbench".

use strict;
use warnings;
use Getopt::Std;

# Arguments of force-ssh.pl specify which commands are allowed.
my %filter;
foreach (@ARGV) {
    /^([0-9A-Za-z]+)$/
	or die "Invalid characters in force argument.\n";
    $filter{iperf3} = \&filter_iperf3 if /^iperf3$/;
    $filter{tcpbench} = \&filter_tcpbench if /^tcpbench$/;
    $filter{udpbench} = \&filter_udpbench if /^udpbench$/;
    $filter{timeout} = \&filter_timeout if /^timeout$/;
}
my @allowed = sort keys %filter;

# Environment from ssh tells which command line the user wants to run.
my $sshcmd = $ENV{SSH_ORIGINAL_COMMAND}
    or die "No SSH_ORIGINAL_COMMAND in environment.\n";
$sshcmd =~ /^([ 0-9A-Za-z.:_-]+)$/
    or die "Invalid characters in ssh command.\n";
my @args = split(" ", $1)
    or die "Split ssh command failed.\n";
my $cmd = $args[0];

if ($cmd eq "pkill") {
    # Run pkill with allowed command if the user wanted to kill.
    @args == 2
	or die "Only one argument for pkill allowed.\n";
    $filter{$args[1]}
	or die "Only pkill '@allowed' allowed.\n";
} else {
    # Filter untrusted options of iperf3, tcpbench, or udpbench.
    my $sub = $filter{$cmd}
	or die "Only command '@allowed' allowed.\n";
    $sub->(@args);
}

$ENV{PATH} = "/bin:/usr/bin:/usr/local/bin";
exec { $cmd } @args;
die "Exec '$cmd' failed: $!\n";

# Filter out file access options.
sub filter_iperf3 {
    shift;
    local @ARGV = @_;
    my %opts;
    getopts('p:f:i:A:B:V:J:d:v:hsD1c:ub:t:n:k:l:P:Rw:M:N46S:L:Z:O:T:C:',
	\%opts)
	or die "Parsing iperf3 options failed.\n";
    if ($opts{c}) {
	$opts{c} =~ /^10\.[0-9.]+$/ ||
	    $opts{c} =~ /^f[cd][0-9a-f]{2}:[0-9a-f:]+$/i
	    or die "Server address for iperf3 must be local.\n";
    } elsif ($opts{s}) {
    } else {
	die "Client or server option for iperf3 must be present.\n";
    }
    @ARGV <= 0
	or die "Too many arguments for iperf3.\n";
}

# Filter out debug, kernel, unix, and rtable options.
sub filter_tcpbench {
    shift;
    local @ARGV = @_;
    my %opts;
    getopts('46b:B:n:p:Rr:sS:t:T:uv', \%opts)
	or die "Parsing tcpbench options failed.\n";
    @ARGV < 1 || $ARGV[0] =~ /^10\.[0-9.]+$/ ||
	$ARGV[0] =~ /^f[cd][0-9a-f]{2}:[0-9a-f:]+$/i
	or die "Host address for tcpbench must be local.\n";
    @ARGV <= 1
	or die "Too many arguments for tcpbench.\n";
}

# Filter out remote and divert options.
sub filter_udpbench {
    shift;
    local @ARGV = @_;
    my %opts;
    getopts('B:b:Dd:Hi:l:m:N:P:p:t:', \%opts)
	or die "Parsing udpbench options failed.\n";
    @ARGV >= 1 && $ARGV[0] =~ /^(send|recv)$/
	or die "Action send or recv for udpbench must be present.\n";
    @ARGV < 2 || $ARGV[1] =~ /^10\.[0-9.]+$/ ||
	$ARGV[1] =~ /^f[cd][0-9a-f]{2}:[0-9a-f:]+$/i
	or die "Host address for udpbench must be local.\n";
    @ARGV <= 2
	or die "Too many arguments for udpbench.\n";
}

# Filter timeout duration.
sub filter_timeout {
    my $cmd = shift;
    delete $filter{$cmd};
    @allowed = sort keys %filter;

    my $duration = shift;
    defined($duration) && $duration =~ /^\d+$/
	or die "Numeric duration for timeout must be present.\n";

    my @args = @_
	or die "Missing command for timeout.\n";
    $cmd = $args[0];
    # Filter untrusted options of iperf3, tcpbench, or udpbench.
    my $sub = $filter{$cmd}
	or die "Only command '@allowed' allowed.\n";
    $sub->(@args);
}
