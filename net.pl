#!/usr/bin/perl

# Copyright (c) 2018-2022 Alexander Bluhm <bluhm@genua.de>
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
getopts('b:c:d:D:h:i:N:P:ps:v', \%opts) or do {
    print STDERR <<"EOF";
usage: net.pl [-pv]  [-b kstack] [-c pseudo] [-d date] [-D cvsdate] -h host
	[-i iface] [-N repeat] [-P patch] [-s setup] [test ...]
#    -b kstack	measure with btrace and create kernel stack map
#    -c pseudo	ifconfig create pseudo network device
    -d date	set date string and change to sub directory, may be current
    -D cvsdate	update sources from cvs to this date
    -h host	user and host for network link test, user defaults to root
    -i iface	network interface
    -N repeat	number of build, reboot, test repetitions per step
    -P patch	apply patch to clean kernel source
    -s setup	setup mode: build install upgrade sysupgrade
		keep kernel reboot tools cvs-build cvs-kernel
    -p		power down after testing
    -v		verbose
    test ...	test mode: all, fragment, icmp, ipopts, pathmtu, tcp, udp
EOF
    exit(2);
};
$opts{h} or die "No -h specified";
(my $host = $opts{h}) =~ s/.*\@//;
!$opts{d} || $opts{d} =~ /^(current|latest|latest-\w+)$/ || str2time($opts{d})
    or die "Invalid -d date '$opts{d}'";
my $date = $opts{d} || $now;
my $cvsdate;
if ($opts{D}) {
    my $cd = str2time($opts{D})
	or die "Invalid -D cvsdate '$opts{D}'";
    $cvsdate = strftime("%FT%TZ", gmtime($cd));
}
my $patch = $opts{P};
my $iface = $opts{i};
my $pseudo = $opts{c};
my $repeat = $opts{N};
!$repeat || $repeat >= 1
    or die "Repeat -N repeat must be positive integer";
my $btrace = $opts{b};
$btrace && $btrace ne "kstack"
    and die "Btrace -b '$btrace' not supported, use 'kstack'";

my %allmodes;
@allmodes{qw(build install upgrade sysupgrade keep kernel reboot tools
    cvs-build cvs-kernel)} = ();
!$opts{s} || exists $allmodes{$opts{s}}
    or die "Unknown setup mode '$opts{s}'";
my %setupmode;
$setupmode{$_} = 1 foreach split(/,/, $opts{s} || "");

keys %setupmode && $opts{d}
    and die "Cannot combine -s setup and -d date";
keys %setupmode && $patch
    and die "Cannot combine -s setup and -P patch";

