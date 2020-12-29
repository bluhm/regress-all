#!/usr/bin/perl

# Copyright (c) 2016-2020 Alexander Bluhm <bluhm@genua.de>
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

my $scriptname = "$0 @ARGV";

my %opts;
getopts('h:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] -h host mode ...
    -h host	user and host for make test, user defaults to root
    -v		verbose
    ports	cvs update /usr/ports
    keep	keep installed host as is, skip setup
EOF
    exit(2);
};
$opts{h} or die "No -h specified";

my %allmodes;
@allmodes{qw(keep ports)} = ();
@ARGV or die "No mode specified";
my %mode = map {
    die "Unknown mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV;
foreach (qw(keep ports)) {
    die "Mode must be used solely: $_" if $mode{$_} && keys %mode != 1;
}

# better get an errno than random kill by SIGPIPE
$SIG{PIPE} = 'IGNORE';

# create directory for this test run with timestamp 2016-07-13T12:30:42Z
my $date = strftime("%FT%TZ", gmtime);

my $regressdir = dirname($0). "/..";
chdir($regressdir)
    or die "Chdir to '$regressdir' failed: $!";
$regressdir = getcwd();
my $resultdir = "$regressdir/results/$date";
mkdir $resultdir
    or die "Make directory '$resultdir' failed: $!";
unlink("results/current");
symlink($date, "results/current")
    or die "Make symlink 'results/current' failed: $!";
chdir($resultdir)
    or die "Chdir to '$resultdir' failed: $!";

createlog(file => "test.log", verbose => $opts{v});
logmsg("Script '$scriptname' started at $date.\n");

open(my $fh, '>', "testconf.txt")
    or die "Open 'testconf.txt' for writing failed: $!";
print $fh "ARGUMENTS @ARGV\n";
print $fh "HOST $opts{h}\n";
print $fh "MODE ", join(" ", sort keys %mode), "\n";
close($fh);

# setup remote machines

usehosts(bindir => "$regressdir/bin", date => $date,
    host => $opts{h}, verbose => $opts{v});

# do not run end block until initialized, date may change later
my $odate = $date;
END {
    if ($odate) {
	my @cmd = ("$regressdir/bin/setup-html.pl");
	system(@cmd);
    }
};
setup_hosts(mode => \%mode) unless $mode{keep};
collect_version();
setup_html();

# run port tests remotely

chdir($resultdir)
    or die "Chdir to '$resultdir' failed: $!";

(my $host = $opts{h}) =~ s/.*\@//;
my @sshcmd = ('ssh', $opts{h}, 'perl', '/root/portstest/portstest.pl',
    '-e', "/root/portstest/env-$host.sh", '-v');
logcmd(@sshcmd);

# get result and logs

my @scpcmd = ('scp');
push @scpcmd, '-q' unless $opts{v};
push @scpcmd, ("$opts{h}:/root/portstest/test.*", $resultdir);
runcmd(@scpcmd);

open(my $tr, '<', "test.result")
    or die "Open 'test.result' for reading failed: $!";
my $logdir = "$resultdir/logs";
mkdir $logdir
    or die "Make directory '$logdir' failed: $!";
chdir($logdir)
    or die "Chdir to '$logdir' failed: $!";
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
    or die "Close 'test.result' after reading failed: $!";

chdir($resultdir)
    or die "Chdir to '$resultdir' failed: $!";

collect_dmesg();
setup_html();

# create html output

chdir($regressdir)
    or die "Chdir to '$regressdir' failed: $!";

setup_html(date => 1);
runcmd("bin/regress-html.pl", "-h", $host, "ports");
runcmd("bin/regress-html.pl", "ports");

unlink("results/latest-$host");
symlink($date, "results/latest-$host")
    or die "Make symlink 'results/latest-$host' failed: $!";
unlink("results/latest");
symlink($date, "results/latest")
    or die "Make symlink 'results/latest' failed: $!";
runcmd("bin/regress-html.pl", "-l", "ports");

$date = strftime("%FT%TZ", gmtime);
logmsg("Script '$scriptname' finished at $date.\n");

exit;
