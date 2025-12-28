#!/usr/bin/perl

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

my $now = strftime("%FT%TZ", gmtime);
my $scriptname = "$0 @ARGV";

my @allsetupmodes = qw(commands keep ports);

my %opts;
getopts('h:pv', \%opts) or do {
    print STDERR <<"EOF";
usage: test.pl [-pv] -h host setup ...
    -h host	user and host for make test, user defaults to root
    -p		power down after testing
    -v		verbose
    setup ...	setup mode: @allsetupmodes
    commands	run commands needed for ports tests
    ports	cvs update /usr/ports
    keep	keep installed host as is, skip setup
EOF
    exit(2);
};
$opts{h} or die "No -h specified";

@ARGV or die "No setup mode specified";
my %setupmode;
foreach my $mode (@ARGV) {
    grep { $_ eq $mode } @allsetupmodes
	or die "Unknown setup mode '$mode'";
    $setupmode{$mode} = 1;
}
foreach my $mode (qw(keep)) {
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
my $date = $now;
my $resultdir = "$regressdir/results/$date";
mkdir $resultdir
    or die "Make directory '$resultdir' failed: $!";
unlink("results/current");
symlink($date, "results/current")
    or die "Make symlink 'results/current' failed: $!";
chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

createlog(file => "test.log", verbose => $opts{v});
logmsg("$now Script '$scriptname' started.\n");

open(my $fh, '>', "testconf.txt")
    or die "Open 'testconf.txt' for writing failed: $!";
print $fh "ARGUMENTS @ARGV\n";
print $fh "HOST $opts{h}\n";
print $fh "SETUPMODE ", join(" ", sort keys %setupmode), "\n";
close($fh);

# setup remote machines

usehosts(bindir => "$regressdir/bin", date => $date,
    host => $opts{h}, lasthost => $opts{h}, verbose => $opts{v});
(my $host = $opts{h}) =~ s/.*\@//;

# do not run end block until initialized, date may change later
my $odate = $date;
END {
    if ($odate) {
	my @cmd = ("$regressdir/bin/bsdcons.pl", '-h', $opts{h}, '-d', $odate);
	system(@cmd);
    }
    if ($regressdir) {
	my @cmd = ("$regressdir/bin/setup-html.pl");
	system(@cmd);
	@cmd = ("$regressdir/bin/running-html.pl");
	system(@cmd);
    }
};
if (!$setupmode{keep}) {
    setup_hosts(mode => \%setupmode);
} else {
    powerup_hosts();
}
collect_version();
setup_html();

# run port tests remotely

chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

my @sshcmd = ('ssh', $opts{h}, 'perl', '/root/portstest/portstest.pl',
    '-e', "/root/portstest/env-$host.sh", '-v');
logcmd(@sshcmd);

# get result and logs

collect_result("$opts{h}:/root/portstest");
collect_dmesg();
setup_html();
powerdown_hosts() if $opts{p};
bsdcons_hosts();
undef $odate;

# create html output

chdir($regressdir)
    or die "Change directory to '$regressdir' failed: $!";

setup_html(date => 1);
runcmd("bin/regress-html.pl", "-h", $host, "ports");

unlink("results/latest-$host");
symlink($date, "results/latest-$host")
    or die "Make symlink 'results/latest-$host' failed: $!";
unlink("results/latest");
symlink($date, "results/latest")
    or die "Make symlink 'results/latest' failed: $!";
logeval { runcmd("bin/regress-html.pl", "-l", "ports") };

# do not create all page, it is too slow and too large
#runcmd("bin/regress-html.pl", "ports");

$now = strftime("%FT%TZ", gmtime);
logmsg("$now Script '$scriptname' finished.\n");

exit;
