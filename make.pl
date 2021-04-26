#!/usr/bin/perl
# make build and release on machine

# Copyright (c) 2016-2021 Alexander Bluhm <bluhm@genua.de>
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
getopts('d:h:r:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] -h host mode ...
    -h host	user and host for make release, user defaults to root
    -v		verbose
    build	build system from source /usr/src
    cvs		clean cvs update /usr/src and make obj
    kernel	build kernel from source /usr/src/sys
    keep	keep installed host as is, skip setup
EOF
    exit(2);
};
$opts{h} or die "No -h specified";

my %allmodes;
@allmodes{qw(build cvs kernel keep)} = ();
@ARGV or die "No mode specified";
my %mode = map {
    die "Unknown mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV;
foreach (qw(keep)) {
    die "Mode must be used solely: $_" if $mode{$_} && keys %mode != 1;
}

# better get an errno than random kill by SIGPIPE
$SIG{PIPE} = 'IGNORE';

# create directory for this test run with timestamp 2016-07-13T12:30:42Z
my $date = strftime("%FT%TZ", gmtime);

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

createlog(file => "make.log", verbose => $opts{v});
logmsg("Script '$scriptname' started at $date.\n");

open(my $fh, '>', "makeconf.txt")
    or die "Open 'makeconf.txt' for writing failed: $!";
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
	my @cmd = ("$regressdir/bin/bsdcons.pl", '-h', $opts{h}, '-d', $odate);
	system(@cmd);
	@cmd = ("$regressdir/bin/setup-html.pl");
	system(@cmd);
    }
};
setup_hosts(mode => \%mode) unless $mode{keep};
collect_version();
setup_html();

# run make release remotely

chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

(my $host = $opts{h}) =~ s/.*\@//;
my @sshcmd = ('ssh', $opts{h}, 'perl', '/root/release/release.pl',
    '-e', "/root/portstest/env-$host.sh", '-v');
logcmd(@sshcmd);

# get result and logs

my @scpcmd = ('scp');
push @scpcmd, '-q' unless $opts{v};
push @scpcmd, ("$opts{h}:/root/release/test.*", $resultdir);
runcmd(@scpcmd);

my $logdir = "$resultdir/logs";
mkdir $logdir
    or die "Make directory '$logdir' failed: $!";
chdir($logdir)
    or die "Change directory to '$logdir' failed: $!";
@scpcmd = ('scp');
push @scpcmd, '-q' unless $opts{v};
push @scpcmd, ("$opts{h}:/usr/src/make.log", $logdir);
runcmd(@scpcmd);

chdir($resultdir)
    or die "Change directory to '$resultdir' failed: $!";

collect_dmesg();
setup_html();

# create html output

chdir($regressdir)
    or die "Change directory to '$regressdir' failed: $!";

setup_html(date => 1);

$date = strftime("%FT%TZ", gmtime);
logmsg("Script '$scriptname' finished at $date.\n");

exit;
