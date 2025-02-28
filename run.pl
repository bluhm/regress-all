#!/usr/bin/perl
# run regression tests on machine

# Copyright (c) 2016-2023 Alexander Bluhm <bluhm@genua.de>
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
use File::Basename;
use Getopt::Std;
use POSIX;

use lib dirname($0);
use Logcmd;
use Hostctl;

my $date = strftime("%FT%TZ", gmtime);
my $scriptname = "$0 @ARGV";

my @allsetupmodes = qw(build cvs install keep kernel reboot sysupgrade upgrade);

my %opts;
getopts('h:P:pv', \%opts) or do {
    print STDERR <<"EOF";
usage: run.pl [-pv] -h host [-P patch] setup ...
    -h host	user and host for make regress, user defaults to root
    -P patch	apply patch to clean kernel source
    -p		power down after testing
    -v		verbose
    setup ...	setup mode: @allsetupmodes
    build	build system from source /usr/src and reboot
    cvs		cvs update /usr/src and make obj
    install	install from snapshot
    keep	keep installed host as is, skip setup
    kernel	build kernel from source /usr/src/sys and reboot
    reboot	before running tests
    sysupgrade	sysupgrade to snapshot
    upgrade	upgrade with snapshot
EOF
    exit(2);
};
$opts{h} or die "No -h specified";
my $patch = $opts{P};

@ARGV or die "No mode specified";
my %setupmode;
foreach my $mode (@ARGV) {
    grep { $_ eq $mode } @allsetupmodes
	or die "Unknown setup mode '$mode'";
    $setupmode{$mode} = 1;
}
foreach my $mode (qw(install keep reboot sysupgrade upgrade)) {
    die "Setup mode '$mode' must be used solely"
	if $setupmode{$mode} && keys %setupmode != 1;
}

# better get an errno than random kill by SIGPIPE
$SIG{PIPE} = 'IGNORE';

# create directory for this test run with timestamp 2016-07-13T12:30:42Z
my $regressdir = dirname($0). "/..";
chdir($regressdir)
    or die "Change directory to '$regressdir' failed: $!";
$regressdir = getcwd();
my $resultdir = "$regressdir/results/$date";
mkdir $resultdir
    or die "Make directory '$resultdir' failed: $!";
unlink("results/current");
symlink($date, "results/current")
    or die "Make symlink 'results/current' failed: $!";
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

createlog(file => "run.log", verbose => $opts{v});
logmsg("$date Script '$scriptname' started.\n");

open(my $fh, '>', "runconf.txt")
    or die "Open 'runconf.txt' for writing failed: $!";
print $fh "ARGUMENTS @ARGV\n";
print $fh "HOST $opts{h}\n";
print $fh "SETUPMODE ", join(" ", sort keys %setupmode), "\n";
close($fh);

# setup remote machines

usehosts(bindir => "$regressdir/bin", date => $date,
    host => $opts{h}, verbose => $opts{v});
(my $host = $opts{h}) =~ s/.*\@//;

# do not run end block until initialized, date may change later
my $odate = $date;
END {
    if ($odate) {
	bsdcons_hosts();
	relogdie();
    }
    if ($regressdir) {
	my @cmd = ("$regressdir/bin/setup-html.pl");
	system(@cmd);
	@cmd = ("$regressdir/bin/running-html.pl");
	system(@cmd);
    }
};
if ($patch || !($setupmode{keep} || $setupmode{reboot})) {
    setup_hosts(patch => $patch, mode => \%setupmode);
} elsif (!$setupmode{reboot}) {
    powerup_hosts(patch => $patch);
} else {
    reboot_hosts(patch => $patch);
}
collect_version();
setup_html();

# run regression tests remotely

chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

my @sshcmd = ('ssh', $opts{h}, 'perl', '/root/regress/regress.pl',
    '-e', "/root/regress/env-$host.sh", '-v');
logcmd(@sshcmd);

# get result and logs

collect_result("$opts{h}:/root/regress");
collect_dmesg();
setup_html();
powerdown_hosts(patch => $patch) if $opts{p};
bsdcons_hosts();
undef $odate;

# create html output

chdir($regressdir)
    or die "Change directory to '$regressdir' failed: $!";

setup_html(date => 1);
runcmd("bin/regress-html.pl", "-h", $host, "src");

unlink("results/latest-$host");
symlink($date, "results/latest-$host")
    or die "Make symlink 'results/latest-$host' failed: $!";
unlink("results/latest");
symlink($date, "results/latest")
    or die "Make symlink 'results/latest' failed: $!";
runcmd("bin/regress-html.pl", "-l", "src");

# do not create all page, it is too slow and too large
#runcmd("bin/regress-html.pl", "src");

my $now = strftime("%FT%TZ", gmtime);
logmsg("$now Script '$scriptname' finished.\n");

exit;
