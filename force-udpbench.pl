#!/usr/bin/perl -T
# Allow ssh to run local udpbench command, but only udpbench.
# pkill udpbench is also allowed.

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

use strict;
use warnings;
use Getopt::Std;

my $sshcmd = $ENV{SSH_ORIGINAL_COMMAND}
    or die "No SSH_ORIGINAL_COMMAND in environment.\n";
$sshcmd =~ /^([ 0-9A-Za-z.:_-]+)$/
    or die "Invalid characters in ssh command.\n";
my @args = split(" ", $1)
    or die "Split ssh command failed.\n";
if (@args == 2 && $args[0] eq "pkill" && $args[1] eq "udpbench") {
    $ENV{PATH} = "/bin:/usr/bin:/usr/local/bin";
    exec { 'pkill' } @args;
    die "Exec 'pkill' failed: $!\n";
}
$args[0] eq "udpbench"
    or die "Only 'udpbench' command allowed.\n";

# filter out remote and divert options
my %opts;
@ARGV = @args;
shift;
getopts('b:d:l:p:t:', \%opts)
    or die "Parsing udpbench options failed.\n";
@ARGV >= 1 && $ARGV[0] =~ /^(send|recv)$/
    or die "Action send or recv for udpbench must be present.\n";
@ARGV < 2 || $ARGV[1] =~ /^10\.[0-9.]+$/ ||
    $ARGV[1] =~ /^f[cd][0-9a-f]{2}:[0-9a-f:]+$/i
    or die "Host address for udpbench must be local.\n";
@ARGV <= 2
    or die "Too many arguments for udpbench.\n";

$ENV{PATH} = "/bin:/usr/bin:/usr/local/bin";
exec { 'udpbench' } @args;
die "Exec 'udpbench' failed: $!\n";
