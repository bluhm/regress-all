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
getopts('d:h:P:ps:v', \%opts) or do {
    print STDERR <<"EOF";
usage: net.pl [-pv] [-d date] -h host [-P patch] [-s setup] [test ...]
    -d date	set date string and change to sub directory, may be current
    -h host	user and host for network link test, user defaults to root
    -P patch	apply patch to clean kernel source
    -s setup	setup mode: build install upgrade keep kernel reboot tools
		cvs-build cvs-kernel
    -p		power down after testing
    -v		verbose
    test ...	test mode: all, fragment, icmp, ipopts, pathmtu, tcp, udp
EOF
    exit(2);
};
$opts{h} or die "No -h specified";
!$opts{d} || $opts{d} =~ /^(current|latest|latest-\w+)$/ || str2time($opts{d})
    or die "Invalid -d date '$opts{d}'";
my $date = $opts{d} || $now;
my $patch = $opts{P};

my %allmodes;
@allmodes{qw(build install upgrade keep kernel reboot tools
    cvs-build cvs-kernel)} = ();
!$opts{s} || exists $allmodes{$opts{s}}
    or die "Unknown setup mode '$opts{s}'";
my %setupmode;
$setupmode{$_} = 1 foreach split(/-/, $opts{s} || "");

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
$resultdir = "$resultdir/$date";
unless ($opts{d}) {
    mkdir $resultdir
	or die "Make directory '$resultdir' failed: $!";
}
if ($patch) {
    my $patchdir = "patch-".
	join(',', map { s,\.[^/]*,,; basename($_) } split(/,/, $patch));
    $resultdir = mkdir_num("$resultdir/$patchdir");
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
(my $host = $opts{h}) =~ s/.*\@//;

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
setup_hosts(patch => $patch, mode => \%setupmode)
    if $patch || !($setupmode{keep} || $setupmode{reboot});
powerup_hosts() if $setupmode{keep} && !$setupmode{reboot};
reboot_hosts() if $setupmode{reboot};
collect_version();
setup_html();

# run network link tests remotely

chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

my @sshcmd = ('ssh', $opts{h}, 'perl', '/root/netlink/netlink.pl');
push @sshcmd, '-e', "/root/netlink/env-$host.sh", '-v', keys %testmode;
logcmd(@sshcmd);

# get result and logs

collect_result("$opts{h}:/root/netlink");

collect_dmesg();
setup_html();
powerdown_hosts(patch => $patch) if $opts{p};

# create html output

chdir($netlinkdir)
    or die "Change directory to '$netlinkdir' failed: $!";

setup_html(date => 1);

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
