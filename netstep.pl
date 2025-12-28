#!/usr/bin/perl

# Copyright (c) 2025 Alexander Bluhm <bluhm@genua.de>
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

my @allifaces = qw(bge bnxt em ice igc ix ixl re vio vmx);
my @allmodifymodes = qw(none direct jumbo nolro nopf notso);
my @allpseudos = qw(none bridge carp gif gif6 gre trunk veb vlan vxlan wg
    bridge+vlan vlan+bridge veb+vlan veb+vtag vlan+veb);
my @allkernelmodes = qw(align gap sort reorder reboot keep);
my @allsetupmodes = (qw(build install upgrade sysupgrade keep), "cvs,build");
my @alltestmodes = qw(all icmp tcp udp splice mcast mmsg iperf trex);

my %opts;
getopts('B:b:c:E:h:i:m:k:N:pr:S:s:v', \%opts) or do {
    print STDERR <<"EOF";
usage: netstep.pl [-pv] -B date [-b kstack] [-c pseudo] [-E date] -h host
	[-i iface] [-m modify] [-k kernel] [-N repeat] [-r release]
	[-S interval] [-s setup] [test ...]
    -B date	begin date, inclusive
    -b kstack	measure with btrace and create kernel stack map
    -c pseudo	list of pseudo network devices: all @allpseudos
    -E date	end date, inclusive
    -h host	user and host for network link test, user defaults to root
    -i iface	list of interfaces, may contain number: all @allifaces
    -m modify	list of modify modes: all @allmodifymodes
    -k kernel	kernel mode: @allkernelmodes
    -N repeat	number of build, reboot, test repetitions per step
    -p		power down after testing
    -r release	use release for install and cvs checkout, X.Y or current
    -S interval	step in sec, min, hour, day, week, month, year
    -s setup	setup mode: @allsetupmodes
    -v		verbose
    test ...	test mode: @alltestmodes
EOF
    exit(2);
};
my $btrace = $opts{b};
$btrace && $btrace ne "kstack"
    and die "Btrace -b '$btrace' not supported, use 'kstack'";
$opts{h} or die "No -h specified";
(my $host = $opts{h}) =~ s/.*\@//;
$opts{r} or die "No -r specified";
my $release;
if ($opts{r} ne "current") {
    ($release = $opts{r}) =~ /^\d+\.\d$/
	or die "Release '$opts{r}' must be major.minor format";
}
$opts{B} or die "No -B begin date";
my $begin = str2time($opts{B})
    or die "Invalid -B date '$opts{B}'";
my $end = str2time($opts{E} || $opts{B})
    or die "Invalid -E date '$opts{E}'";
my ($step, $unit);
if ($opts{S}) {
    if ($opts{S} eq "commit") {
	$unit = "commit";
    } else {
	($step, $unit) = $opts{S} =~ /^(\d+)(\w+)$/
	    or die "Invalid -S step '$opts{S}'";
	# unit syntax check
	add_step(0 , $step, $unit);
    }
} else {
    $step = $end - $begin;
    $unit = "sec";
}
$end >= $begin
    or die "Begin date '$opts{B}' before end date '$opts{E}'";
$end == $begin || $unit eq "commit" || $step > 0
    or die "Step '$opts{S}' cannot reach end date";

my $iface = $opts{i} || "all";
my $modify = $opts{m};
my $pseudo = $opts{c};
my $repeat = $opts{N};
!$repeat || $repeat >= 1
    or die "Repeat -N repeat must be positive integer";
!$opts{k} || grep { $_ eq $opts{k} } @allkernelmodes
    or die "Unknown kernel mode '$opts{k}'";

my %kernelmode;
$kernelmode{$opts{k}} = 1 if $opts{k};

!$opts{s} || grep { $_ eq $opts{s} } @allsetupmodes
    or die "Unknown setup mode '$opts{s}'";
my %setupmode;
$setupmode{$_} = 1 foreach split(/,/, $opts{s} || "");

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
-d $resultdir || mkdir $resultdir
    or die "Make directory '$resultdir' failed: $!";

# hierarchy: release date cvsdate iface pseudo repeat btrace

if ($release) {
    $resultdir .= "/$release";
    -d $resultdir || mkdir $resultdir
	or die "Make directory '$resultdir' failed: $!";
}
my $date = $now;
$resultdir .= "/$date";
mkdir $resultdir
    or die "Make directory '$resultdir' failed: $!";
unlink("results/current");
symlink("$date", "results/current")
    or die "Make symlink 'results/current' failed: $!";
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

createlog(file => "net.log", verbose => $opts{v});
logmsg("$now Script '$scriptname' started.\n");

