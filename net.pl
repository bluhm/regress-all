#!/usr/bin/perl

# Copyright (c) 2018-2024 Alexander Bluhm <bluhm@genua.de>
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
use List::Util qw(pairkeys);
use POSIX;

use lib dirname($0);
use Logcmd;
use Hostctl;

my $now = strftime("%FT%TZ", gmtime);

my $scriptname = "$0 @ARGV";

my @allifaces = qw(bnxt em igc ix ixl);
my @allmodifymodes = qw(none jumbo nolro nopf notso);
my @allpseudos = qw(none bridge carp gif veb vlan);
my @allsetupmodes = (qw(build install upgrade sysupgrade keep kernel reboot
    tools), "cvs,build", "cvs,kernel");
my @alltestmodes = qw(all fragment icmp tcp udp splice);

my %opts;
getopts('b:c:d:D:h:i:m:N:P:ps:v', \%opts) or do {
    print STDERR <<"EOF";
usage: net.pl [-pv] [-b kstack] [-c pseudo] [-d date] [-D cvsdate] -h host
	[-i iface] [-m modify] [-N repeat] [-P patch] [-s setup] [test ...]
#    -b kstack	measure with btrace and create kernel stack map
    -c pseudo	list of pseudo network devices: all @allpseudos
    -d date	set date string and change to sub directory, may be current
    -D cvsdate	update sources from cvs to this date
    -h host	user and host for network link test, user defaults to root
    -i iface	list of interfaces, may contain number: all @allifaces
    -m modify	list of modify modes: all @allmodifymodes
    -N repeat	number of build, reboot, test repetitions per step
    -P patch	apply patch to clean kernel source
    -s setup	setup mode: @allsetupmodes
    -p		power down after testing
    -v		verbose
    test ...	test mode: @alltestmodes
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
my $modify = $opts{m};
my $pseudo = $opts{c};
my $repeat = $opts{N};
!$repeat || $repeat >= 1
    or die "Repeat -N repeat must be positive integer";
my $btrace = $opts{b};
$btrace && $btrace ne "kstack"
    and die "Btrace -b '$btrace' not supported, use 'kstack'";

!$opts{s} || grep { $_ eq $opts{s} } @allsetupmodes
    or die "Unknown setup mode '$opts{s}'";
my %setupmode;
$setupmode{$_} = 1 foreach split(/,/, $opts{s} || "");

keys %setupmode && $opts{d}
    and die "Cannot combine -s setup and -d date";
keys %setupmode && $patch
    and die "Cannot combine -s setup and -P patch";

my %testmode;
foreach my $mode (@ARGV) {
    grep { $_ eq $mode } @alltestmodes
	or die "Unknown test mode '$mode'";
    $testmode{$mode} = 1;
}

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

delete $ENV{SKIP_IF};
environment("$netlinkdir/bin/env-$host.sh");
my $skip_if = $ENV{SKIP_IF} || "";
$skip_if =~ s/,/|/g;

# setup remote machines

usehosts(bindir => "$netlinkdir/bin", htmlprog => "netlink", date => $date,
    host => $opts{h}, verbose => $opts{v});

# do not run end block until initialized, date may change later
my $odate = $date;
END {
    if ($odate) {
	my @cmd = ("$netlinkdir/bin/bsdcons.pl", '-h', $opts{h}, '-d', $odate);
	system(@cmd);
    }
    if ($netlinkdir) {
	my @cmd = ("$netlinkdir/bin/setup-html.pl");
	system(@cmd);
	@cmd = ("$netlinkdir/bin/running-html.pl");
	system(@cmd);
    }
};
$resultdir .= "/$cvsdate" if $cvsdate;
-d $resultdir || mkdir $resultdir
    or die "Make directory '$resultdir' failed: $!";
if ($patch) {
    my $patchdir = "patch-".
	join(',', map { s,\.[^/]*,,; basename($_) } split(/,/, $patch));
    $resultdir = mkdir_num("$resultdir/$patchdir");
}
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";
if (keys %setupmode) {
    if ($patch || !($setupmode{keep} || $setupmode{reboot})) {
	setup_hosts(patch => $patch, mode => \%setupmode);
    } elsif (!$setupmode{reboot}) {
	powerup_hosts(cvsdate => $cvsdate, patch => $patch);
    } else {
	reboot_hosts(cvsdate => $cvsdate, patch => $patch);
    }
    collect_version();
    setup_html();
} else {
    powerup_hosts(cvsdate => $cvsdate, patch => $patch);
}
if (($cvsdate && ! -f "$resultdir/cvsbuild-$host.log") || $patch) {
    cvsbuild_hosts(cvsdate => $cvsdate, patch => $patch);
    collect_version();
    setup_html();
} elsif ($cvsdate &&
    !($patch || $iface || $modify || $pseudo || $repeat || $btrace)) {
	die "Directory '$resultdir' exists and no subdir given";
}

collect_version();

my @ifaces;
if ($iface) {
    open($fh, '<', "dmesg-boot-$host.txt")
	or die "Open 'dmesg-boot-$host.txt' for reading failed: $!";
    my @dmesg;
    while (<$fh>) {
	# parse only latest copy of dmesg from current boot
	undef @dmesg if /^OpenBSD/;
	push @dmesg, $_;
    }
    $iface = join(",", @allifaces) if $iface eq "all";
    foreach my $if (split(/,/, $iface)) {
	my ($iftype, $num) = $if =~ /^([a-z]+)([0-9]+)?$/
	    or die "Invalid interface '$if'";
	grep { $_ eq $iftype } @allifaces
	    or die "Unknown interface '$if'";
	unless (grep { /^$iftype\d+ at / } @dmesg) {
	    if ($opts{i} eq "all") {
		next;
	    } else {
		die "Interface type '$if' does not exist in dmesg";
	    }
	}
	my %ifnums;
	@ifnums{
	    map { /^$iftype(\d+)$/ }
	    grep { ! /^($skip_if)$/ }
	    map { /^($iftype\d+) at / ? $1 : () }
	    @dmesg} = ();
	foreach my $ifnum (defined($num) ? ($num + 0) :
	    pairkeys sort { $a <=> $b } keys %ifnums) {
	    if (($iftype.($ifnum + 0)) =~ /^($skip_if)$/ ||
		($iftype.($ifnum + 1)) =~ /^($skip_if)$/) {
		die "Cannot use inferface '$if', conflicts skip interface";
	    }
	    if (!exists($ifnums{$ifnum + 0}) || !exists($ifnums{$ifnum + 1})) {
		if (defined($num)) {
		    die "Interface pair '$if' does not exist in dmesg";
		} else {
		    next;
		}
	    }
	    push @ifaces, "iface-$iftype$ifnum";
	}
    }
    @ifaces or die "No suitable interfaces in '$iface' found";
}
my @modifies;
if ($modify) {
    $modify = join(",", @allmodifymodes) if $modify eq "all";
    @modifies = split(/,/, $modify);
    foreach my $md (@modifies) {
	grep { $_ eq $md } @allmodifymodes
	    or die "Unknown modify mode '$md'";
	$md = "modify-$md";
    }
}
my @pseudos;
if ($pseudo) {
    $pseudo = join(",", @allpseudos) if $pseudo eq "all";
    @pseudos = split(/,/, $pseudo);
    foreach my $ps (@pseudos) {
	grep { $_ eq $ps } @allpseudos
	    or die "Unknown pseudo network device '$ps'";
	$ps = "pseudo-$ps";
    }
}
my @repeats;
push @repeats, map { sprintf("%03d", $_) } (0 .. $repeat - 1)
    if $repeat;
# after all regular repeats, make one with btrace turned on
push @repeats, "btrace-$btrace" if $btrace;

setup_html(date => 1);

foreach my $modifydir (@modifies ? @modifies : ".") {
    if (@modifies) {
	-d $modifydir || mkdir $modifydir
	    or die "Make directory '$modifydir' failed: $!";
	chdir($modifydir)
	    or die "Change directory to '$modifydir' failed: $!";
    }

    foreach my $ifacedir (@ifaces ? @ifaces : ".") {
	if (@ifaces) {
	    -d $ifacedir || mkdir $ifacedir
		or die "Make directory '$ifacedir' failed: $!";
	    chdir($ifacedir)
		or die "Change directory to '$ifacedir' failed: $!";
	}

	foreach my $pseudodir (@pseudos ? @pseudos : ".") {
	    if (@pseudos) {
		-d $pseudodir || mkdir $pseudodir
		    or die "Make directory '$pseudodir' failed: $!";
		chdir($pseudodir)
		    or die "Change directory to '$pseudodir' failed: $!";
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

		my @sshcmd = ('ssh', $opts{h}, 'perl',
		    '/root/netlink/netlink.pl');
		push @sshcmd, '-c', $1 if $pseudodir =~ /-(.+)/;
		push @sshcmd, '-b', $btrace if $repeatdir =~ /^btrace-/;
		push @sshcmd, '-e', "/root/netlink/env-$host.sh";
		push @sshcmd, '-i', $1 if $ifacedir =~ /-(.+)/;
		push @sshcmd, '-m', $1 if $modifydir =~ /-(.+)/;
		push @sshcmd, '-v' if $opts{v};
		push @sshcmd, keys %testmode;
		logcmd(@sshcmd);

		# get result and logs

		collect_result("$opts{h}:/root/netlink");
		wait_html();
		collect_version();
		setup_html();
		current_html();

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
    if (@modifies) {
	chdir("..")
	    or die "Change directory to '..' failed: $!";
    }
}

collect_dmesg();
powerdown_hosts(cvsdate => $cvsdate, patch => $patch) if $opts{p};

# create html output

chdir($netlinkdir)
    or die "Change directory to '$netlinkdir' failed: $!";

wait_html();
setup_html(date => 1);

unlink("results/latest-$host");
symlink($date, "results/latest-$host")
    or die "Make symlink 'results/latest-$host' failed: $!";
unlink("results/latest");
symlink($date, "results/latest")
    or die "Make symlink 'results/latest' failed: $!";

my @cmd = ("bin/netlink-html.pl");
push @cmd, "-v" if $opts{v};
runcmd(@cmd, "-l");
runcmd(@cmd, "-h", $host);
runcmd(@cmd);

$now = strftime("%FT%TZ", gmtime);
logmsg("Script '$scriptname' finished at $now.\n");

exit;

# parse shell script that is setting environment for some tests
# FOO=bar
# FOO="bar"
# export FOO=bar
# export FOO BAR
sub environment {
    my $file = shift;

    open(my $fh, '<', $file)
	or die "Open '$file' for reading failed: $!";
    while (<$fh>) {
	chomp;
	s/#.*$//;
	s/\s+$//;
	s/^export\s+(?=\w+=)//;
	s/^export\s+\w+.*//;
	next if /^$/;
	if (/^(\w+)=(\S+)$/ or /^(\w+)="([^"]*)"/ or /^(\w+)='([^']*)'/) {
	    $ENV{$1}=$2;
	} else {
	    die "Unknown environment line in '$file': $_";
	}
    }
}

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