undef %allmodes;
@allmodes{qw(
    all fragment icmp ipopts pathmtu tcp udp
)} = ();
my %testmode = map {
    die "Unknown test mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV;

# better get an errno than random kill by SIGPIPE
$SIG{PIPE} = 'IGNORE';

my $netlinkdir = dirname($0). "/..";
chdir($netlinkdir)
    or die "Change directory to '$netlinkdir' failed: $!";
$netlinkdir = getcwd();
my $resultdir = "$netlinkdir/results";

if ($date && $date =~ /^(current|latest|latest-\w+)$/) {
    my $current = readlink("$resultdir/$date")
	or die "Read link '$resultdir/$date' failed: $!";
    -d "$resultdir/$current"
	or die "Test directory '$resultdir/$current' failed: $!";
    $date = basename($current);
}

# hierarchy: date cvsdate patch iface pseudo repeat btrace

$resultdir .= "/$date";
unless ($opts{d}) {
    mkdir $resultdir
	or die "Make directory '$resultdir' failed: $!";
    unlink("results/current");
    symlink("$date", "results/current")
	or die "Make symlink 'results/current' failed: $!";
}
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

createlog(file => "net.log", verbose => $opts{v});
logmsg("Script '$scriptname' started at $now.\n");

open(my $fh, '>', "netconf.txt")
    or die "Open 'netconf.txt' for writing failed: $!";
print $fh "ARGUMENTS @ARGV\n";
print $fh "HOST $opts{h}\n";
print $fh "SETUPMODES ", join(" ", sort keys %setupmode), "\n";
print $fh "TESTMODES ", join(" ", sort keys %testmode), "\n";
close($fh);

# setup remote machines

usehosts(bindir => "$netlinkdir/bin", date => $date,
    host => $opts{h}, verbose => $opts{v});

# do not run end block until initialized, date may change later
my $odate = $date;
END {
    if ($odate) {
	my @cmd = ("$netlinkdir/bin/bsdcons.pl", '-h', $opts{h}, '-d', $odate);
	system(@cmd);
	@cmd = ("$netlinkdir/bin/setup-html.pl");
	system(@cmd);
	@cmd = ("$netlinkdir/bin/running-html.pl");
	system(@cmd);
    }
};
if (keys %setupmode) {
    setup_hosts(patch => $patch, mode => \%setupmode)
	if $patch || !($setupmode{keep} || $setupmode{reboot});
    powerup_hosts() if $setupmode{keep} && !$setupmode{reboot};
    reboot_hosts() if $setupmode{reboot};
    collect_version();
    setup_html();
}
$resultdir .= "/$cvsdate" if $cvsdate;
if (($cvsdate && ! -f "$resultdir/cvsbuild-$host.log") || $patch) {
    -d $resultdir || mkdir $resultdir
	or die "Make directory '$resultdir' failed: $!";
    if ($patch) {
	my $patchdir = "patch-".
	    join(',', map { s,\.[^/]*,,; basename($_) } split(/,/, $patch));
	$resultdir = mkdir_num("$resultdir/$patchdir");
    }
    chdir($resultdir)
	or die "Change directory to '$resultdir' failed: $!";
    cvsbuild_hosts(cvsdate => $cvsdate, patch => $patch);
    collect_version();
    setup_html();
} elsif ($cvsdate && !($patch || $iface || $pseudo || $repeat || $btrace)) {
	die "Directory '$resultdir' exists and no subdir given";
}

chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";
collect_version();

my @ifaces;
if ($iface) {
    $iface =~ s/^all$/em,igc,ix,ixl/;
    @ifaces = map { "iface-$_" } split(/,/, $iface);
}
my @pseudos;
if ($pseudo) {
    $pseudo =~ s/^all$/aggr,bridge,carp,trunk,veb,vlan/;
    @pseudos = map { "pseudo-$_" } split(/,/, $pseudo);
}
my @repeats;
push @repeats, map { sprintf("%03d", $_) } (0 .. $repeat - 1)
    if $repeat;
# after all regular repeats, make one with btrace turned on
push @repeats, "btrace-$btrace" if $btrace;

foreach my $ifacedir (@ifaces ? @ifaces : ".") {
    if (@ifaces) {
	-d $ifacedir || mkdir $ifacedir
	    or die "Make directory '$ifacedir' failed: $!";
	chdir($ifacedir)
	    or die "Change directory to '$ifacedir' failed: $!";
	($iface = $ifacedir) =~ s/.*-//;
    }

    foreach my $pseudodir (@pseudos ? @pseudos : ".") {
	if (@pseudos) {
	    -d $pseudodir || mkdir $pseudodir
		or die "Make directory '$pseudodir' failed: $!";
	    chdir($pseudodir)
		or die "Change directory to '$pseudodir' failed: $!";
	    ($pseudo = $pseudodir) =~ s/.*-//;
	}

	foreach my $repeatdir (@repeats ? @repeats : ".") {
	    if (@repeats) {
		if ($repeatdir =~ /^btrace-/) {
		    $repeatdir = mkdir_num($repeatdir);
		} else {
		    -d $repeatdir || mkdir $repeatdir
			or die "Make directory '$repeatdir' failed: $!";
		}
		chdir($repeatdir)
		    or die "Change directory to '$repeatdir' failed: $!";
	    }

	    # run network link tests remotely

	    my @sshcmd = ('ssh', $opts{h}, 'perl', '/root/netlink/netlink.pl');
	    push @sshcmd, '-c', $pseudo if $pseudo;
	    push @sshcmd, '-b', $btrace if $repeatdir =~ /^btrace-/;
	    push @sshcmd, '-e', "/root/netlink/env-$host.sh";
	    push @sshcmd, '-i', $iface if $iface;
	    push @sshcmd, '-v' if $opts{v};
	    push @sshcmd, keys %testmode;
	    logcmd(@sshcmd);

	    # get result and logs

	    collect_result("$opts{h}:/root/netlink");
	    collect_version();
	    setup_html();

	    if (@repeats) {
		chdir("..")
		    or die "Change directory to '..' failed: $!";
	    }
	}
	if (@pseudos) {
	    chdir("..")
		or die "Change directory to '..' failed: $!";
	}
    }
    if (@ifaces) {
	chdir("..")
	    or die "Change directory to '..' failed: $!";
    }
}

collect_dmesg();
powerdown_hosts(cvsdate => $cvsdate, patch => $patch) if $opts{p};

# create html output

chdir($netlinkdir)
    or die "Change directory to '$netlinkdir' failed: $!";

setup_html(date => 1);

unlink("results/latest-$host");
symlink($date, "results/latest-$host")
    or die "Make symlink 'results/latest-$host' failed: $!";
unlink("results/latest");
symlink($date, "results/latest")
    or die "Make symlink 'results/latest' failed: $!";

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