open(my $fh, '>', "netconf.txt")
    or die "Open 'netconf.txt' for writing failed: $!";
print $fh "ARGUMENTS @ARGV\n";
print $fh "HOST $opts{h}\n";
print $fh "RELEASE $opts{r}\n";
print $fh strftime("BEGIN %FT%TZ\n", gmtime($begin));
print $fh strftime("END %FT%TZ\n", gmtime($end));
print $fh "STEP ", $unit eq "commit" ? $unit : "$step $unit", "\n";
print $fh "REPEAT ", $repeat || "", "\n";
print $fh "KERNELMODES ", join(" ", sort keys %kernelmode), "\n";
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
if (!$setupmode{keep}) {
    setup_hosts(release => $release, mode => \%setupmode);
} else {
    powerup_hosts(release => $release);
}
collect_version();
setup_html();

# update in single steps

my @steps;
if ($unit eq "commit") {
    my %times;
    @times{(get_commits($begin, $end), get_quirks($begin, $end))} = ();
    @steps = sort keys %times;
    unshift @steps, $begin unless @steps && $steps[0] == $begin;
    push @steps, $end unless $steps[-1] == $end;
} else {
    for (my $current = $begin; $current < $end;
	$current = add_step($current, $step, $unit)) {

	push @steps, $current;
    }
    # if next step does not hit the end exactly, do an additional test
    push @steps, $end;
}

setup_html(date => 1);

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
	    if (!$opts{i} || $opts{i} eq "all") {
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
# use repeats subdirs only if there are any
push @repeats, map { sprintf("%03d", $_) } (0 .. $repeat - 1) if $repeat;
# after all regular repeats, make one with btrace turned on
push @repeats, "btrace-$btrace.0" if $btrace;

my $allruns = @steps *
    (@modifies || 1) * (@ifaces || 1) * (@pseudos || 1) * (@repeats || 1);
my $run = 0;
foreach my $current (@steps) {
    chdir($netlinkdir)
	or die "Change directory to '$netlinkdir' failed: $!";

    my $cvsdate = strftime("%FT%TZ", gmtime($current));
    my $cvsdir = "results";
    $cvsdir .= "/$release" if $release;
    $cvsdir .= "/$date/$cvsdate";
    mkdir $cvsdir
	or die "Make directory '$cvsdir' failed: $!";
    chdir($cvsdir)
	or die "Change directory to '$cvsdir' failed: $!";
    my %cvsmode = %kernelmode;
    if ($kernelmode{keep}) {
	# cannot keep the kernel after building a new one
	delete $cvsmode{keep};
	$cvsmode{reboot} = 1;
    }
    cvsbuild_hosts(cvsdate => $cvsdate, release => $release,
	mode => \%cvsmode);
    collect_version();
    setup_html();

    foreach my $repeatdir (@repeats ? @repeats : ".") {
	if (@repeats) {
	    if ($repeatdir =~ /^btrace-/) {
		$repeatdir = mkdir_num($repeatdir);
	    } else {
		-d $repeatdir || mkdir $repeatdir
		    or die "Make directory '$repeatdir' failed: $!";
	    }
	    chdir($repeatdir) or die
		"Change directory to '$repeatdir' failed: $!";
	}

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

			logmsg sprintf("\nrun %d/%d %s %s %s %s %s\n\n",
			    ++$run, $allruns, $cvsdate,
			    $modifydir, $ifacedir, $pseudodir, $repeatdir);

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
	if (@repeats) {
	    # align and sort do not change kernel image randomly at each reboot.
	    # This has been done by cvsbuild_hosts(), avoid doing it again.
	    my %rebootmode = %kernelmode;
	    delete @rebootmode{qw(align sort)};

	    unless ($rebootmode{keep} ||
		$repeatdir eq $repeats[-1]) {
		    reboot_hosts(cvsdate => $cvsdate,
			repeatdir => $repeatdir,
			release => $release, mode => \%rebootmode);
	    }
	    collect_version();
	    setup_html();

	    chdir("..")
		or die "Change directory to '..' failed: $!";
	}
    }
}
collect_dmesg();
powerdown_hosts(release => $release) if $opts{p};
bsdcons_hosts(release => $release);
undef $odate;

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
# concurrent testruns on multiple hosts may fail when renaming
logeval { runcmd(@cmd, "-l") };
runcmd(@cmd, "-h", $host);
# do not create all page, it is too slow and too large
#runcmd(@cmd);

$now = strftime("%FT%TZ", gmtime);
logmsg("$now Script '$scriptname' finished.\n");

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
