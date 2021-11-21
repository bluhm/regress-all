#!/usr/bin/perl

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
use Date::Parse;
use File::Basename;
use Getopt::Std;
use POSIX;

use lib dirname($0);
use Logcmd;
use Hostctl;

my $now = strftime("%FT%TZ", gmtime);

my $scriptname = "$0 @ARGV";

my %opts;
getopts('b:d:D:h:k:N:P:r:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] [-b kstack] [-d date] [-D cvsdate] -h host [-k kernel]
    [-N repeat] [-P patch] [-r release] [test ...]
    -b kstack	measure with btrace and create kernel stack map
    -d date	set date string and change to sub directory, may be current
    -D cvsdate	update sources from cvs to this date
    -h host	user and host for performance test, user defaults to root
    -k kernel	kernel mode: align, gap, sort, reorder, reboot, keep
    -N repeat	number of build, reboot, test repetitions per step
    -P patch	apply patch to clean kernel source
    -r release	change to release sub directory
    -v		verbose
    test ...	test mode: all, net, tcp, udp, make, fs, iperf, tcpbench,
		udpbench, iperftcp, iperfudp, net4, tcp4, udp4, iperf4,
		tcpbench4, udpbench4, iperftcp4, iperfudp4, net6, tcp6,
		udp6, iperf6, tcpbench6, udpbench6, iperftcp6, iperfudp6,
		linuxnet, linuxiperftcp4, linuxiperftcp6,
		forward, forward4, forward6,
		relay, relay4, relay6,
		ipsec, ipsec4, ipsec6, ipsec44, ipsec46, ipsec64, ipsec66

EOF
    exit(2);
};
my $btrace = $opts{b};
$btrace && $btrace ne "kstack"
    and die "Btrace -b '$btrace' not supported, use 'kstack'";
$opts{h} or die "No -h specified";
!$opts{d} || $opts{d} eq "current" || str2time($opts{d})
    or die "Invalid -d date '$opts{d}'";
my $date = $opts{d};
my $cvsdate;
if ($opts{D}) {
    my $cd = str2time($opts{D})
	or die "Invalid -D cvsdate '$opts{D}'";
    $cvsdate = strftime("%FT%TZ", gmtime($cd));
}
my $patch = $opts{P};
$cvsdate && $patch
    and die "Cannot combine -D cvsdate and -P patch";
my $release;
if ($opts{r} && $opts{r} ne "current") {
    ($release = $opts{r}) =~ /^\d+\.\d$/
	or die "Release '$opts{r}' must be major.minor format";
}

my $repeat = $opts{N};
!$repeat || $repeat >= 1 || $repeat =~ /^\d{3}$/
    or die "Repeat -N repeat must be positive integer or three digit subdir";
my %allmodes;
@allmodes{qw(align gap sort reorder reboot keep)} = ();
!$opts{k} || exists $allmodes{$opts{k}}
    or die "Unknown kernel mode '$opts{k}'";
my %kernelmode;
$kernelmode{$opts{k}} = 1 if $opts{k};

