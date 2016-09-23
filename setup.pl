#!/usr/bin/perl
# setup machine for regress test

use strict;
use warnings;
use Cwd;
use File::Basename;
use Getopt::Std;
use POSIX;

use lib dirname($0);
use Logcmd;

my %opts;
getopts('d:h:v', \%opts) or do {
    print STDERR "usage: $0 [-v] [-d date] -h host\n";
    exit(2);
};
$opts{h} or die "No -h specified";
my $date = $opts{d};

my $dir = dirname($0). "/..";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";
my $regressdir = getcwd();
$dir = "results";
$dir .= "/$date" if $date;
chdir($dir)
    or die "Chdir to '$dir' failed: $!";

(my $host = $opts{h}) =~ s/.*\@//;
createlog(file => "setup-$host.log", verbose => $opts{v});
$date = strftime("%FT%TZ", gmtime);
logmsg("script $0 started at $date\n");

# create new summary with setup log

runcmd("$regressdir/bin/setup-html.pl");

# pxe install machine

logcmd('ssh', "$host\@10.0.1.1", 'setup');

# get version information

my @sshcmd = ('ssh', $opts{h}, 'sysctl', 'kern.version', 'hw.machine');
logmsg "Command '@sshcmd' started\n";
open(my $sysctl, '-|', @sshcmd)
    or die "Open pipe from '@sshcmd' failed: $!";
open(my $version, '>', "version-$host.txt")
    or die "Open 'version-$host.txt' for writing failed: $!";
print $version (<$sysctl>);
close($sysctl) or die $! ?
    "Close pipe from '@sshcmd' failed: $!" :
    "Command '@sshcmd' failed: $?";
logmsg "Command '@sshcmd' finished\n";

# copy scripts

runcmd('ssh', $opts{h}, 'mkdir', '-p', '/root/regress');

$dir = "$regressdir/bin";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";
my @copy = grep { -f $_ }
    ("regress.pl", "env-$host.sh", "pkg-$host.list", "test.list", "site.list");
my @scpcmd = ('scp');
push @scpcmd, '-q' unless $opts{v};
push @scpcmd, (@copy, "$opts{h}:/root/regress");
runcmd(@scpcmd);

# cvs checkout

logcmd('ssh', $opts{h},
    "cd /usr && cvs -R -d /mount/openbsd/cvs co src");
logcmd('ssh', $opts{h},
    "cd /usr/src && make obj");

# install packages

eval {
    logcmd('ssh', $opts{h}, 'pkg_add', '-l', "regress/pkg-$host.list", '-Ivx')
	if -f "pkg-$host.list";
};
logmsg "WARNING: command failed\n" if $@;

$date = strftime("%FT%TZ", gmtime);
logmsg("script $0 finished at $date\n");
