#!/usr/bin/perl

# Copyright (c) 2016-2018 Alexander Bluhm <bluhm@genua.de>
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

my $scriptname = "$0 @ARGV";

my %opts;
getopts('h:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] -h host mode ...
    -h host	optional user and host for make regress, user defaults to root
    -v		verbose
    build	build system from source /usr/src
    cvs		cvs update /usr/src and make obj
    install	install from snapshot
    keep	keep installed host as is, skip setup
    kernel	build kernel from source /usr/src/sys
    upgrade	upgrade with snapshot
EOF
    exit(2);
};
$opts{h} or die "No -h specified";

my %allmodes;
@allmodes{qw(build cvs install keep kernel upgrade)} = ();
@ARGV or die "No mode specified";
my %mode = map {
    die "Unknown mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV;
foreach (qw(install keep upgrade)) {
    die "Mode must be used solely: $_" if $mode{$_} && keys %mode != 1;
}

# create directory for this test run with timestamp 2016-07-13T12:30:42Z
my $date = strftime("%FT%TZ", gmtime);

my $dir = dirname($0). "/..";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";
my $regressdir = getcwd();
$dir = "results";
-d $dir || mkdir $dir
    or die "Make result directory '$dir' failed: $!";
$dir .= "/$date";
mkdir $dir
    or die "Make directory '$dir' failed: $!";
unlink("results/current");
symlink($date, "results/current")
    or die "Make symlink 'results/current' failed: $!";

createlog(file => "$dir/run.log", verbose => $opts{v});
logmsg("script '$scriptname' started at $date\n");

# setup remote machines

my ($user, $host) = split('@', $opts{h}, 2);
($user, $host) = ("root", $user) unless $host;
my ($firsthost, $lasthost) = $host;

unless ($mode{keep}) {
    my @pidcmds;
    my @setupcmd = ("bin/setup.pl", '-h', "$user\@$host", '-d', $date);
    push @setupcmd, '-v' if $opts{v};
    push @setupcmd, keys %mode;
    push @pidcmds, forkcmd(@setupcmd);

    if ($mode{install} || $mode{upgrade}) {
	# change config of dhcpd has races, cannot install simultaneously
	sleep 1;
	runcmd("$regressdir/bin/setup-html.pl");
	waitcmd(@pidcmds);
	undef @pidcmds;
    }

    $host++;
    # XXX hack to find out whether a remote machine exists
    if (-f "bin/pkg-$host.list") {
	@setupcmd = ("bin/setup.pl", '-h', "$user\@$host", '-d', $date);
	push @setupcmd, '-v' if $opts{v};
	push @setupcmd, keys %mode;
	push @pidcmds, forkcmd(@setupcmd);
    }
    $lasthost = $host;

    # create new summary with setup log
    sleep 1;
    runcmd("$regressdir/bin/setup-html.pl");
    waitcmd(@pidcmds);
}
runcmd("$regressdir/bin/setup-html.pl");

for ($host = $firsthost; $host; $host++) {
    my $h = "$user\@$host";
    my $version = "$dir/version-$host.txt";
    eval { logcmd({
	cmd => ['ssh', $h, 'sysctl', 'kern.version', 'hw.machine', 'hw.ncpu'],
	outfile => $version,
    })};
    if ($@) {
	unlink $version;
	last;
    }
    my $dmesg = "$dir/dmesg-boot-$host.txt";
    eval { logcmd({
	cmd => ['ssh', $h, 'cat', '/var/run/dmesg.boot'],
	outfile => $dmesg,
    })};
    if ($@) {
	unlink $dmesg;
    }
    last if $host eq $lasthost;
}

# run regress there

($host = $opts{h}) =~ s/.*\@//;
my @sshcmd = ('ssh', $opts{h}, 'perl', '/root/regress/regress.pl',
    '-e', "/root/regress/env-$host.sh", '-v');
logcmd(@sshcmd);

# get result and logs

my @scpcmd = ('scp');
push @scpcmd, '-q' unless $opts{v};
push @scpcmd, ("$opts{h}:/root/regress/test.*", $dir);
runcmd(@scpcmd);

open(my $tr, '<', "$dir/test.result")
    or die "Open '$dir/test.result' for reading failed: $!";
mkdir "$dir/logs"
    or die "Make directory '$dir/logs' failed: $!";
chdir("$dir/logs")
    or die "Chdir to '$dir/logs' failed: $!";
my @paxcmd = ('pax', '-rzf', "../test.log.tgz");
open(my $pax, '|-', @paxcmd)
    or die "Open pipe to '@paxcmd' failed: $!";
while (<$tr>) {
    my ($status, $test, $message) = split(" ", $_, 3);
    print $pax "$test/make.log" unless $test =~ m,[^\w/],;
}
close($pax) or die $! ?
    "Close pipe to '@paxcmd' failed: $!" :
    "Command '@paxcmd' failed: $?";
close($tr)
    or die "Close '$dir/test.result' after reading failed: $!";

chdir($regressdir)
    or die "Chdir to '$regressdir' failed: $!";

for ($host = $firsthost; $host; $host++) {
    my $h = "$user\@$host";
    my $dmesg = "$dir/dmesg-$host.txt";
    eval { logcmd({
	cmd => ['ssh', $h, 'dmesg'],
	outfile => $dmesg,
    })};
    if ($@) {
	unlink $dmesg;
    }
    last if $host eq $lasthost;
}

# create html output

runcmd("bin/setup-html.pl");
runcmd("bin/regress-html.pl", "-h", $firsthost);
runcmd("bin/regress-html.pl");

unlink("results/latest-$firsthost");
symlink($date, "results/latest-$firsthost")
    or die "Make symlink 'results/latest-$firsthost' failed: $!";
unlink("results/latest");
symlink($date, "results/latest")
    or die "Make symlink 'results/latest' failed: $!";
runcmd("bin/regress-html.pl", "-l", "-h", $firsthost);
runcmd("bin/regress-html.pl", "-l");

$date = strftime("%FT%TZ", gmtime);
logmsg("script '$scriptname' finished at $date\n");
