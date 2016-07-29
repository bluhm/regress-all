#!/usr/bin/perl
# setup machine for regress test

use strict;
use warnings;
use File::Basename;
use Getopt::Std;

my %opts;
getopts('h:v', \%opts) or do {
    print STDERR "usage: $0 [-v] -h host\n";
    exit(2);
};
$opts{h} or die "No -h specified";

my $dir = dirname($0);
chdir($dir)
    or die "Chdir to '$dir' failed: $!";

(my $host = $opts{h}) =~ s/.*\@//;

my $setuplog = "../results/setup-$host.log";
open(my $log, '>', $setuplog)
    or die "Open '$setuplog' for writing failed: $!";
$log->autoflush();
$| = 1;

# pxe install machine

my @sshcmd = ('ssh', "$host\@10.0.1.1",  'setup');
defined(my $pid = open(my $out, '-|', @sshcmd))
    or die "Open pipe from '@sshcmd' failed: $!";
if ($pid == 0) {
    close($out);
    open(STDIN, '<', "/dev/null")
	or warn "Redirect stdin to /dev/null failed: $!";
    open(STDERR, '>&', \*STDOUT)
	or warn "Redirect stderr to stdout failed: $!";
    setsid()
	or warn "Setsid $$ failed: $!";
    exec(@sshcmd);
    warn "Exec '@sshcmd' failed: $!";
    _exit(126);
}
while (<$out>) {
    print $log $_;
    s/[^\s[:print:]]/_/g;
    print if $opts{v};
}
close($out) or die $! ?
    "Close pipe from '@sshcmd' failed: $!" :
    "Command '@sshcmd' failed: $?";

# copy scripts

@sshcmd = ('ssh', $opts{h}, 'mkdir', '-p', '/root/regress');
system(@sshcmd)
    and die "Command '@sshcmd' failed: $?";

my @copy = grep { -f $_ }
    ("regress.pl", "env-$host.sh", "pkg-$host.list", "test.list");
my @scpcmd = ('scp');
push @scpcmd, '-q' unless $opts{v};
push @scpcmd, (@copy, "$opts{h}:/root/regress");
system(@scpcmd)
    and die "Command '@scpcmd' failed: $?";

# cvs checkout

my ($quiet, $noout) = ("", "");
$quiet = "-q" unless $opts{v};
$noout = ">/dev/null" unless $opts{v};
@sshcmd = ('ssh', $opts{h},
    "cd /usr && cvs $quiet -R -d /mount/openbsd/cvs co src/regress $noout");
system(@sshcmd)
    and die "Command '@sshcmd' failed: $?";

# install packages

if (-f "pkg-$host.list") {
    @sshcmd = ('ssh', $opts{h}, 'pkg_add', '-l', "regress/pkg-$host.list",
	'-Ix');
    push @sshcmd, '-v' if $opts{v};
    system(@sshcmd)
	and die "Command '@sshcmd' failed: $?";
}