@allmodes{qw(
    all net tcp udp make fs iperf tcpbench udpbench iperftcp
    iperfudp net4 tcp4 udp4 iperf4 tcpbench4 udpbench4 iperftcp4 iperfudp4
    net6 tcp6 udp6 iperf6 tcpbench6 udpbench6 iperftcp6 iperfudp6
    linuxnet linuxiperftcp4 linuxiperftcp6
    forward forward4 forward6 relay relay4 relay6
    ipsec ipsec4 ipsec6 ipsec44 ipsec46 ipsec64 ipsec66
)} = ();
my %testmode = map {
    die "Unknown test mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV;

# better get an errno than random kill by SIGPIPE
$SIG{PIPE} = 'IGNORE';

my $performdir = dirname($0). "/..";
chdir($performdir)
    or die "Change directory to '$performdir' failed: $!";
$performdir = getcwd();
my $resultdir = "$performdir/results";
$resultdir .= "/$release" if $release;
if ($date && $date eq "current") {
    my $current = readlink("$resultdir/$date")
	or die "Read link '$resultdir/$date' failed: $!";
    -d "$resultdir/$current"
	or die "Test directory '$resultdir/$current' failed: $!";
    $date = basename($current);
    $release ||= dirname($current) if $date ne $current;
}
$resultdir = "$resultdir/$date" if $date;
if ($date && $cvsdate) {
    $resultdir = "$resultdir/$cvsdate";
    -d $resultdir || mkdir $resultdir
	or die "Make directory '$resultdir' failed: $!";
}
if ($patch) {
    if ($kernelmode{keep}) {
	$resultdir = chdir_num("$resultdir/patch-". basename($patch));
    } else {
	$resultdir = mkdir_num("$resultdir/patch-". basename($patch));
    }
}
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

createlog(file => "once.log", verbose => $opts{v});
logmsg("Script '$scriptname' started at $now.\n");

# setup remote machines

usehosts(bindir => "$performdir/bin", date => $date,
    host => $opts{h}, verbose => $opts{v});
(my $host = $opts{h}) =~ s/.*\@//;

# do not run end block until initialized, date may change later
my $odate = $date;
END {
    if ($odate) {
	my @cmd = ("$performdir/bin/bsdcons.pl", '-h', $opts{h}, '-d', $odate);
	push @cmd, "-r", $release if $release;
	system(@cmd);
	@cmd = ("$performdir/bin/setup-html.pl");
	system(@cmd);
	@cmd = ("$performdir/bin/running-html.pl");
	system(@cmd);
    }
};
cvsbuild_hosts(cvsdate => $cvsdate, patch => $patch, release => $release,
    mode => \%kernelmode) unless $kernelmode{keep};
collect_version();
setup_html();

my @repeats;
if ($repeat) {
    # use repeats subdirs only if there are any
    if ($repeat =~ /^\d{3}$/) {
	push @repeats, $repeat;
    } else {
	push @repeats, map { sprintf("%03d", $_) } (0 .. $repeat - 1);
    }
}
# after all regular repeats, make one with btrace turned on
push @repeats, "btrace-$btrace" if $btrace;

foreach my $repeatdir (@repeats ? @repeats : ".") {
    if (@repeats) {
	if ($repeatdir =~ /^btrace-/) {
	    $repeatdir = mkdir_num($repeatdir);
	} else {
	    mkdir $repeatdir
		or die "Make directory '$repeatdir' failed: $!";
	}
	chdir($repeatdir)
	    or die "Change directory to '$repeatdir' failed: $!";
    }

    # run performance tests remotely

    my @sshcmd = ('ssh', $opts{h}, 'perl', '/root/perform/perform.pl');
    push @sshcmd, '-b', $btrace if $repeatdir =~ /^btrace-/;
    push @sshcmd, '-e', "/root/perform/env-$host.sh", '-v', keys %testmode;
    logcmd(@sshcmd);

    # get result and logs

    collect_result("$opts{h}:/root/perform");

    if (@repeats) {
	unless ($kernelmode{keep} || $repeatdir eq $repeats[-1]) {
	    reboot_hosts(cvsdate => $cvsdate, repeat => $repeatdir,
		mode => \%kernelmode);
	}
	collect_version();
	setup_html();
	chdir("..")
	    or die "Change directory to '..' failed: $!";
    }
    collect_dmesg();
    setup_html();
}

# create html output

chdir($performdir)
    or die "Change directory to '$performdir' failed: $!";

if ($date) {
    setup_html(date => 1);
    my @cmd = ("bin/perform-html.pl", "-d", $date, "-n");
    push @cmd, "-r", $release if $release;
    push @cmd, "-v" if $opts{v};
    runcmd(@cmd);

    unlink("results/latest");
    symlink($date, "results/latest")
	or die "Make symlink 'results/latest' failed: $!";
}

$now = strftime("%FT%TZ", gmtime);
logmsg("Script '$scriptname' finished at $now.\n");

exit;

sub mkdir_num {
    my ($path) = @_;

    $path =~ s/\..*//;
    my $dir;
    for (my $suffix = 0; $suffix < 10; $suffix++) {
	$dir = "$path.$suffix";
	if (mkdir($dir)) {
	    return $dir;
	} else {
	    $!{EEXIST}
		or die "Make directory '$dir' failed: $!";
	}
    }
    die "Make directory '$dir' failed: $!";
}

sub chdir_num {
    my ($path) = @_;

    $path =~ s/\..*//;
    my $dir;
    for (my $suffix = 9; $suffix >= 0; $suffix--) {
	$dir = "$path.$suffix";
	if (chdir($dir)) {
	    return $dir;
	} else {
	    $!{ENOENT}
		or die "Change directory '$dir' failed: $!";
	}
    }
    die "Change directory '$dir' failed: $!";
}
