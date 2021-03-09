#!/usr/bin/perl -T
# Allow ssh to run any iperf3 client or server daemon, but only iperf3.

# Copyright (c) 2021 Alexander Bluhm <bluhm@openbsd.org>
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
use Getopt::Std;

my $sshcmd = $ENV{SSH_ORIGINAL_COMMAND}
    or die "No SSH_ORIGINAL_COMMAND in environment.\n";
$sshcmd =~ /^([ 0-9A-Za-z.:_-]+)$/
    or die "Invalid characters in ssh command.\n";
my @args = split(" ", $1)
    or die "Split ssh command failed.\n";
if (@args == 2 && $args[0] eq "pkill" && $args[1] eq "iperf3") {
    $ENV{PATH} = "/bin:/usr/bin:/usr/local/bin";
    exec { 'pkill' } @args;
    die "Exec 'pkill' failed: $!\n";
}
$args[0] eq "iperf3"
    or die "Only 'iperf3' command allowed.\n";

# filter out file access options
my %opts;
@ARGV = @args;
shift;
getopts('p:f:i:A:B:V:J:d:v:hsD1c:ub:t:n:k:l:P:Rw:M:N46S:L:Z:O:T:C:', \%opts)
    or die "Parsing iperf3 options failed.\n";
if ($opts{c}) {
    $opts{c} =~ /^10\.[0-9.]+$/ || $opts{c} =~ /^f[cd][0-9a-f]{2}:[0-9a-f:]+$/i
	or die "Server address must be local.\n";
} elsif ($opts{s}) {
} else {
    die "Client or server option for iperf3 must be present.\n";
}

$ENV{PATH} = "/bin:/usr/bin:/usr/local/bin";
exec { 'iperf3' } @args;
die "Exec 'iperf3' failed: $!\n";
