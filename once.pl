#!/usr/bin/perl

# Copyright (c) 2018-2019 Alexander Bluhm <bluhm@genua.de>
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
use Date::Parse;
use File::Basename;
use Getopt::Std;
use POSIX;

use lib dirname($0);
use Logcmd;
use Hostctl;

my $scriptname = "$0 @ARGV";

my %opts;
getopts('D:h:k:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] [-D cvsdate] -h host [-k kernel] [test ...]
    -D cvsdate	update sources from cvs to this date
    -h host	user and host for performance test, user defaults to root
    -k kernel	kernel mode: align, gap, sort, reorder, reboot, keep
    -v		verbose
    test ...	test mode: all, net, tcp, udp, make, fs, iperf, tcpbench,
		udpbench, iperftcp, iperfudp, net4, tcp4, udp4, iperf4,
		tcpbench4, udpbench4, iperftcp4, iperfudp4, net6, tcp6,
		udp6, iperf6, tcpbench6, udpbench6, iperftcp6, iperfudp6,
		linuxnet, linuxiperftcp4, linuxiperftcp6

EOF
    exit(2);
};
$opts{h} or die "No -h specified";
!$opts{D} || str2time($opts{D})
    or die "Invalid -D cvsdate '$opts{D}'";
my $cvsdate = $opts{D};

my %allmodes;
@allmodes{qw(align gap sort reorder reboot keep)} = ();
!$opts{k} || exists $allmodes{$opts{k}}
    or die "Unknown kernel mode '$opts{k}'";
my %kernelmode;
$kernelmode{$opts{k}} = 1 if $opts{k};

@allmodes{qw(all net tcp udp make fs iperf tcpbench udpbench iperftcp
    iperfudp net4 tcp4 udp4 iperf4 tcpbench4 udpbench4 iperftcp4 iperfudp4
    net6 tcp6 udp6 iperf6 tcpbench6 udpbench6 iperftcp6 iperfudp6
    linuxnet linuxiperftcp4 linuxiperftcp6)} = ();
my %testmode = map {
    die "Unknown test mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV;

# better get an errno than random kill by SIGPIPE
$SIG{PIPE} = 'IGNORE';

my $performdir = dirname($0). "/..";
chdir($performdir)
    or die "Chdir to '$performdir' failed: $!";
$performdir = getcwd();
my $resultdir = "results";
chdir($resultdir)
    or die "Chdir to '$resultdir' failed: $!";

createlog(file => "once.log", verbose => $opts{v});
my $date = strftime("%FT%TZ", gmtime);
logmsg("script '$scriptname' started at $date\n");

# setup remote machines

usehosts(bindir => "$performdir/bin", host => $opts{h}, verbose => $opts{v});
(my $host = $opts{h}) =~ s/.*\@//;

cvsbuild_hosts(cvsdate => $cvsdate, mode => \%kernelmode)
    unless $kernelmode{keep};
collect_version();

# run performance tests remotely

my @sshcmd = ('ssh', $opts{h}, 'perl', '/root/perform/perform.pl',
    '-e', "/root/perform/env-$host.sh", '-v', keys %testmode);
logcmd(@sshcmd);

$date = strftime("%FT%TZ", gmtime);
logmsg("script '$scriptname' finished at $date\n");
